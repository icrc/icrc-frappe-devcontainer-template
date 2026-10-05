#!/usr/bin/env bash
# repo-status.sh
# Reports the git status of every repository here: this container repository,
# plus every app checked out under development/frappe-bench/apps/.
#
# A bench is a dozen independent checkouts, each with its own remote, branches
# and pull requests, and the bench directory is gitignored, so `git status`
# says nothing about any of them. This walks all of them in one pass.
#
# Usage:
#   repo-status.sh                 # root inferred from the working directory
#   repo-status.sh ROOT            # explicit repository root
#   repo-status.sh --fetch         # refresh remote-tracking refs first (network)
#   repo-status.sh --pull          # --fetch, then fast-forward what can be (writes)
#   repo-status.sh --verbose       # add the remote and the changed files per repo
#   repo-status.sh --porcelain     # one tab-separated line per repo, for scripts
#
# The root is the repository this script lives in, so a bare call reports the
# same set whatever the working directory is. Pass ROOT to point it elsewhere.
#
# Columns:
#   SYNC      in sync, ahead N, behind N, no upstream, or detached
#   WORKTREE  clean, or !conflicts +staged ~unstaged ?untracked
#   STALE     local branches behind their upstream, the current one aside
#
# SYNC covers the checked-out branch only, so STALE is what says whether the
# rest of the local branches are current: a default branch left behind weeks ago
# is invisible on a checkout that sits on a topic branch.
#
# --pull fast-forwards every local branch that is behind its upstream with
# nothing of its own on top: the checked-out one with merge --ff-only, and only
# when no tracked file is modified, the others by moving their ref, which leaves
# the working tree alone. A diverged branch is left alone, as is a repository
# whose fetch failed. Nothing is rewritten and nothing is merged, so every move
# is undoable from the branch reflog.
#
# --porcelain fields, tab-separated, in order: path, branch, sync, worktree,
# stashes, age, subject, upstream, ahead, behind, staged, unstaged, untracked,
# stale. The subject is never truncated there, unlike in the table.
#
# Ahead and behind are read from the remote-tracking refs on disk, so they are
# only as fresh as the last fetch; the header says which.
#
# Exit status: 0 when the report was produced, 2 on a usage or root error. A
# dirty or unsynced repository is a finding to read, not a failure.

set -uo pipefail

FETCH=0
PULL=0
VERBOSE=0
PORCELAIN=0
ROOT_ARG=""
BRANCH_MAX=24    # a long topic branch name would otherwise widen every row
SUBJECT_MAX=44   # fallback when the terminal width is unknown, as in a pipe

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fetch) FETCH=1; shift ;;
        # Being behind cannot be known without a fetch, so --pull implies it.
        --pull) PULL=1; FETCH=1; shift ;;
        -v | --verbose) VERBOSE=1; shift ;;
        --porcelain) PORCELAIN=1; shift ;;
        -h | --help) sed -n '3,46p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        -*) echo "repo-status: unknown option $1" >&2; exit 2 ;;
        *) ROOT_ARG="$1"; shift ;;
    esac
done

# The repository this script belongs to, whatever the working directory is and
# whatever this repository is itself nested inside. Walking up from $PWD would
# report the wrong tree for a clone made inside another checkout.
script_repo_root() {
    git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null
}

if [[ -n "$ROOT_ARG" ]]; then
    [[ -d "$ROOT_ARG" ]] || { echo "repo-status: not a directory: $ROOT_ARG" >&2; exit 2; }
    ROOT="$(cd "$ROOT_ARG" && pwd)"
else
    ROOT="$(script_repo_root)"
    [[ -n "$ROOT" ]] || {
        echo "repo-status: no git repository around $0, pass a root" >&2
        exit 2
    }
fi

repos=()
git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null && repos+=("$ROOT")
APPS_DIR="${APPS_DIR:-$ROOT/development/${BENCH_NAME:-frappe-bench}/apps}"
if [[ -d "$APPS_DIR" ]]; then
    # -prune stops find descending into the .git directory it just matched.
    # Depth 2 is apps/<app>/.git and nothing deeper: an app's own vendored
    # checkout is that app's business, not the bench's.
    while IFS= read -r gitdir; do
        repos+=("${gitdir%/.git}")
    done < <(find "$APPS_DIR" -maxdepth 2 -name .git -prune -print 2>/dev/null | sort)
fi

if [[ ${#repos[@]} -eq 0 ]]; then
    echo "repo-status: no git repository found in $ROOT" >&2
    exit 2
fi

sync_label() { # head upstream ahead behind
    local head="$1" up="$2" a="$3" b="$4" s=""
    [[ "$head" == "(detached)" ]] && { printf 'detached'; return; }
    [[ "$up" == "-" ]] && { printf 'no upstream'; return; }
    ((a == 0 && b == 0)) && { printf 'in sync'; return; }
    ((a)) && s="ahead $a"
    ((b)) && s="${s:+$s }behind $b"
    printf '%s' "$s"
}

tree_label() { # conflicts staged unstaged untracked
    local cf="$1" st="$2" un="$3" ut="$4" s=""
    ((cf)) && s+="!$cf "
    ((st)) && s+="+$st "
    ((un)) && s+="~$un "
    ((ut)) && s+="?$ut "
    [[ -z "$s" ]] && { printf 'clean'; return; }
    printf '%s' "${s% }"
}

# A clone URL can carry credentials as userinfo (https://user:<token>@host/...).
# Strip it before printing: the URL is context, the token is a secret.
scrub_url() { printf '%s' "$1" | sed 's#://[^/@]*@#://#'; }

n_label() { # count singular plural
    (($1 == 1)) && { printf '%s %s' "$1" "$2"; return; }
    printf '%s %s' "$1" "$3"
}

# One line per local branch: name, upstream ref, and how the two diverge, as
# "behind 3", "ahead 1, behind 2", empty when in sync, "gone" when the upstream
# branch no longer exists. This is the whole of what STALE and --pull need.
branch_tracking() { # repo
    git -C "$1" for-each-ref refs/heads \
        --format='%(refname:short)|%(upstream)|%(upstream:track,nobracket)' 2>/dev/null
}

declare -A fetch_failed=()

if ((FETCH)); then
    # Bounded so a blocked or proxied remote cannot hang the report.
    timeout_cmd=()
    command -v timeout &>/dev/null && timeout_cmd=(timeout 60)
    for repo in "${repos[@]}"; do
        rel="${repo#"$ROOT"/}"
        [[ "$repo" == "$ROOT" ]] && rel="."
        # A repository with no remote has nothing to fetch, and the SYNC column
        # already says so. Skipping it keeps the warnings meaningful.
        [[ -n "$(git -C "$repo" remote 2>/dev/null)" ]] || continue
        if ! "${timeout_cmd[@]}" git -C "$repo" fetch --quiet 2>/dev/null; then
            fetch_failed["$repo"]=1
            echo "WARN  $rel: fetch failed, its ahead and behind counts are stale" >&2
        fi
    done
fi

pull_log=()
pulled=0

if ((PULL)); then
    for repo in "${repos[@]}"; do
        rel="${repo#"$ROOT"/}"
        [[ "$repo" == "$ROOT" ]] && rel="."

        # Same rule as pr-sync.sh: a failed fetch makes every count below it
        # untrustworthy, so nothing moves in that repository.
        if [[ -n "${fetch_failed[$repo]:-}" ]]; then
            pull_log+=("$rel: left alone, its fetch failed")
            continue
        fi

        head_branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
        # Tracked changes only: an untracked file cannot block a fast-forward
        # unless the merge would overwrite it, and git refuses that by itself.
        tracked_dirty=0
        git -C "$repo" diff --quiet HEAD -- 2>/dev/null || tracked_dirty=1

        while IFS='|' read -r b up track; do
            [[ -n "$b" && -n "$up" && "$track" == *behind* ]] || continue
            if [[ "$track" == *ahead* ]]; then
                pull_log+=("$rel $b: left alone, diverged ($track)")
                continue
            fi
            rc=0
            if [[ "$b" == "$head_branch" ]]; then
                if ((tracked_dirty)); then
                    pull_log+=("$rel $b: left alone, uncommitted changes ($track)")
                    continue
                fi
                out="$(git -C "$repo" merge --ff-only --quiet "$up" 2>&1)" || rc=$?
            else
                # A branch that is not checked out moves by ref update alone, so
                # no file changes and no clean-tree requirement. fetch refuses
                # anything but a fast-forward, and refuses a branch checked out
                # in another worktree, which is the guard this relies on.
                out="$(git -C "$repo" fetch --quiet . "$up:refs/heads/$b" 2>&1)" || rc=$?
            fi
            if ((rc == 0)); then
                pulled=$((pulled + 1))
                pull_log+=("$rel $b: fast-forwarded $(n_label "${track#behind }" commit commits)")
            else
                pull_log+=("$rel $b: fast-forward failed, ${out//$'\n'/ }")
            fi
        done < <(branch_tracking "$repo")
    done
fi

rows=()
dirty=0
unpushed=0
no_upstream=0
stale_repos=0

for repo in "${repos[@]}"; do
    rel="${repo#"$ROOT"/}"
    [[ "$repo" == "$ROOT" ]] && rel="."

    status_out="$(git -C "$repo" status --porcelain=v2 --branch -unormal 2>/dev/null)" || status_out=""
    if [[ -z "$status_out" ]]; then
        # No field is left empty: IFS=tab collapses runs of tabs, so an empty
        # field would shift every column after it when a row is read back.
        rows+=("$rel"$'\t'"-"$'\t'"unreadable"$'\t'"-"$'\t'"0"$'\t'"-"$'\t'"git could not read this repository"$'\t'"-"$'\t'"0"$'\t'"0"$'\t'"0"$'\t'"0"$'\t'"0"$'\t'"0")
        continue
    fi

    # One status call per repository carries the branch, its divergence and every
    # changed path. Porcelain v2 marks an unchanged half of XY with a dot.
    read -r head oid up ahead behind staged unstaged untracked conflicts < <(
        printf '%s\n' "$status_out" | awk '
            /^# branch\.head /     { head = $3 }
            /^# branch\.oid /      { oid = $3 }
            /^# branch\.upstream / { up = $3 }
            /^# branch\.ab /       { a = substr($3, 2) + 0; b = substr($4, 2) + 0 }
            /^[12] / {
                if (substr($2, 1, 1) != ".") st++
                if (substr($2, 2, 1) != ".") un++
            }
            /^u / { cf++ }
            /^\? / { ut++ }
            END {
                print (head == "" ? "-" : head), (oid == "" ? "-" : oid), \
                      (up == "" ? "-" : up), a + 0, b + 0, st + 0, un + 0, ut + 0, cf + 0
            }'
    )

    branch="$head"
    [[ "$head" == "(detached)" ]] && branch="detached@${oid:0:7}"

    stashes="$(git -C "$repo" stash list 2>/dev/null | wc -l | tr -d ' ')"

    if last="$(git -C "$repo" log -1 --format='%cr'$'\t''%s' 2>/dev/null)" && [[ -n "$last" ]]; then
        age="${last%%$'\t'*}"
        subject="${last#*$'\t'}"
    else
        age="-"
        subject="no commits yet"
    fi

    # The other local branches, which SYNC says nothing about. A diverged one
    # counts too: it is not up to date, and --pull deliberately leaves it.
    stale=0
    while IFS='|' read -r b bup btrack; do
        [[ -n "$b" && "$b" != "$head" && -n "$bup" && "$btrack" == *behind* ]] &&
            stale=$((stale + 1))
    done < <(branch_tracking "$repo")

    ((staged + unstaged + untracked + conflicts)) && dirty=$((dirty + 1))
    ((ahead)) && unpushed=$((unpushed + 1))
    [[ "$up" == "-" && "$head" != "(detached)" ]] && no_upstream=$((no_upstream + 1))
    ((stale)) && stale_repos=$((stale_repos + 1))

    rows+=("$rel"$'\t'"$branch"$'\t'"$(sync_label "$head" "$up" "$ahead" "$behind")"$'\t'"$(tree_label "$conflicts" "$staged" "$unstaged" "$untracked")"$'\t'"$stashes"$'\t'"$age"$'\t'"$subject"$'\t'"$up"$'\t'"$ahead"$'\t'"$behind"$'\t'"$staged"$'\t'"$unstaged"$'\t'"$untracked"$'\t'"$stale")
done

if ((PORCELAIN)); then
    # What --pull did is a side effect, not a row: keep it off the parsed stream.
    ((${#pull_log[@]})) && printf 'pull  %s\n' "${pull_log[@]}" >&2
    # path, branch, sync, worktree, stashes, age, subject, upstream, ahead,
    # behind, staged, unstaged, untracked, stale
    printf '%s\n' "${rows[@]}"
    exit 0
fi

clip() { # text max
    local t="$1" m="$2"
    ((${#t} > m)) && t="${t:0:$((m - 3))}..."
    printf '%s' "$t"
}

w_repo=4 w_branch=6 w_sync=4 w_tree=8 w_age=3
for row in "${rows[@]}"; do
    IFS=$'\t' read -r c_repo c_branch c_sync c_tree c_stash c_age _ <<< "$row"
    ((${#c_repo} > w_repo)) && w_repo=${#c_repo}
    ((${#c_branch} > w_branch)) && w_branch=${#c_branch}
    ((${#c_sync} > w_sync)) && w_sync=${#c_sync}
    ((${#c_tree} > w_tree)) && w_tree=${#c_tree}
    ((${#c_age} > w_age)) && w_age=${#c_age}
done
((w_branch > BRANCH_MAX)) && w_branch=$BRANCH_MAX

# Fit the subject to what the terminal leaves, and fall back to the fixed cap
# when there is no terminal to measure, as when the output is piped or read by
# an agent. The constants are the stash and stale columns and the seven
# two-space gaps.
term_cols=0
command -v tput &>/dev/null && term_cols="$(tput cols 2>/dev/null || echo 0)"
subject_max=$SUBJECT_MAX
if ((term_cols > 0)); then
    subject_max=$((term_cols - (w_repo + w_branch + w_sync + w_tree + w_age + 10 + 14)))
    ((subject_max < 16)) && subject_max=16
fi

echo "=== Repository git status ==="
echo "root: $ROOT"
if ((PULL)); then
    echo "refs: refreshed by --pull, $(n_label "$pulled" branch branches) fast-forwarded"
elif ((FETCH)); then
    echo "refs: refreshed by --fetch"
else
    echo "refs: as of the last fetch, so behind counts may be stale (--fetch refreshes)"
fi
if ((${#pull_log[@]})); then
    echo ""
    printf 'pull  %s\n' "${pull_log[@]}"
fi
echo ""

# shellcheck disable=SC2059  # the format string is built from measured widths
fmt="%-${w_repo}s  %-${w_branch}s  %-${w_sync}s  %-${w_tree}s  %5s  %5s  %-${w_age}s  %s\n"
printf "$fmt" REPO BRANCH SYNC WORKTREE STASH STALE AGE "LAST COMMIT"
for row in "${rows[@]}"; do
    IFS=$'\t' read -r c_repo c_branch c_sync c_tree c_stash c_age c_subject _ _ _ _ _ _ c_stale <<< "$row"
    [[ "$c_stash" == "0" ]] && c_stash="-"
    [[ "$c_stale" == "0" ]] && c_stale="-"
    printf "$fmt" "$c_repo" "$(clip "$c_branch" "$w_branch")" "$c_sync" "$c_tree" \
        "$c_stash" "$c_stale" "$c_age" "$(clip "$c_subject" "$subject_max")"
done

echo ""
echo "${#rows[@]} repositories: $dirty with uncommitted changes, $unpushed with unpushed commits, $no_upstream without an upstream, $stale_repos with a local branch behind its upstream."
echo "Legend: !conflicts +staged ~unstaged ?untracked (an untracked directory counts as one)."
echo "STALE is the local branches behind their upstream, the current one aside (--pull fast-forwards what it can)."

((VERBOSE)) || exit 0

for repo in "${repos[@]}"; do
    rel="${repo#"$ROOT"/}"
    [[ "$repo" == "$ROOT" ]] && rel="."
    echo ""
    echo "--- $rel ---"
    url="$(git -C "$repo" remote get-url origin 2>/dev/null)" && [[ -n "$url" ]] &&
        echo "origin: $(scrub_url "$url")"
    changed="$(git -C "$repo" status --short -unormal 2>/dev/null)"
    if [[ -n "$changed" ]]; then
        printf '%s\n' "$changed"
    else
        echo "(working tree clean)"
    fi
done

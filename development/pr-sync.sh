#!/usr/bin/env bash
# pr-sync.sh
# Brings a repository back to its default branch after its pull request was
# merged somewhere else, on GitHub or in another web UI, and removes the local
# feature branch the pull request came from.
#
# A squash merge is what makes this awkward by hand. It rewrites the branch into
# one new commit on the default branch, so the original commits are never
# ancestors of it and `git branch -d` refuses to delete a branch that is in fact
# merged. This collects the evidence, says which signal it used, and only then
# removes the branch.
#
# Usage:
#   pr-sync.sh --list                # candidate repositories, one line each
#   pr-sync.sh REPO                  # switch to the default branch, pull, tidy
#   pr-sync.sh REPO --branch NAME    # tidy that branch, not the one checked out
#   pr-sync.sh REPO --verified       # merge confirmed out of band, skip the git evidence
#   pr-sync.sh REPO --keep-branch    # switch and pull, leave the branch alone
#   pr-sync.sh REPO --dry-run        # print the plan, change nothing
#
# REPO is resolved against the repository root, not the shell, so a path copied
# out of --list means the same thing on the way back in and a stray cd cannot
# redirect the run to another checkout. An absolute path is taken as given.
#
# It never pushes, never force-pushes, never deletes a remote branch and never
# passes --no-verify. The only destructive act is deleting a local branch, and
# only once the merge is evidenced or asserted with --verified.
#
# Exit status: 0 done, 2 usage error, 3 refused (dirty worktree, diverged
# default branch, or a merge it could not evidence).

set -uo pipefail

LIST=0
VERIFIED=0
KEEP_BRANCH=0
DRY_RUN=0
REPO_ARG=""
BRANCH_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) LIST=1; shift ;;
        --verified) VERIFIED=1; shift ;;
        --keep-branch) KEEP_BRANCH=1; shift ;;
        --branch)
            [[ -n "${2:-}" ]] || { echo "pr-sync: --branch needs a branch name" >&2; exit 2; }
            BRANCH_ARG="$2"; shift 2 ;;
        -n | --dry-run) DRY_RUN=1; shift ;;
        -h | --help) sed -n '3,30p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        -*) echo "pr-sync: unknown option $1" >&2; exit 2 ;;
        *) REPO_ARG="$1"; shift ;;
    esac
done

# Same root rule as repo-status.sh: the repository this script lives in, so
# the candidate list is the same whatever the working directory is.
script_repo_root() {
    git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null
}

ROOT="$(script_repo_root)"
[[ -n "$ROOT" ]] || { echo "pr-sync: no git repository around $0" >&2; exit 2; }

# The default branch is per repository and must never be assumed: a Frappe app
# often uses develop or version-16, not main. Ask the remote rather than
# guessing, and only fall back to a guess when offline.
detect_default_branch() { # repo [allow_network]
    local repo="$1" allow="${2:-1}" ref
    ref="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
    [[ -n "$ref" ]] && { printf '%s' "${ref#origin/}"; return 0; }
    if ((allow)); then
        ref="$(git -C "$repo" ls-remote --symref origin HEAD 2>/dev/null |
            awk '$1 == "ref:" { print $2; exit }')"
        [[ -n "$ref" ]] && { printf '%s' "${ref#refs/heads/}"; return 0; }
    fi
    local candidate
    for candidate in main master develop; do
        git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$candidate" &&
            { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

worktree_state() { # repo -> clean, or a summary
    local repo="$1" out
    out="$(git -C "$repo" status --porcelain -unormal 2>/dev/null)"
    [[ -z "$out" ]] && { printf 'clean'; return; }
    printf '%s change(s)' "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
}

collect_repos() {
    local repos=()
    git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null && repos+=("$ROOT")
    local apps_dir="${APPS_DIR:-$ROOT/development/${BENCH_NAME:-frappe-bench}/apps}"
    if [[ -d "$apps_dir" ]]; then
        # Same walk as repo-status.sh.
        while IFS= read -r gitdir; do
            repos+=("${gitdir%/.git}")
        done < <(find "$apps_dir" -maxdepth 2 -name .git -prune -print 2>/dev/null | sort)
    fi
    printf '%s\n' "${repos[@]}"
}

rel_path() { # repo
    local repo="$1"
    [[ "$repo" == "$ROOT" ]] && { printf '.'; return; }
    printf '%s' "${repo#"$ROOT"/}"
}

if ((LIST)); then
    # No network here on purpose: this runs before the user has picked a
    # repository, and a fetch per checkout would make picking one slow.
    rows=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        rel="$(rel_path "$repo")"
        branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch="?"
        [[ "$branch" == "HEAD" ]] && branch="detached"
        default="$(detect_default_branch "$repo" 0)" || default="?"
        tree="$(worktree_state "$repo")"
        if [[ "$branch" == "detached" ]]; then
            ready="no, detached HEAD"
        elif [[ "$default" == "?" ]]; then
            ready="unknown, needs a fetch"
        elif [[ "$branch" == "$default" ]]; then
            ready="already on default"
        elif [[ "$tree" != "clean" ]]; then
            ready="no, uncommitted changes"
        else
            ready="yes"
        fi
        rows+=("$rel"$'\t'"$branch"$'\t'"$default"$'\t'"$tree"$'\t'"$ready")
    done < <(collect_repos)

    # Measured, not fixed: an app path and a topic branch name are both
    # long enough to shift every column after them if the widths are guessed.
    w_repo=4 w_branch=6 w_default=7 w_tree=8
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r c_repo c_branch c_default c_tree _ <<< "$row"
        ((${#c_repo} > w_repo)) && w_repo=${#c_repo}
        ((${#c_branch} > w_branch)) && w_branch=${#c_branch}
        ((${#c_default} > w_default)) && w_default=${#c_default}
        ((${#c_tree} > w_tree)) && w_tree=${#c_tree}
    done

    echo "=== Candidates for a post-merge sync ==="
    echo "root: $ROOT"
    echo ""
    # shellcheck disable=SC2059  # the format string is built from measured widths
    fmt="%-${w_repo}s  %-${w_branch}s  %-${w_default}s  %-${w_tree}s  %s\n"
    printf "$fmt" REPO BRANCH DEFAULT WORKTREE READY
    for row in "${rows[@]}"; do
        IFS=$'\t' read -r c_repo c_branch c_default c_tree c_ready <<< "$row"
        printf "$fmt" "$c_repo" "$c_branch" "$c_default" "$c_tree" "$c_ready"
    done
    echo ""
    echo "Pick one and run: pr-sync.sh <REPO>"
    exit 0
fi

[[ -n "$REPO_ARG" ]] || { echo "pr-sync: pass a repository, or --list to see the candidates" >&2; exit 2; }

# Resolved against the repository root first, deliberately, so that a path copied
# out of --list means the same thing here as it did there. Resolving against the
# shell instead made `pr-sync.sh .` act on whichever checkout the working
# directory happened to be left in, which is a silent wrong-repository bug.
if [[ "$REPO_ARG" == "." ]]; then
    REPO="$ROOT"
elif [[ "$REPO_ARG" == /* && -d "$REPO_ARG" ]]; then
    REPO="$(cd "$REPO_ARG" && pwd)"
elif [[ -d "$ROOT/$REPO_ARG" ]]; then
    REPO="$(cd "$ROOT/$REPO_ARG" && pwd)"
elif [[ -d "$REPO_ARG" ]]; then
    REPO="$(cd "$REPO_ARG" && pwd)"
    echo "pr-sync: '$REPO_ARG' is not under the repository root, taking it as $REPO" >&2
else
    echo "pr-sync: not a directory, under $ROOT or absolute: $REPO_ARG" >&2
    exit 2
fi
git -C "$REPO" rev-parse --is-inside-work-tree &>/dev/null ||
    { echo "pr-sync: not a git repository: $REPO" >&2; exit 2; }

REL="$(rel_path "$REPO")"
run() { # echo the command, then run it unless this is a dry run
    echo "  \$ $*"
    ((DRY_RUN)) && return 0
    "$@"
}

echo "=== Post-merge sync: $REL ==="
echo "path: $REPO"

BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"
# A detached HEAD is still workable when --branch names what to tidy, because
# then the branch to evaluate does not have to be the one checked out.
if [[ "$BRANCH" == "HEAD" && -z "$BRANCH_ARG" ]]; then
    echo "REFUSED: detached HEAD and no --branch given, so there is nothing to sync." >&2
    exit 3
fi

# Uncommitted work is the one thing this must never walk over: a checkout would
# carry it onto the default branch or fail outright, and either way it is the
# user's work in progress, not this script's to decide about.
TREE="$(worktree_state "$REPO")"
[[ "$TREE" == "clean" ]] || {
    echo "REFUSED: $TREE uncommitted in $REL." >&2
    echo "Commit, stash or discard them yourself, then run this again." >&2
    exit 3
}

DEFAULT="$(detect_default_branch "$REPO")" || {
    echo "REFUSED: could not determine the default branch of $REL." >&2
    exit 3
}
# The branch to tidy is the one checked out, unless --branch names another. That
# flag exists because the evidence can only be read after the switch and the
# pull, so a run that refuses leaves the checkout on the default branch and the
# branch it was asked about no longer reachable as HEAD.
TARGET="${BRANCH_ARG:-$BRANCH}"

if [[ "$TARGET" == "$DEFAULT" ]]; then
    if [[ -n "$BRANCH_ARG" ]]; then
        echo "REFUSED: --branch names $DEFAULT, the default branch, which is never deleted." >&2
        exit 2
    fi
else
    git -C "$REPO" show-ref --verify --quiet "refs/heads/$TARGET" || {
        echo "REFUSED: no local branch $TARGET in $REL." >&2
        exit 2
    }
fi

if [[ -n "$BRANCH_ARG" ]]; then
    echo "branch: $TARGET (named) -> default: $DEFAULT, currently on $BRANCH"
else
    echo "branch: $BRANCH -> default: $DEFAULT"
fi

# Keep the tip before anything moves: after a squash merge this sha is the only
# handle on what the branch held, and the evidence check below needs it.
BRANCH_SHA="$(git -C "$REPO" rev-parse "$TARGET" 2>/dev/null)"

# And whether it was ever pushed, read before the prune can remove the ref. A
# branch that never had an upstream has no origin/<branch> either, which would
# otherwise read exactly like one the host deleted on completion and get an
# unmerged branch deleted.
BRANCH_UPSTREAM="$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name \
    "$TARGET@{upstream}" 2>/dev/null)"

echo "fetching:"
run git -C "$REPO" fetch --prune --quiet || {
    echo "REFUSED: fetch failed for $REL, so nothing below could be trusted." >&2
    exit 3
}

if [[ "$BRANCH" != "$DEFAULT" ]]; then
    echo "switching:"
    run git -C "$REPO" switch "$DEFAULT" || {
        echo "REFUSED: could not switch to $DEFAULT." >&2
        exit 3
    }
fi

echo "pulling:"
# --ff-only on purpose. If the local default branch has diverged, that is a
# situation to look at, not to paper over with a merge commit.
run git -C "$REPO" pull --ff-only --quiet || {
    echo "REFUSED: $DEFAULT could not fast-forward, so it has diverged from origin." >&2
    echo "Inspect it with: git -C $REPO log --oneline --graph $DEFAULT origin/$DEFAULT" >&2
    exit 3
}

if [[ "$TARGET" == "$DEFAULT" ]]; then
    echo ""
    echo "Was already on $DEFAULT, now up to date. No branch to remove."
    # Left-behind branches are easy to miss once the checkout is back on the
    # default branch, so name them rather than let them accumulate silently.
    others="$(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads |
        grep -vx "$DEFAULT" || true)"
    if [[ -n "$others" ]]; then
        echo ""
        echo "Other local branches still here:"
        printf '  %s\n' $others
        echo "Tidy one with: pr-sync.sh $REL --branch <name>"
    fi
    exit 0
fi

if ((KEEP_BRANCH)); then
    echo ""
    echo "On $DEFAULT and up to date. Left $TARGET in place as asked."
    exit 0
fi

# Does the branch hold any change that the default branch cannot account for?
# `git cherry` compares patch ids rather than commit ids, so a commit that was
# squashed or cherry-picked onto the default branch is recognised as present
# even though its sha is nowhere in the history. Returns 0 when something is
# genuinely missing, which is the case that must never be deleted.
branch_has_unaccounted_commits() {
    local out
    out="$(git -C "$REPO" cherry HEAD "$BRANCH_SHA" 2>/dev/null)" || return 0
    [[ -z "$out" ]] && return 1
    grep -q '^+' <<< "$out" && return 0
    return 1
}

# Three independent signals that the branch landed. Any one is enough, and the
# report names which, because they are not equally strong.
EVIDENCE=""
if ((DRY_RUN)); then
    # The signals are all read after the fetch and the pull, neither of which a
    # dry run performs, so there is nothing honest to report here.
    echo ""
    echo "Dry run: stopping before the branch decision."
    echo "Whether $BRANCH would be deleted depends on the fetch and pull above, which a dry run skips."
    exit 0
elif ((VERIFIED)); then
    EVIDENCE="asserted with --verified"
elif [[ -n "$BRANCH_SHA" ]] &&
    git -C "$REPO" merge-base --is-ancestor "$BRANCH_SHA" HEAD 2>/dev/null; then
    EVIDENCE="its commits are ancestors of $DEFAULT"
elif [[ -n "$BRANCH_SHA" ]] &&
    git -C "$REPO" diff --quiet "$BRANCH_SHA" HEAD 2>/dev/null; then
    EVIDENCE="$DEFAULT now has an identical tree, as a squash merge leaves"
elif [[ -n "$BRANCH_SHA" ]] && ! branch_has_unaccounted_commits; then
    EVIDENCE="every change it carries is already in $DEFAULT, by patch id"
fi

# A vanished remote branch is deliberately not a delete signal on its own. It
# usually means the pull request completed, but an abandoned pull request whose
# branch was deleted looks identical, and in that case the local commits are the
# only copy left.
if [[ -z "$EVIDENCE" ]]; then
    echo ""
    echo "On $DEFAULT and up to date, but kept $TARGET: no evidence it was merged."
    echo "It carries changes that $DEFAULT cannot account for, by commit or by patch id."
    if [[ -z "$BRANCH_UPSTREAM" ]]; then
        echo "It has no upstream either, so it was never pushed and can have no pull request."
    elif ! git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$TARGET"; then
        echo "WARNING: $BRANCH_UPSTREAM is gone while these changes are not in $DEFAULT."
        echo "That is what an abandoned pull request with a deleted branch looks like, so this"
        echo "local branch may be the only copy. Check the pull request before removing it."
        echo "It can also mean the merged version was edited afterwards, in which case the"
        echo "difference is those later edits and nothing of yours is missing. Compare with:"
        echo "  git -C $REPO diff $DEFAULT $TARGET"
    else
        echo "$BRANCH_UPSTREAM still exists, so the pull request has not completed."
    fi
    echo "Inspect $TARGET with: git -C $REPO switch $TARGET"
    echo "Once the merge is confirmed, re-run with: pr-sync.sh $REL --branch $TARGET --verified"
    exit 3
fi

echo "removing the local branch $TARGET ($EVIDENCE):"
# -D not -d: a squash merge leaves the original commits unreachable from the
# default branch, so -d refuses a branch that is genuinely merged. The evidence
# above is what makes -D safe here. The remote branch is never touched.
run git -C "$REPO" branch -D "$TARGET" || {
    echo "WARN: could not delete $TARGET, leaving it in place." >&2
    exit 0
}

echo ""
echo "$REL is on $DEFAULT, up to date, and $TARGET is gone locally."
echo "The remote branch was not touched. Delete it on the remote if it is still there."

#!/bin/bash
# =============================================================================
# Scaffold a new Frappe app with `bench new-app` into a repository that already
# exists, on a feature branch, ready for a pull request.
#
# `bench new-app` alone starts a fresh repository whose first commit shares no
# history with the remote, so it can be force-pushed but never reviewed. Here
# the scaffold is generated without git and laid on a branch cut from the
# remote's default branch: the app arrives as one commit on top of what the
# repository already holds, its README, licence and pipeline, and goes through
# a pull request like any other change.
#
# The remote URL is an argument and is never written to a tracked file. An
# internal host belongs in apps.local.json once the app exists.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: new-app.sh [-y] [--branch NAME] [--base BRANCH] [--push] APP REMOTE_URL

Run `bench new-app APP` and commit the scaffold on a new branch of
REMOTE_URL, cut from its default branch, so it can be merged through a pull
request. The app is installed in the bench, at apps/APP, like any other.

  --branch NAME   the branch to create, default feat/init-APP
  --base BRANCH   the branch to cut it from, default the remote's HEAD
  --push          push the branch to origin. Without it, the push command
                  is printed and nothing leaves the container
  -y              keep the repository's version of any file the scaffold
                  also generates, without asking. Also --yes

  new-app.sh my_app https://github.com/your-org/my_app.git
  new-app.sh --push my_app https://tfs.example.org/Coll/Project/_git/my_app

APP is a Python package name: lower case, digits and underscores. Naming it
after the repository keeps get-apps.sh able to recognise it in the bench.

bench asks for the title, description, publisher, email and licence. The
repository must have at least one commit on its default branch, since a pull
request needs a base, and must not hold an app already: fetch that one with
get-apps.sh.

Exit status: 0 on success, 1 on a bad argument or a refusal, 2 when bench or
git fails.
EOF
}

ASSUME_YES=false
PUSH=false
BRANCH=""
BASE=""
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
        usage
        exit 0
        ;;
    -y | --yes) ASSUME_YES=true ;;
    --push) PUSH=true ;;
    --branch | --base)
        [[ -n ${2:-} ]] || {
            usage >&2
            exit 1
        }
        if [[ $1 == --branch ]]; then BRANCH="$2"; else BASE="$2"; fi
        shift
        ;;
    -*)
        usage >&2
        exit 1
        ;;
    *) args+=("$1") ;;
    esac
    shift
done

[[ ${#args[@]} -eq 2 ]] || {
    usage >&2
    exit 1
}
APP="${args[0]}"
URL="${args[1]}"
BRANCH="${BRANCH:-feat/init-$APP}"

[[ $APP =~ ^[a-z][a-z0-9_]*$ ]] ||
    error_exit "$APP is not a valid app name: lower case, digits and underscores, starting with a letter."

require_bench
APP_DIR="$BENCH_DIR/apps/$APP"
[[ ! -e $APP_DIR ]] || error_exit "$APP_DIR already exists."

# Every check that can refuse runs before bench asks its questions, so a
# refusal never leaves a half-made app in the bench.
if [[ -z $BASE ]]; then
    BASE="$(git ls-remote --symref "$URL" HEAD |
        awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }')" ||
        error_exit "Cannot reach $URL. Check the URL and your ~/.gitconfig or ssh agent."
    [[ -n $BASE ]] ||
        error_exit "$URL is empty. Push a first commit, a README, to its default branch: a pull request needs a base."
fi
if git ls-remote --exit-code --heads "$URL" "$BRANCH" >/dev/null 2>&1; then
    error_exit "$BRANCH already exists on $URL. Pick another with --branch."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log_info "Cloning $URL at $BASE..."
git clone --quiet --branch "$BASE" "$URL" "$tmp/repo" ||
    error_exit "Cannot clone $BASE from $URL."
if [[ -f $tmp/repo/pyproject.toml || -f $tmp/repo/setup.py ]]; then
    error_exit "$URL already holds a Python package on $BASE. Fetch it with get-apps.sh instead."
fi

log_info "Scaffolding $APP. bench asks a few questions."
cd "$BENCH_DIR"
bench new-app --no-git "$APP" || {
    log_error "bench new-app failed."
    exit 2
}
[[ -d $APP_DIR ]] || {
    log_error "bench new-app created nothing at $APP_DIR."
    exit 2
}

# The clone's history under the scaffold: every scaffold file now reads as a
# change against BASE, and every BASE file the scaffold lacks as a deletion.
mv "$tmp/repo/.git" "$APP_DIR/.git"
cd "$APP_DIR"
git checkout --quiet -b "$BRANCH"

# What the repository has and the scaffold does not, CI or CONTRIBUTING, stays.
git ls-files --deleted -z | xargs -0 -r git checkout --

# What both have, a README, a LICENSE, a .gitignore, is for a person to decide.
mapfile -t overlap < <(git diff --name-only)
if [[ ${#overlap[@]} -gt 0 ]]; then
    log_warn "The scaffold also generates files the repository already has:"
    printf '  %s\n' "${overlap[@]}"
    if confirm "Keep the repository's version of these, and drop the scaffold's?"; then
        git checkout -- "${overlap[@]}"
    else
        log_info "Keeping the scaffold's version. Review the diff in the pull request."
    fi
fi

# --no-git skips the .gitignore too, and bench has already compiled the app,
# so without one every __pycache__ would be committed. Frappe's own template.
if [[ ! -f .gitignore ]]; then
    "$BENCH_DIR/env/bin/python" -c "from frappe.utils.boilerplate import gitignore_template as t; print(t.format(app_name='$APP'), end='')" >.gitignore ||
        error_exit "Cannot write .gitignore from Frappe's template."
fi

# The agent guidance of templates/app-AGENTS.md, unless the repository has its own.
write_agents_md app AGENTS.md "$APP"

git add -A

# The scaffold's own hooks, which its CI runs: bench's hooks.py ends with a
# blank line ruff-format removes, so the first run rewrites and fails, and the
# second, on the rewritten files, must pass.
if [[ -f .pre-commit-config.yaml ]] && command -v pre-commit >/dev/null; then
    log_info "Running the scaffold's pre-commit hooks."
    pre-commit run --all-files >/dev/null 2>&1 || pre-commit run --all-files ||
        log_warn "A pre-commit hook still fails. Fix it before the push, or CI will."
    git add -A
fi

git commit --quiet -m "feat: initialize $APP with bench new-app" || {
    log_error "The commit failed. The scaffold is staged in $APP_DIR."
    log_error "  A signing error? Check it with: git -C $APP_DIR commit"
    exit 2
}
git --no-pager show --stat --format='%h %s' HEAD

if [[ $PUSH == true ]]; then
    git push -u origin "$BRANCH" || {
        log_error "The push failed. The commit is in $APP_DIR on $BRANCH."
        exit 2
    }
    log_info "Pushed. Open a pull request from $BRANCH into $BASE."
else
    log_info "Nothing pushed. When the diff is right:"
    log_info "  git -C $APP_DIR push -u origin $BRANCH"
fi

cat <<EOF

Next:
  1. Open a pull request from $BRANCH into $BASE.
  2. Declare the app so the next bench gets it, with "branch": "$BASE" and
     "history": true: in apps.json when the host is public, in
     apps.local.json when it is internal.
  3. Install it on a site: bench --site SITE install-app $APP
EOF

#!/bin/bash
# =============================================================================
# Move one app in the bench, frappe included, to another tag or branch.
#
# A direct git checkout rather than `bench switch-to-branch`, which fails on a
# tag. Then the Python dependencies, the Node ones when the app has any, a
# migration of every site, and the assets of that app.
#
# For frappe the new version is also recorded in .devcontainer/.env, so a later
# install-bench.sh builds the same one.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: switch-version.sh [-y] APP VERSION

Check out VERSION in apps/APP, update its dependencies, migrate every site
and rebuild its assets. VERSION is a tag or a branch.

  -y   stash uncommitted changes in apps/APP without asking. Also --yes,
       --force

  switch-version.sh frappe v16.35.0    # the release the production image uses
  switch-version.sh raven v2.8.8
  switch-version.sh helpdesk develop

With APP frappe, FRAPPE_VERSION in .devcontainer/.env is updated too.
README.md, "Frappe versions", covers a move across a major line.

Exit status: 0 on success, 1 on a bad argument or a refusal, 2 on failure.
EOF
}

ASSUME_YES=false
args=()
for arg in "$@"; do
    case "$arg" in
    -h | --help)
        usage
        exit 0
        ;;
    -y | --yes | --force) ASSUME_YES=true ;;
    *) args+=("$arg") ;;
    esac
done
set -- "${args[@]}"

APP="${1:-}"
NEW_VERSION="${2:-}"
[[ -n $APP && -n $NEW_VERSION ]] || {
    usage >&2
    exit 1
}

require_bench
APP_DIR="$BENCH_DIR/apps/$APP"
[[ -d $APP_DIR ]] || error_exit "No app at $APP_DIR"

current_ref() { git describe --tags --exact-match 2>/dev/null || git rev-parse --abbrev-ref HEAD; }

cd "$APP_DIR"
CURRENT_VERSION="$(current_ref)"
log_info "$APP is on $CURRENT_VERSION"
if [[ $CURRENT_VERSION == "$NEW_VERSION" ]]; then
    log_info "Already there. Nothing to do."
    exit 0
fi

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    log_error "apps/$APP has uncommitted changes:"
    git status --short
    if confirm "Stash them and continue?"; then
        git stash push -m "before switching to $NEW_VERSION"
    else
        error_exit "Commit or stash them first."
    fi
fi

git fetch --all --tags || error_exit "Fetch failed"
git checkout "$NEW_VERSION" || error_exit "No such tag or branch: $NEW_VERSION"
if git show-ref --verify --quiet "refs/heads/$NEW_VERSION"; then
    git pull origin "$NEW_VERSION" || log_warn "Could not pull, continuing."
fi
NEW_CURRENT="$(current_ref)"
log_info "Now on $NEW_CURRENT"

cd "$BENCH_DIR"
log_info "Updating the Python dependencies..."
./env/bin/pip install -q -U -e "apps/$APP" || log_warn "Dependency update failed, continuing."
if [[ -f "$APP_DIR/package.json" ]]; then
    log_info "Updating the Node dependencies..."
    (cd "$APP_DIR" && yarn install --silent) || log_warn "yarn install failed, continuing."
fi

# One migration per site, reported individually: a failure on one site is not
# a reason to skip the others, and it is the thing to fix by hand.
mapfile -t SITES < <(list_sites)
if [[ ${#SITES[@]} -eq 0 ]]; then
    log_warn "No sites to migrate. Create one with create-site.sh."
else
    for site in "${SITES[@]}"; do
        log_info "Migrating $site..."
        bench --site "$site" migrate || log_error "  $site failed to migrate, fix it by hand."
    done
    bench --site all clear-cache 2>/dev/null || log_warn "Could not clear the cache."
fi

if [[ $APP == frappe && -f $ENV_FILE ]]; then
    if grep -q '^FRAPPE_VERSION=' "$ENV_FILE"; then
        sed -i "s|^FRAPPE_VERSION=.*|FRAPPE_VERSION=$NEW_VERSION|" "$ENV_FILE"
    else
        echo "FRAPPE_VERSION=$NEW_VERSION" >>"$ENV_FILE"
    fi
    log_info "FRAPPE_VERSION in .devcontainer/.env is now $NEW_VERSION"
    log_warn "If frappe/build:$NEW_VERSION has another Python or Node, set FRAPPE_PYTHON and FRAPPE_NODE there too and rebuild the container."
fi

log_info "Building the assets of $APP..."
bench build --app "$APP" || log_warn "Build failed. Run ./build.sh when ready."

log_info "$APP: $CURRENT_VERSION -> $NEW_CURRENT, ${#SITES[@]} site(s) migrated."
log_info "To go back: ./switch-version.sh $APP $CURRENT_VERSION"

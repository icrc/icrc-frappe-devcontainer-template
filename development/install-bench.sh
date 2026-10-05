#!/bin/bash
# =============================================================================
# Create the bench, point it at the services, and install the declared apps.
#
# Run once after the container is first created. Everything project-specific
# lives in apps.json, not here.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: install-bench.sh [-y] [VERSION]

Initialise frappe-bench, configure it for the MariaDB and Redis services in
docker-compose.yml, and install the apps from apps.json. The configuration
comes first, so an app that fails to clone leaves a working bench behind.

  VERSION   the Frappe branch or tag, e.g. v16.35.0 or version-16.
            Defaults to FRAPPE_VERSION from .devcontainer/.env, which is
            where to pin the release your production image is built from
  -y        remove an existing bench without asking. Also --yes, --force
  -h        show this help

Environment:
  BENCH_NAME    the bench directory under development/. Default frappe-bench;
                every script honours it, so a second bench can sit next to
                the first
  BENCH_PYTHON  the Python the bench is created on. Default python3, the
                current one frappe/bench carries

An existing bench is not touched: the script asks before removing it. To add
an app to a bench that already exists, edit apps.json and run get-apps.sh.

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

# .env is the one place the default is written, so no literal here.
[[ -n ${1:-} ]] && FRAPPE_VERSION="$1"
require_secret FRAPPE_VERSION

log_info "Installing a Frappe bench (version $FRAPPE_VERSION)"

if [[ -d $BENCH_DIR ]]; then
    log_error "A bench already exists at $BENCH_DIR."
    log_warn "Removing it deletes every site and database in it."
    if confirm "Remove and reinstall?"; then
        rm -rf "$BENCH_DIR" || error_exit "Failed to remove $BENCH_DIR"
    else
        log_info "Nothing done. To add apps to the existing bench, run get-apps.sh."
        exit 1
    fi
fi

cd "$DEV_DIR"

log_info "Initialising the bench..."
bench init --skip-redis-config-generation --frappe-branch="$FRAPPE_VERSION" \
    --python "${BENCH_PYTHON:-python3}" "$BENCH_NAME" ||
    error_exit "bench init failed"

"$SCRIPT_DIR/configure-bench.sh" || error_exit "Failed to configure the bench"

log_info "Installing the apps from apps.json..."
"$SCRIPT_DIR/get-apps.sh" || error_exit "Some apps could not be installed. The bench is configured: fix apps.json and re-run get-apps.sh."

log_info "========================================="
log_info "Bench installed at $BENCH_DIR"
log_info "Frappe: $FRAPPE_VERSION"
log_info "Apps:   $(ls "$BENCH_DIR/apps" | tr '\n' ' ')"
log_info "========================================="
log_info "Next: ./create-site.sh dev.localhost, then ./start.sh"

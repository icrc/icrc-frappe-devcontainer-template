#!/bin/bash
# =============================================================================
# Create a development site and install apps into it.
#
# One script for every site: the four it replaces differed only in the site
# name, the database name and the app list, all of which are arguments here.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: create-site.sh [-y] [SITE] [DB_NAME] [APP ...]

Create a Frappe site on the MariaDB service and install apps into it.

  SITE      site name, must end in .localhost. Default dev.localhost
  DB_NAME   database name. Default derived from the site name
  APP ...   apps to install. Default every app in the bench except frappe,
            which is installed by definition
  -y        drop and recreate SITE if it exists, without asking. Also
            --yes, --force
  -h        show this help

The Administrator password is ADMIN_PASSWORD from .devcontainer/.env and is
printed once at the end. Recover it later with:
  bash .devcontainer/init-env.sh --print

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

SITE_NAME="${1:-dev.localhost}"
DB_NAME="${2:-}"
shift 2 2>/dev/null || shift $# # the rest, if any, are app names
APPS=("$@")

require_bench
require_secret DB_ROOT_PASSWORD
require_secret ADMIN_PASSWORD
cd "$BENCH_DIR"

# Frappe's own default, and what delete-site.sh reconstructs.
[[ -n $DB_NAME ]] || DB_NAME="_$(echo "$SITE_NAME" | tr '.-' '_')"

# Everything in the bench, in a defined order, rather than whatever the
# filesystem happens to return.
if [[ ${#APPS[@]} -eq 0 ]]; then
    while IFS= read -r app; do
        [[ $app == frappe ]] && continue
        APPS+=("$app")
    done < <(ls apps | sort)
fi

if [[ -d "sites/$SITE_NAME" ]]; then
    log_error "Site $SITE_NAME already exists."
    if confirm "Drop and recreate it? Every row in it is lost."; then
        bench drop-site "$SITE_NAME" --force \
            --db-root-username="$DB_ROOT_USER" \
            --db-root-password="$DB_ROOT_PASSWORD" || error_exit "Failed to drop $SITE_NAME"
    else
        exit 1
    fi
fi

log_info "Creating $SITE_NAME (database $DB_NAME) with: ${APPS[*]:-none}"

install_args=()
for app in "${APPS[@]}"; do install_args+=("--install-app=$app"); done

bench new-site "$SITE_NAME" \
    --db-type=mariadb \
    --db-name="$DB_NAME" \
    --db-host="$DB_HOST" \
    --db-root-username="$DB_ROOT_USER" \
    --db-root-password="$DB_ROOT_PASSWORD" \
    --admin-password="$ADMIN_PASSWORD" \
    --mariadb-user-host-login-scope=% \
    "${install_args[@]}" || error_exit "bench new-site failed"

bench --site "$SITE_NAME" set-config developer_mode 1
bench --site "$SITE_NAME" clear-cache

log_info "========================================="
log_info "Site:     $SITE_NAME"
log_info "Database: $DB_NAME on $DB_HOST"
log_info "Login:    Administrator / $ADMIN_PASSWORD"
log_info "========================================="
log_info "Next: ./start.sh, then http://localhost:8000"

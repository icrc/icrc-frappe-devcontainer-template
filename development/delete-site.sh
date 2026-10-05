#!/bin/bash
# Delete a site and its database, with a manual cleanup when bench cannot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: delete-site.sh [-y] [SITE]

Drop a site, its database and its files. Default dev.localhost. Asks for
confirmation, and falls back to dropping the database directly when
`bench drop-site` fails.

  -y   delete without asking. Also --yes, --force

Exit status: 0 on success or when cancelled, 1 when the site does not exist.
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

require_bench
require_secret DB_ROOT_PASSWORD
cd "$BENCH_DIR"

[[ -d "sites/$SITE_NAME" ]] || error_exit "Site $SITE_NAME does not exist."

log_warn "========================================="
log_warn "This permanently deletes:"
log_warn "  sites/$SITE_NAME, its database, and every file in it"
log_warn "========================================="
if ! confirm "Delete $SITE_NAME?"; then
    log_info "Cancelled."
    exit 0
fi

DB_NAME=""
if [[ -f "sites/$SITE_NAME/site_config.json" ]]; then
    DB_NAME="$(grep -o '"db_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        "sites/$SITE_NAME/site_config.json" | cut -d'"' -f4 || echo "")"
fi
# Frappe's default shape, the same one create-site.sh derives.
[[ -n $DB_NAME ]] || DB_NAME="_$(echo "$SITE_NAME" | tr '.-' '_')"

log_info "Site: $SITE_NAME, database: $DB_NAME"

if bench drop-site --force --no-backup \
    --db-root-username="$DB_ROOT_USER" \
    --db-root-password="$DB_ROOT_PASSWORD" "$SITE_NAME" 2>/dev/null; then
    log_info "Dropped with bench."
else
    log_warn "bench drop-site failed, cleaning up by hand..."
    if mysql -h "$DB_HOST" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASSWORD" \
        -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null; then
        log_info "Database dropped."
    else
        log_error "Could not drop $DB_NAME. Drop it by hand:"
        log_error "  mysql -h $DB_HOST -u $DB_ROOT_USER -p -e 'DROP DATABASE \`$DB_NAME\`;'"
    fi
    rm -rf "sites/$SITE_NAME" || error_exit "Failed to remove sites/$SITE_NAME"
fi

if [[ -d "sites/$SITE_NAME" ]]; then
    error_exit "sites/$SITE_NAME still exists."
fi
log_info "$SITE_NAME deleted."

#!/bin/bash
# Open a database shell on the site's own database.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SITE_NAME="${1:-dev.localhost}"

require_bench
cd "$BENCH_DIR"

log_info "Database console for $SITE_NAME"
bench --site "$SITE_NAME" mariadb

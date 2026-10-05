#!/bin/bash
# Apply schema changes to a site. Run it after editing any DocType JSON:
# without it the new column does not exist and the field never appears.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SITE_NAME="${1:-all}"

require_bench
cd "$BENCH_DIR"

log_info "Migrating $SITE_NAME..."
bench --site="$SITE_NAME" migrate || error_exit "Migration failed"
log_info "$SITE_NAME migrated."

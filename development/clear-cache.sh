#!/bin/bash
# Clear the cache of every site, the compiled asset manifest included. Run
# this when the browser shows an old build after a rebuild.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_bench
cd "$BENCH_DIR"

log_info "Clearing the cache..."
bench --site=all clear-cache
bench --site=all execute 'frappe.cache.delete_key(keys="assets_json", shared=True)'
log_info "Cache cleared."

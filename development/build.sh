#!/bin/bash
# Build the frontend assets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_bench
cd "$BENCH_DIR"

log_info "Building assets..."
bench build
log_info "Done."

#!/bin/bash
# Rebuild assets on change. Leave it running in its own terminal.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_bench
cd "$BENCH_DIR"

log_info "Watching for changes. Ctrl-C to stop."
bench watch

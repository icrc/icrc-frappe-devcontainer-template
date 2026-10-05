#!/bin/bash
# Start the development server: web, socket.io, workers and the scheduler.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_bench
cd "$BENCH_DIR"

log_info "Starting the bench. http://localhost:8000, Ctrl-C to stop."
bench start

#!/bin/bash
# =============================================================================
# Stop every bench process and free the ports.
#
# `bench start` leaves web, realtime, workers, scheduler and the asset watcher
# behind when its terminal dies. Each is asked to stop, then killed if it did
# not, then whatever still holds a Frappe port goes the same way.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: stop-bench.sh

Stop bench serve, watch, schedule and worker, the realtime server and the
asset watchers, then free ports 8000-8005 and 9000-9005.

Exit status: 0 when nothing is left running, 2 when something survived.
EOF
}

case "${1:-}" in
-h | --help)
    usage
    exit 0
    ;;
esac

PATTERN='bench serve|bench watch|bench schedule|bench worker|bench_helper frappe|socketio.js|esbuild.*watch|yarn run watch'
PORTS='8000|8001|8002|8003|8004|8005|9000|9001|9002|9003|9004|9005'

bench_pids() { pgrep --full "$PATTERN" || true; }

# The owners of whatever listens on a Frappe port.
port_pids() {
    ss -tlnp 2>/dev/null | awk -v ports="$PORTS" '$4 ~ ":("ports")$"' |
        grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u
}

# TERM, a moment, then KILL for whatever ignored it.
stop_pids() {
    local pids
    pids="$(printf '%s\n' "$@" | sort -u | tr '\n' ' ')"
    [[ -n ${pids// /} ]] || return 0
    # shellcheck disable=SC2086
    kill -TERM $pids 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null || true
}

log_info "Stopping the bench processes..."
stop_pids $(bench_pids) $(port_pids)

left="$(bench_pids)"
busy="$(port_pids)"
if [[ -z $left && -z $busy ]]; then
    log_info "Bench stopped, ports 8000-8005 and 9000-9005 free."
    exit 0
fi
log_warn "Still running:"
# shellcheck disable=SC2086
[[ -n $left ]] && ps -o pid=,args= -p $(tr '\n' ',' <<<"$left" | sed 's/,$//')
[[ -n $busy ]] && ss -tlnp | grep -E ":($PORTS)\b"
exit 2

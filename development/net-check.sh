#!/bin/bash
# Network health check: the Compose services, the proxy, a few hosts the
# egress firewall opens, and that it still blocks everything else.
#
# Exits non-zero when any check fails. Each probe gives up after TIMEOUT
# seconds, default 5, so a dropped connection shows as a failure, not a hang.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

TIMEOUT="${TIMEOUT:-5}"
failures=0

case "${1:-}" in
    -h | --help)
        sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

ok() { echo -e "  ${GREEN}ok${NC}    $1"; }
fail() {
    echo -e "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

# TCP connect to host:port, nothing sent.
tcp_check() {
    local host="$1" port="$2"
    if timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
        ok "$host:$port"
    else
        fail "$host:$port unreachable"
    fi
}

# HTTPS GET through whatever the environment says, as pip or npm would. Any
# HTTP status counts: an answer means the path is open.
http_check() {
    local url="$1" out
    out="$(curl -s -o /dev/null --max-time "$TIMEOUT" -w '%{http_code} %{time_total}s' "$url")"
    if [[ "${out%% *}" != "000" ]]; then
        ok "$url ($out)"
    else
        fail "$url no answer"
    fi
}

echo "Proxy"
proxy="${HTTPS_PROXY:-${https_proxy:-}}"
if [[ -n "$proxy" ]]; then
    # Host and port only, so a password in the URL stays out of the output.
    rest="${proxy#*://}"
    rest="${rest##*@}"
    rest="${rest%%/*}"
    [[ "$rest" == *:* ]] || rest="$rest:80"
    echo "  HTTPS_PROXY  $rest"
    echo "  NO_PROXY     ${NO_PROXY:-${no_proxy:-}}"
    [[ ",${NO_PROXY:-${no_proxy:-}}," == *,\*,* ]] && fail "NO_PROXY contains *, every request bypasses the proxy"
    tcp_check "${rest%:*}" "${rest##*:}"
else
    echo "  none, every tool connects directly"
fi

echo "Compose services"
tcp_check mariadb 3306
tcp_check redis-cache 6379
tcp_check redis-queue 6379
tcp_check mailpit 1025
tcp_check seaweedfs 8333
tcp_check keycloak 8080
tcp_check litellm 4000

echo "Allowed hosts"
http_check https://pypi.org/simple/
http_check https://registry.npmjs.org/
http_check https://github.com/
http_check https://api.anthropic.com/

echo "Firewall"
if curl --noproxy '*' -s -o /dev/null --max-time "$TIMEOUT" https://1.1.1.1 2>/dev/null; then
    fail "direct egress to 1.1.1.1 is open, the firewall is not applied"
else
    ok "direct egress to 1.1.1.1 blocked"
fi

echo
if ((failures)); then
    log_error "$failures check(s) failed"
    exit 1
fi
log_info "All checks passed."

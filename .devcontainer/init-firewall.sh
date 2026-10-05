#!/usr/bin/env bash
# =============================================================================
# Egress firewall: default-deny outbound with a root-owned allowlist, on a
# network with a proxy and on one without (postStartCommand).
#
# Unlike a firewall whose allowlist opens only a corporate proxy and relies on
# it for everything else, the hosts the bench and its tools reach are listed
# themselves, so the container works with no proxy, and the proxy, when there
# is one, is opened on top.
#
# The proxy and EGRESS_ALLOW are read from the environment of PID 1, which
# Compose sets from the host, never from the caller's: the frappe user runs
# this script through sudo, and must not open a host of its choosing by setting
# a variable first.
# =============================================================================
set -euo pipefail

ALLOWLIST="/etc/icrc-egress-allowlist"

usage() {
    cat <<'EOF'
Usage: sudo /usr/local/bin/init-firewall.sh

Drop every outbound connection except, on top of loopback, replies and DNS:

  the container's own networks   so the Compose services stay reachable
  /etc/icrc-egress-allowlist     baked into the image from egress-allowlist
  GitHub's web, api and git      ranges from api.github.com/meta, on 443,
                                 and the git ones on 22 as well
  the proxy                      from HTTP_PROXY / HTTPS_PROXY, when set
  EGRESS_ALLOW                   host[:port] entries, comma- or space-separated,
                                 for internal hosts no tracked file may name

An entry is host[:port] or CIDR[:port], the port 443 unless given. Names are
resolved once, now: a host whose address moves needs the script run again.
Idempotent, so it runs on every start and can be re-run at any time.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    "") ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
    echo "init-firewall: must run as root: sudo /usr/local/bin/init-firewall.sh" >&2
    exit 1
fi

# The environment the container was started with. PID 1 runs as frappe, and
# the kernel lets root read another user's environ only with CAP_SYS_PTRACE,
# which the container does not have and should not get: the file is read as
# PID 1's own uid instead.
pid1_uid="$(stat -c %u /proc/1)"
pid1_gid="$(stat -c %g /proc/1)"
if ! pid1_environ="$(setpriv --reuid="$pid1_uid" --regid="$pid1_gid" --clear-groups \
    cat /proc/1/environ | tr '\0' '\n')"; then
    echo "init-firewall: WARN cannot read PID 1's environment, no proxy or EGRESS_ALLOW opened" >&2
    pid1_environ=""
fi

# A variable as the container was started with it.
pid1_env() {
    sed -n "s/^$1=//p" <<<"$pid1_environ" | head -n 1
}

# host:port of a proxy URL such as http://user:secret@proxy.example.org:8080/
proxy_entry() {
    local url="$1" rest port
    rest="${url#*://}"
    rest="${rest##*@}"
    rest="${rest%%/*}"
    if [[ "$rest" == *:* ]]; then
        port="${rest##*:}"
        rest="${rest%:*}"
    elif [[ "$url" == https://* ]]; then
        port=443
    else
        port=80
    fi
    printf '%s:%s\n' "$rest" "$port"
}

# Allow one host[:port] or CIDR[:port] entry.
allow_entry() {
    local entry="$1" host port ips ip
    host="${entry%%:*}"
    port="443"
    [[ "$entry" == *:* ]] && port="${entry##*:}"
    if [[ "$host" =~ ^[0-9.]+(/[0-9]+)?$ ]]; then
        ips="$host"
    else
        # getent, not dig: it reads /etc/hosts too, where host.docker.internal
        # and host.containers.internal live.
        ips="$(getent ahostsv4 "$host" | awk '{print $1}' | sort -u || true)"
        if [[ -z "$ips" ]]; then
            echo "init-firewall: WARN cannot resolve '$host', entry skipped" >&2
            return 0
        fi
    fi
    for ip in $ips; do
        iptables -A OUTPUT -p tcp -d "$ip" --dport "$port" -j ACCEPT
    done
}

proxy_url="$(pid1_env HTTPS_PROXY)"
[[ -n "$proxy_url" ]] || proxy_url="$(pid1_env https_proxy)"
http_proxy_url="$(pid1_env HTTP_PROXY)"
[[ -n "$http_proxy_url" ]] || http_proxy_url="$(pid1_env http_proxy)"
extra="$(pid1_env EGRESS_ALLOW)"

# Open up before flushing: on a re-run the policy is already DROP, and flushing
# the ACCEPT rules first would cut off DNS and GitHub for the lookups below.
iptables -P OUTPUT ACCEPT
iptables -F OUTPUT
if ip6tables -L OUTPUT >/dev/null 2>&1; then
    ip6tables -P OUTPUT ACCEPT
    ip6tables -F OUTPUT
fi

# Before any rule, while egress is still open.
github_meta="$(curl -fsS --max-time 15 --proxy "${proxy_url:-${http_proxy_url}}" \
    https://api.github.com/meta 2>/dev/null || true)"

# Baseline: loopback, replies to existing flows, DNS.
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# The container's own networks, every port: MariaDB, Redis, Keycloak and the
# other services are on the Compose network, and a host proxy is at its
# gateway.
for net in $(ip -4 -o addr show scope global | awk '{print $4}'); do
    iptables -A OUTPUT -d "$net" -j ACCEPT
done

while IFS= read -r entry || [[ -n "$entry" ]]; do
    entry="${entry%%#*}"
    entry="${entry//[[:space:]]/}"
    [[ -z "$entry" ]] && continue
    allow_entry "$entry"
done <"$ALLOWLIST"

# GitHub rotates the addresses behind its names, so its published ranges are
# opened rather than what github.com resolves to now. IPv4 only, as the rest.
if [[ -n "$github_meta" ]]; then
    for cidr in $(jq -r '(.web + .api + .git)[] | select(contains(":") | not)' <<<"$github_meta" | sort -u); do
        iptables -A OUTPUT -p tcp -d "$cidr" --dport 443 -j ACCEPT
    done
    for cidr in $(jq -r '.git[] | select(contains(":") | not)' <<<"$github_meta"); do
        iptables -A OUTPUT -p tcp -d "$cidr" --dport 22 -j ACCEPT
    done
else
    echo "init-firewall: WARN cannot fetch api.github.com/meta, GitHub stays closed" >&2
fi

for url in "$proxy_url" "$http_proxy_url"; do
    if [[ -n "$url" ]]; then
        allow_entry "$(proxy_entry "$url")"
    fi
done

for entry in ${extra//,/ }; do
    allow_entry "$entry"
done

# Default-deny everything else outbound.
iptables -P OUTPUT DROP
if ip6tables -L OUTPUT >/dev/null 2>&1; then
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -P OUTPUT DROP
fi

# Verify: a direct external fetch to an address nobody listed must now fail.
if curl --noproxy '*' --max-time 5 -s -o /dev/null https://1.1.1.1 2>/dev/null; then
    echo "init-firewall: FAIL direct external egress is still possible" >&2
    exit 1
fi

echo "init-firewall: default-deny egress active ($(iptables -S OUTPUT | grep -c -- '-j ACCEPT') allow rules," \
    "proxy: $([[ -n "$proxy_url" ]] && proxy_entry "$proxy_url" || echo none))"

#!/usr/bin/env bash
# =============================================================================
# Everything the container runs on every start (postStartCommand).
#
# The firewall first, since iptables state does not survive a restart, and a
# firewall that fails stops here, so it cannot go unnoticed. Then the plugin
# volume, which starts empty on a rebuild, and the skills skills.json pins:
# both idempotent and non-fatal.
#
# Those two clone with no credential helper but gh's. The editor adds its own
# helper at system scope, which forwards the request to the host, and a
# lifecycle command runs before the editor is attached: asked then, that helper
# can fail, hang, or take the start down with it. A host ~/.gitconfig with
# http.<url>.proactiveAuth asks it on the first request, before any 401. So a
# repository that needs any other credential fails here with a warning instead,
# and is installed by running the script again from a terminal, where the
# editor's helper works.
# =============================================================================
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: post-start.sh

Apply the egress firewall, then install the declared Claude plugins and the
skills skills.json pins, with gh as the only git credential helper. Run by
postStartCommand on every start.

  -h        show this help
EOF
    return
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    "") ;;
    *)
        usage >&2
        exit 1
        ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo /usr/local/bin/init-firewall.sh

# Command scope, so it comes after every config file: the empty helper clears
# the list built so far, the editor's included, and gh's is added back. No
# terminal prompt either, so a missing credential fails rather than waits.
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=
export GIT_CONFIG_KEY_1=credential.https://github.com.helper
export GIT_CONFIG_VALUE_1='!/usr/local/bin/gh auth git-credential'

bash "$HERE/install-plugins.sh"
bash "$HERE/../development/get-skills.sh"

#!/usr/bin/env bash
# =============================================================================
# GitHub CLI login.
#
# gh cannot authenticate an API call with an ssh key, so it needs a token of its
# own. This runs the OAuth device flow rather than asking for a PAT: you approve
# a code in a browser, and there is no second secret to mint, store or rotate.
# git is left alone, on the ssh key forwarded from the host agent.
#
# The token is written to ~/.config/gh, which is the host's directory bind-
# mounted in, so this is run once and survives every rebuild. See README.md.
# =============================================================================
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: gh-login.sh [--force]

Log the GitHub CLI in with the OAuth device flow (no PAT). git protocol is set
to ssh and no ssh key is uploaded: the host agent already provides one.

  --force   re-run the login even when gh reports an active session
  -h        show this help
EOF
}

force=false
case "${1:-}" in
-h | --help)
    usage
    exit 0
    ;;
--force) force=true ;;
"") ;;
*)
    usage >&2
    exit 1
    ;;
esac

if ! command -v gh &>/dev/null; then
    echo "gh-login.sh: gh is not on PATH." >&2
    echo "  It is installed by .devcontainer/Dockerfile, so rebuild the container." >&2
    exit 1
fi

if [[ $force == false ]] && gh auth status --hostname github.com &>/dev/null; then
    gh auth status --hostname github.com
    echo "gh-login.sh: already logged in. Re-run with --force to replace this session."
    exit 0
fi

# --web is the device flow. --skip-ssh-key because git authenticates with the
# forwarded agent key, which gh has no business generating or uploading.
gh auth login \
    --hostname github.com \
    --git-protocol ssh \
    --web \
    --skip-ssh-key

gh auth status --hostname github.com

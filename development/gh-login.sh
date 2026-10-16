#!/usr/bin/env bash
# =============================================================================
# GitHub CLI login.
#
# gh and git both need this token: gh for the API, git because it reaches GitHub
# over https and the Dockerfile makes gh its credential helper. This runs the
# OAuth device flow rather than asking for a PAT: you approve a code in a
# browser, and there is no secret to mint, store or rotate.
#
# The token is written to ~/.config/gh, which is the host's directory bind-
# mounted in, so this is run once and survives every rebuild. See README.md.
# =============================================================================
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: gh-login.sh [--force]

Log the GitHub CLI in with the OAuth device flow (no PAT). The token also
serves git, which reaches GitHub over https. No ssh key is uploaded.

  --force   re-run the login even when gh reports an active session
  -h        show this help
EOF
    return
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

# --web is the device flow. --git-protocol ssh only because https would offer
# to write a credential helper into ~/.gitconfig; the Dockerfile sets the helper
# at system scope instead, and rewrites the ssh URLs gh hands out to https.
# --skip-ssh-key because no key needs uploading.
gh auth login \
    --hostname github.com \
    --git-protocol ssh \
    --web \
    --skip-ssh-key

gh auth status --hostname github.com

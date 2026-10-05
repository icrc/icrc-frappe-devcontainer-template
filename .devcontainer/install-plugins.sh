#!/usr/bin/env bash
# =============================================================================
# Materialise the Claude plugins this environment declares (postStartCommand).
#
# ~/.claude/plugins holds ABSOLUTE paths (known_marketplaces.json,
# installed_plugins.json), valid only for the HOME that wrote them, so it must
# never be shared: the environment starting last wins and every other one then
# fails with "failed to load: cache-miss". devcontainer.json mounts a volume
# over it to keep this container's copy private, and this script fills that
# volume from the declarations, which are portable.
#
# Idempotent, so it runs on every start. Warns and exits 0 rather than blocking
# container start.
# =============================================================================
set -uo pipefail

usage() {
    cat <<'EOF'
Usage: install-plugins.sh [SETTINGS_FILE...]

Register every declared marketplace, then install every enabled plugin, at user
scope. Idempotent, so it is meant to run from postStartCommand on every start.

Declarations are read from these files and unioned, first declaration winning:

  /etc/claude-code/managed-settings.json   org policy, when present
  $CLAUDE_CONFIG_DIR/settings.json         your own settings (~/.claude)
  .claude/settings.json                    the repository's settings, relative
                                           to the working directory

  extraKnownMarketplaces  ->  claude plugin marketplace add
  enabledPlugins, true    ->  claude plugin install

Pass SETTINGS_FILE to read a different set. A file that is absent or malformed
is skipped with a warning, never fatal.
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

warn() { echo "WARNING (install-plugins): $*" >&2; }

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if (($#)); then
    SETTINGS=("$@")
else
    SETTINGS=(
        /etc/claude-code/managed-settings.json
        "$CONFIG_DIR/settings.json"
        .claude/settings.json
    )
fi

command -v claude >/dev/null || {
    warn "claude not on PATH, cannot install plugins"
    exit 0
}
command -v python3 >/dev/null || {
    warn "python3 not on PATH, cannot read the declarations"
    exit 0
}

# Tab-separated instructions, marketplaces first so a plugin is never installed
# before the marketplace holding it is registered.
mapfile -t DECLARATIONS < <(python3 - "${SETTINGS[@]}" <<'PY'
import json
import pathlib
import sys

marketplaces = {}
plugins = []
notes = []

for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if not path.exists():
        continue                       # a policy-less image, or no project settings
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        notes.append(f"could not read {path}: {error}")
        continue
    for key, entry in (data.get("extraKnownMarketplaces") or {}).items():
        source = (entry or {}).get("source") or {}
        # owner/repo for a github source, a clone URL otherwise. `git` and `url`
        # mean the same here: the CLI writes one, a hand-written policy the other.
        target = source.get("repo") if source.get("source") == "github" else source.get("url")
        # Keyed by target: a marketplace is named by its own manifest, so the
        # settings key is only a local alias and the same repository is often
        # registered under two different ones.
        if target and target not in marketplaces:
            marketplaces[target] = key
    for spec, enabled in (data.get("enabledPlugins") or {}).items():
        if enabled is True and spec not in plugins:
            plugins.append(spec)

for target, key in marketplaces.items():
    print(f"marketplace\t{key}\t{target}")

# Attempted without checking the marketplace first, for that same reason: the
# CLI knows the real names, so let it be the one to refuse.
for spec in plugins:
    print(f"plugin\t{spec}")

for note in notes:
    print(f"note\t{note}")
PY
)

for declaration in "${DECLARATIONS[@]}"; do
    IFS=$'\t' read -r kind name detail <<<"$declaration"
    case "$kind" in
        marketplace)
            if claude plugin marketplace add "$detail" >/dev/null 2>&1; then
                echo "install-plugins: marketplace '$name' registered"
            else
                warn "could not register marketplace '$name' from $detail"
                warn "  A clone failure, missing git credentials, or a source the"
                warn "  managed policy's strictKnownMarketplaces refuses."
            fi
            ;;
        plugin)
            if claude plugin install "$name" >/dev/null 2>&1; then
                echo "install-plugins: $name ready"
            else
                warn "could not install '$name'."
                warn "  The marketplace is cloned from the remote default branch, so a plugin"
                warn "  that exists only on a feature branch is not installable until merged."
                warn "  Retry with: claude plugin install $name"
            fi
            ;;
        note)
            warn "$name"
            ;;
    esac
done

exit 0

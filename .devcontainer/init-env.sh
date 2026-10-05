#!/usr/bin/env bash
# =============================================================================
# Prepare the HOST for the dev container (initializeCommand).
#
# Three jobs, all of which have to happen before the container is created:
#
#  1. .devcontainer/.env, with a freshly generated value for every secret, the
#     Frappe pins, the project name, and an empty line per model-provider key
#     for LiteLLM.
#     Compose reads it when it creates the services, which is earlier than any
#     hook running inside the container could write it.
#  2. Copies of the host files the container needs, ~/.gitconfig,
#     ~/.ssh/allowed_signers and ~/.npmrc, next to this script. Compose mounts the copies by
#     a relative path, which needs no ${localEnv:HOME} and so works on Windows,
#     and a copy cannot go stale the way a bind-mounted file does when the
#     host rewrites it.
#  3. The bind-mount directories devcontainer.json declares. A bind mount whose
#     source is missing aborts container creation.
#
# Runs on macOS, Linux and Windows, the last from WSL2 or Git Bash, which is
# what provides bash and HOME there.
#
# Idempotent: an existing .env is left alone, so a rebuild keeps the password
# the existing database was created with. Pass --force to rotate it, which
# means the old database can no longer be opened.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HERE/.env"
S3_TEMPLATE="$HERE/seaweedfs-s3.json.template"
S3_CONFIG="$HERE/seaweedfs-s3.json"
REALM_TEMPLATE="$HERE/keycloak-realm.json.template"
REALM_CONFIG="$HERE/keycloak-realm.json"

# Every secret this stack needs, generated. The provider keys are yours, so
# they are written empty, and LiteLLM simply has no model until one is filled.
SECRETS=(DB_ROOT_PASSWORD ADMIN_PASSWORD S3_ACCESS_KEY S3_SECRET_KEY
    KEYCLOAK_PASSWORD KEYCLOAK_CLIENT_SECRET LITELLM_MASTER_KEY)
PROVIDER_KEYS=(ANTHROPIC_API_KEY OPENAI_API_KEY AZURE_API_KEY AZURE_API_BASE AZURE_API_VERSION)

# The Frappe pins, the only place they are written. FRAPPE_VERSION is the exact
# release install-bench.sh installs: set it to the one your production image
# is built from. FRAPPE_PYTHON and FRAPPE_NODE are the Python and Node
# frappe/build carries at that tag, which the Dockerfile makes the default.
DEFAULT_FRAPPE_VERSION=v16.35.0
DEFAULT_FRAPPE_PYTHON=3.14.7
DEFAULT_FRAPPE_NODE=24.21.0
PINS=(FRAPPE_VERSION FRAPPE_PYTHON FRAPPE_NODE)

usage() {
    cat <<'EOF'
Usage: init-env.sh [--force] [--print] [--project-name NAME]

Generate .devcontainer/.env with a random value per secret and the Compose
project name, render seaweedfs-s3.json and keycloak-realm.json from it, copy
~/.gitconfig, ~/.ssh/allowed_signers and ~/.npmrc into .devcontainer/, and
create the host directories the container bind-mounts. Run automatically as
the dev container's initializeCommand.

  --force              replace an existing .env. The database created with
                       the old password becomes unreachable
  --print              show the current values (or what would be generated)
                       and exit
  --project-name NAME  the Compose project and volume prefix to write, lower
                       case, digits, - and _
  -h                   show this help

The project name is, first found: --project-name, PROJECT_NAME in the
environment, the origin remote's repository name, the repository's folder
name. It is written once. Asking later for another one than .env holds is an
error, since Compose would open other volumes: to rename, edit .env, and the
stack starts on new, empty ones.

Exit status: 0 on success or when there was nothing to do, 1 on a bad
argument, a project name Compose refuses or one .env contradicts, 2 when a
value could not be generated.
EOF
}

force=false
print_only=false
project_name_arg=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
        usage
        exit 0
        ;;
    --force) force=true ;;
    --print) print_only=true ;;
    --project-name)
        [[ -n ${2:-} ]] || {
            usage >&2
            exit 1
        }
        project_name_arg="$2"
        shift
        ;;
    --project-name=*) project_name_arg="${1#*=}" ;;
    *)
        usage >&2
        exit 1
        ;;
    esac
    shift
done

# The name asked for, on the command line or, as the proxy is, in the shell
# that opens the container. Empty leaves it to derive_project_name.
requested_name="${project_name_arg:-${PROJECT_NAME:-}}"
if [[ -n $requested_name && ! $requested_name =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "init-env.sh: '$requested_name' is not a Compose project name." >&2
    echo "  Use lower case, digits, - and _, starting with a letter or a digit." >&2
    exit 1
fi
existing_name="$(grep -sE '^PROJECT_NAME=' "$ENV_FILE" | cut -d= -f2- || true)"

# 32 characters of [A-Za-z0-9]. No openssl dependency, and nothing that would
# need quoting in a .env, a URL or a shell command.
random_secret() {
    local value
    value="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32 || true)"
    [[ ${#value} -eq 32 ]] || {
        echo "init-env.sh: could not generate a random value from /dev/urandom." >&2
        exit 2
    }
    printf '%s' "$value"
}

# The Compose project and volume names, so two projects made from this template
# on one machine never share a database. From the origin remote's repository
# name, which is the same in every clone and under DevPod, whose checkout
# folder is named after the workspace, else from this repository's folder.
# Reduced to what Compose accepts: lower case, digits, `-` and `_`. The
# template's own repository gets a name of its own, which no project made from
# it takes by accident.
derive_project_name() {
    local name
    name="$(git -C "$HERE/.." remote get-url origin 2>/dev/null || true)"
    name="${name%/}"
    name="${name%.git}"
    name="${name##*/}"
    name="${name##*:}"
    [[ -n $name ]] || name="$(basename "$(cd "$HERE/.." && pwd)")"
    name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' |
        LC_ALL=C sed -e 's/[^a-z0-9_-]/-/g' -e 's/^[^a-z0-9]*//')"
    [[ $name == icrc-frappe-devcontainer-template ]] && name=icrc-frappe-template
    printf '%s' "${name:-frappe}"
}

# The name a new .env, or one without PROJECT_NAME, gets.
new_project_name() {
    if [[ -n $requested_name ]]; then
        printf '%s' "$requested_name"
    else
        derive_project_name
    fi
}

write_env() {
    local tmp project_name
    # Kept through --force, which rotates the secrets and not the volumes.
    project_name="${existing_name:-$(new_project_name)}"
    tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
    {
        echo "# Generated by .devcontainer/init-env.sh. Not committed."
        echo "# Rotate with: bash .devcontainer/init-env.sh --force"
        echo "# Rotating invalidates the database created with the old password."
        echo ""
        echo "# The Compose project and the prefix of every volume. Changing it"
        echo "# starts the stack on new, empty volumes; the old ones stay behind."
        echo "PROJECT_NAME=${project_name}"
        echo ""
        for name in "${SECRETS[@]}"; do
            if [[ $name == LITELLM_MASTER_KEY ]]; then
                echo "# The API key a client sends to LiteLLM (http://litellm:4000 from"
                echo "# the bench, http://localhost:4000 from the host), as"
                echo "# \"Authorization: Bearer <key>\". Not a provider key."
            fi
            echo "${name}=$(random_secret)"
        done
        echo ""
        echo "# Model-provider keys for LiteLLM. Fill in the ones you use, then"
        echo "# restart the litellm service."
        for name in "${PROVIDER_KEYS[@]}"; do
            echo "${name}="
        done
        echo ""
        echo "# The exact Frappe release install-bench.sh installs, and the Python"
        echo "# and Node frappe/build carries at that tag. Align them with your"
        echo "# production image and rebuild the container; switch-version.sh"
        echo "# frappe VERSION rewrites FRAPPE_VERSION here."
        echo "FRAPPE_VERSION=${DEFAULT_FRAPPE_VERSION}"
        echo "FRAPPE_PYTHON=${DEFAULT_FRAPPE_PYTHON}"
        echo "FRAPPE_NODE=${DEFAULT_FRAPPE_NODE}"
    } >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$ENV_FILE"
}

# An .env written before a pin existed lacks it, and Compose refuses to build
# without it. Only the missing ones are appended; a value already set is kept.
# PROJECT_NAME is one of them: the stack then starts on volumes of that name,
# and the ones created before it existed, icrc-frappe*, are left behind.
add_missing_pins() {
    local project_name
    if ! grep -qE '^PROJECT_NAME=' "$ENV_FILE"; then
        project_name="$(new_project_name)"
        echo "PROJECT_NAME=${project_name}" >>"$ENV_FILE"
        echo "init-env.sh: added PROJECT_NAME=${project_name} to .devcontainer/.env."
        echo "  The stack starts on new, empty volumes; the old icrc-frappe* ones are left as they were."
    fi
    local name default
    for name in "${PINS[@]}"; do
        grep -qE "^${name}=" "$ENV_FILE" && continue
        default="DEFAULT_${name}"
        echo "${name}=${!default}" >>"$ENV_FILE"
        echo "init-env.sh: added ${name}=${!default} to .devcontainer/.env."
    done
}

# seaweedfs reads its identities from a JSON file, which Compose cannot
# interpolate, so it is rendered here from the template with the same keys.
render_s3_config() {
    [[ -f $S3_TEMPLATE ]] || return 0
    local access secret
    access="$(grep -E '^S3_ACCESS_KEY=' "$ENV_FILE" | cut -d= -f2-)"
    secret="$(grep -E '^S3_SECRET_KEY=' "$ENV_FILE" | cut -d= -f2-)"
    sed -e "s|__S3_ACCESS_KEY__|${access}|" -e "s|__S3_SECRET_KEY__|${secret}|" \
        "$S3_TEMPLATE" >"$S3_CONFIG"
}

# Same for the Keycloak realm: the client secret and the test user's password
# are placeholders in the template, so nothing in git holds a credential.
render_realm_config() {
    [[ -f $REALM_TEMPLATE ]] || return 0
    local client_secret password
    client_secret="$(grep -E '^KEYCLOAK_CLIENT_SECRET=' "$ENV_FILE" | cut -d= -f2-)"
    password="$(grep -E '^KEYCLOAK_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
    sed -e "s|__KEYCLOAK_CLIENT_SECRET__|${client_secret}|" -e "s|__KEYCLOAK_PASSWORD__|${password}|" \
        "$REALM_TEMPLATE" >"$REALM_CONFIG"
}

if [[ $print_only == true ]]; then
    if [[ -f $ENV_FILE ]]; then
        cat "$ENV_FILE"
    else
        echo "# No .env yet. A run would generate:"
        echo "PROJECT_NAME=$(new_project_name)"
        for name in "${SECRETS[@]}"; do echo "${name}=$(random_secret)"; done
        for name in "${PROVIDER_KEYS[@]}"; do echo "${name}="; done
        echo "FRAPPE_VERSION=${DEFAULT_FRAPPE_VERSION}"
        echo "FRAPPE_PYTHON=${DEFAULT_FRAPPE_PYTHON}"
        echo "FRAPPE_NODE=${DEFAULT_FRAPPE_NODE}"
    fi
    exit 0
fi

# Compose takes a PROJECT_NAME set in the shell over the one in .env, so a
# different one left exported would open another project's volumes. Stop
# before the container is created instead.
if [[ -n $requested_name && -n $existing_name && $requested_name != "$existing_name" ]]; then
    echo "init-env.sh: .devcontainer/.env has PROJECT_NAME=$existing_name, but $requested_name was asked for." >&2
    echo "  To keep $existing_name, unset PROJECT_NAME in this shell or drop --project-name." >&2
    echo "  To rename, edit .devcontainer/.env: the stack then starts on new, empty volumes." >&2
    exit 1
fi

if [[ -f $ENV_FILE && $force == false ]]; then
    echo "init-env.sh: .devcontainer/.env exists, left alone."
    add_missing_pins
else
    write_env
    echo "init-env.sh: wrote .devcontainer/.env with fresh secrets."
fi
render_s3_config
render_realm_config

if [[ -z ${HOME:-} ]]; then
    echo "init-env.sh: HOME is not set on the host." >&2
    echo "  On Windows, run from WSL2 or Git Bash, which sets it. See README.md." >&2
    exit 1
fi

# A fresh copy on every start, empty when the host has none, so the mount
# always has a file to map. The copy keeps the host file's mode rather than
# 600: the container user is not remapped to the host UID, so a private file
# would be unreadable inside for anyone whose UID is not 1000. Both copies are
# git-ignored, and the gitconfig and npmrc ones can hold a credential.
copy_host_file() {
    local source="$1" target="$2" missing="$3"
    if [[ -f $source ]]; then
        cp -p "$source" "$target"
    else
        : >"$target"
        echo "init-env.sh: no ${source/#$HOME/\~}, ${missing}."
    fi
}
copy_host_file "$HOME/.gitconfig" "$HERE/.gitconfig.host" \
    "git in the container has no identity"
copy_host_file "$HOME/.ssh/allowed_signers" "$HERE/.allowed_signers.host" \
    "git in the container cannot verify a signature"
copy_host_file "$HOME/.npmrc" "$HERE/.npmrc.host" \
    "npm in the container uses the public registry"

# Less the host's prefix: nvm refuses to run under one, and a host path would
# send `npm install -g` somewhere the container cannot write. Rewritten in
# place, so the copy keeps its mode.
if [[ -s "$HERE/.npmrc.host" ]]; then
    npmrc="$(grep -Ev '^[[:space:]]*prefix[[:space:]]*=' "$HERE/.npmrc.host" || true)"
    printf '%s\n' "$npmrc" >"$HERE/.npmrc.host"
fi

# The bind-mount directories. Docker creates a root-owned one for whichever is
# missing. ~/.config/herdr holds herdr's control socket and is inert for a
# host without herdr.
mkdir -p "$HOME/.config/gh" "$HOME/.config/herdr" "$HOME/.claude"

exit 0

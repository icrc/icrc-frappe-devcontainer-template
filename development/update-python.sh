#!/bin/bash
# =============================================================================
# Recreate the bench's virtualenv on another Python, every app reinstalled.
#
# The virtualenv links to the interpreter it was made on. A rebuild of the
# container on another FRAPPE_PYTHON removes that interpreter, and every bench
# command then fails. `bench migrate-env` does the work. Around it, this script
# checks that the target Python is installed, keeps the current virtualenv in
# archived/envs, checks that every app imports, and puts the previous
# virtualenv back if any step fails.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: update-python.sh [-y] [PYTHON]

Recreate the virtualenv of the bench on PYTHON and reinstall every app into
it. Run it after a rebuild of the container on another FRAPPE_PYTHON, or when
a script says the bench's Python is gone.

  PYTHON    a version pyenv has installed, e.g. 3.14.8, or an interpreter,
            e.g. python3.12 or a path. Default FRAPPE_PYTHON from
            .devcontainer/.env
  -y        recreate it without asking. Also --yes, --force
  -h        show this help

The bench must be stopped. The current virtualenv is kept in archived/envs/
in the bench, and put back if the update fails. The sites and the app
checkouts are not touched.

Exit status: 0 on success, 1 on a bad argument or a refusal, 2 on failure.
EOF
    return
}

ASSUME_YES=false
args=()
for arg in "$@"; do
    case "$arg" in
    -h | --help)
        usage
        exit 0
        ;;
    -y | --yes | --force)
        # shellcheck disable=SC2034 # read by confirm() in common.sh
        ASSUME_YES=true
        ;;
    *) args+=("$arg") ;;
    esac
done
set -- "${args[@]}"

WANTED="${1:-${FRAPPE_PYTHON:-}}"
[[ -n $WANTED ]] || error_exit "No PYTHON given, and no FRAPPE_PYTHON in $ENV_FILE."

require_bench --any-python
cd "$BENCH_DIR"

# A bare version is one of pyenv's, anything else is looked up on PATH. The
# interpreter's own sys.executable, so a pyenv shim is not what the
# virtualenv ends up linked to.
resolve_python() {
    local wanted="$1" candidate="$1"
    if [[ $wanted =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        candidate="$(pyenv root)/versions/$wanted/bin/python"
    fi
    "$candidate" -c 'import sys; print(sys.executable)' 2>/dev/null
    return
}

python_version() {
    local python="$1"
    "$python" -c 'import platform; print(platform.python_version())'
    return
}

PYTHON_BIN="$(resolve_python "$WANTED")" ||
    error_exit "Python $WANTED is not installed. Set FRAPPE_PYTHON and rebuild the container, or: pyenv install $WANTED"
NEW_VERSION="$(python_version "$PYTHON_BIN")"

if [[ -x env/bin/python ]]; then
    CURRENT_VERSION="$(python_version env/bin/python)"
else
    CURRENT_VERSION="$(sed -n 's/^version_info = //p' env/pyvenv.cfg 2>/dev/null || true), no longer installed"
fi
log_info "The bench runs on Python $CURRENT_VERSION. Target: $NEW_VERSION, $PYTHON_BIN"
if [[ $CURRENT_VERSION == "$NEW_VERSION" ]]; then
    log_info "Already there. Nothing to do."
    exit 0
fi

# Every Frappe process bench starts runs this module, and would lose its
# interpreter halfway.
if pgrep --full 'frappe.utils.bench_helper' >/dev/null; then
    error_exit "The bench is running. Stop it first: ./stop-bench.sh"
fi

confirm "Recreate the virtualenv on Python $NEW_VERSION? The current one is kept in archived/envs." ||
    exit 1

BACKUP="archived/envs/env-$(date +%Y%m%d-%H%M%S)"
restore() {
    log_error "The update failed. Putting the previous virtualenv back."
    rm -rf env
    mv "$BACKUP" env
    exit 2
}

mkdir -p archived/envs
mv env "$BACKUP"
trap restore INT TERM

# --no-backup: the backup is the one above, at a path this script knows.
bench migrate-env --no-backup "$PYTHON_BIN" || restore

mapfile -t APPS < <(grep -v '^[[:space:]]*$' sites/apps.txt)
for app in "${APPS[@]}"; do
    env/bin/python -c "import $app" || restore
done
trap - INT TERM

log_info "Python $CURRENT_VERSION -> $NEW_VERSION, ${#APPS[@]} app(s) reinstalled: ${APPS[*]}"
if [[ -n ${FRAPPE_PYTHON:-} && $NEW_VERSION != "$FRAPPE_PYTHON" ]]; then
    log_warn "FRAPPE_PYTHON is $FRAPPE_PYTHON, so the next rebuild can remove Python $NEW_VERSION again."
fi
log_info "The previous virtualenv is in $BENCH_DIR/$BACKUP. Delete it once the bench works."

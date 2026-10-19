#!/usr/bin/env bash
# template-sync.sh
# Checks that a project made from this template has not drifted from it.
#
# Every file tracked in both the project and the template must be identical,
# except the ones .template-sync at the project root lists as the project's
# own. A file of the template the project does not have must be listed too. A
# file only the project has is the project's business and is not checked.
#
# Usage:
#   template-sync.sh TEMPLATE            # a checkout of the template, or its git URL
#   template-sync.sh --ref REF TEMPLATE  # compare with REF, origin/main by default
#   template-sync.sh --diff TEMPLATE     # print the diff of every file that differs,
#                                        # the listed ones included
#
# A URL is cloned, shallow, into a temporary directory; REF is then a branch,
# and the default branch when it is not given. The project side is the working
# tree of the repository this script is in, so an edit is checked before it is
# committed.
#
# .template-sync holds one path or glob per line, `#` starts a comment. A glob
# is a bash pattern, so `*` matches across `/`: `.github/*` covers the folder.
# A listed file that has become identical is reported too, so the list never
# keeps a file that no longer needs it.
#
# Exit status: 0 in sync, 1 on drift, 2 on a usage or template error.

set -euo pipefail

# shellcheck source=development/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MANIFEST="$REPO_DIR/.template-sync"
REF=""
SHOW_DIFF=0
TEMPLATE=""

usage() {
    local status="$1"
    sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit "$status"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref) [[ $# -ge 2 ]] || usage 2; REF="$2"; shift 2 ;;
        --diff) SHOW_DIFF=1; shift ;;
        -h|--help) usage 0 ;;
        -*) log_error "Unknown option: $1"; usage 2 ;;
        *) [[ -z $TEMPLATE ]] || usage 2; TEMPLATE="$1"; shift ;;
    esac
done
[[ -n $TEMPLATE ]] || usage 2

if [[ $TEMPLATE == *://* || $TEMPLATE == git@* ]]; then
    clone="$(mktemp -d)"
    trap 'rm -rf "$clone"' EXIT
    git clone --quiet --depth 1 ${REF:+--branch "$REF"} "$TEMPLATE" "$clone" ||
        { log_error "Could not clone $TEMPLATE."; exit 2; }
    TEMPLATE="$clone"
    REF=HEAD
fi
REF="${REF:-origin/main}"
git -C "$TEMPLATE" rev-parse --verify --quiet "$REF^{commit}" >/dev/null ||
    { log_error "$REF is not a commit in $TEMPLATE."; exit 2; }

patterns=()
if [[ -f $MANIFEST ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n $line ]] && patterns+=("$line")
    done <"$MANIFEST"
fi

# Whether .template-sync lists PATH as the project's own.
is_listed() {
    local path="$1" pattern
    for pattern in "${patterns[@]}"; do
        # shellcheck disable=SC2053 # the pattern is a glob on purpose
        [[ $path == $pattern ]] && return 0
    done
    return 1
}

# The diff from the template's PATH to the project's. diff exits 1 when the
# files differ, which is the expected case here, not an error.
show_diff() {
    local path="$1"
    diff -u --label "template/$path" --label "project/$path" \
        <(git -C "$TEMPLATE" show "$REF:$path") "$REPO_DIR/$path" || true
    return 0
}

# The blob id of every file tracked in the project, read from the working tree.
declare -A project_blob
mapfile -t project_files < <(git -C "$REPO_DIR" ls-files)
mapfile -t project_ids < <(
    for f in "${project_files[@]}"; do
        [[ -f "$REPO_DIR/$f" ]] && printf '%s\n' "$f"
    done | git -C "$REPO_DIR" hash-object --stdin-paths
)
i=0
for f in "${project_files[@]}"; do
    [[ -f "$REPO_DIR/$f" ]] || continue
    project_blob[$f]="${project_ids[i]}"
    i=$((i + 1))
done

drift=0
same=0
own=0
while IFS=$'\t' read -r meta path; do
    blob="${meta##* }"
    if is_listed "$path"; then
        if [[ ${project_blob[$path]:-} == "$blob" ]]; then
            log_warn "LISTED    $path is identical to the template: drop it from .template-sync."
            drift=1
        else
            own=$((own + 1))
            [[ $SHOW_DIFF == 1 && -n ${project_blob[$path]:-} ]] && show_diff "$path"
        fi
    elif [[ -z ${project_blob[$path]:-} ]]; then
        log_error "MISSING   $path is in the template, not here, and not listed."
        drift=1
    elif [[ ${project_blob[$path]} != "$blob" ]]; then
        log_error "DRIFT     $path differs from the template."
        [[ $SHOW_DIFF == 1 ]] && show_diff "$path"
        drift=1
    else
        same=$((same + 1))
    fi
done < <(git -C "$TEMPLATE" ls-tree -r "$REF")

summary="$same identical, $own listed as the project's own, template at $(git -C "$TEMPLATE" rev-parse --short "$REF")."
if [[ $drift == 1 ]]; then
    log_error "Out of sync with the template: $summary"
    exit 1
fi
log_info "In sync with the template: $summary"
exit 0

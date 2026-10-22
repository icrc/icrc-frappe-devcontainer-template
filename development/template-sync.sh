#!/usr/bin/env bash
# template-sync.sh
# Shows how a project made from icrc-frappe-devcontainer-template differs from
# the template on GitHub, and checks that it has not drifted from it.
#
# Every file tracked in both the project and the template must be identical,
# except the ones .template-sync at the project root lists as the project's
# own. A file of the template the project does not have must be listed too. A
# file only the project has is the project's business and is not checked.
#
# Usage:
#   template-sync.sh              # compare with the template's default branch
#   template-sync.sh --ref REF    # compare with the template's branch or tag REF
#   template-sync.sh --quiet      # the report only, without the diffs
#
# The template is cloned, shallow, into a temporary directory, and the diff of
# every file that differs is printed, the listed ones included. The project
# side is the working tree of the repository this script is in, so an edit is
# checked before it is committed. TEMPLATE_URL in the environment compares
# with another repository, file:///path/to/checkout for a local one.
#
# .template-sync holds one path or glob per line, `#` starts a comment. A glob
# is a bash pattern, so `*` matches across `/`: `.github/*` covers the folder.
# A listed file that has become identical is reported too, so the list never
# keeps a file that no longer needs it. The listed files that differ are named
# before the report, as a change the template makes to one shows only in its
# diff and never as drift.
#
# Exit status: 0 in sync, 1 on drift, 2 on a usage or clone error.

set -euo pipefail

# shellcheck source=development/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/icrc/icrc-frappe-devcontainer-template.git}"
MANIFEST="$REPO_DIR/.template-sync"
REF=""
QUIET=0

usage() {
    local status="$1"
    sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit "$status"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref) [[ $# -ge 2 ]] || usage 2; REF="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) usage 0 ;;
        *) log_error "Unknown argument: $1"; usage 2 ;;
    esac
done

TEMPLATE="$(mktemp -d)"
trap 'rm -rf "$TEMPLATE"' EXIT
git clone --quiet --depth 1 ${REF:+--branch "$REF"} "$TEMPLATE_URL" "$TEMPLATE" ||
    { log_error "Could not clone ${REF:+$REF of }$TEMPLATE_URL."; exit 2; }

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

# The diff from the template's PATH to the project's, unless --quiet. diff
# exits 1 when the files differ, which is the expected case here, not an error.
show_diff() {
    local path="$1"
    [[ $QUIET == 1 ]] && return 0
    diff -u --label "template/$path" --label "project/$path" \
        "$TEMPLATE/$path" "$REPO_DIR/$path" || true
    return 0
}

drift=0
same=0
own=0
own_differ=()
while IFS= read -r -d '' path; do
    if is_listed "$path"; then
        if [[ -f "$REPO_DIR/$path" ]] && cmp -s "$TEMPLATE/$path" "$REPO_DIR/$path"; then
            log_warn "LISTED    $path is identical to the template: drop it from .template-sync."
            drift=1
        else
            own=$((own + 1))
            if [[ -f "$REPO_DIR/$path" ]]; then
                own_differ+=("$path")
                show_diff "$path"
            fi
        fi
    elif [[ ! -f "$REPO_DIR/$path" ]]; then
        log_error "MISSING   $path is in the template, not here, and not listed."
        drift=1
    elif ! cmp -s "$TEMPLATE/$path" "$REPO_DIR/$path"; then
        log_error "DRIFT     $path differs from the template."
        show_diff "$path"
        drift=1
    else
        same=$((same + 1))
    fi
done < <(git -C "$TEMPLATE" ls-files -z)

if [[ ${#own_differ[@]} -gt 0 ]]; then
    log_info "Listed and differing, so read their diffs for a template change to bring: ${own_differ[*]}"
fi

summary="$same identical, $own listed as the project's own, template at $(git -C "$TEMPLATE" rev-parse --short HEAD)."
if [[ $drift == 1 ]]; then
    log_error "Out of sync with the template: $summary"
    exit 1
fi
log_info "In sync with the template: $summary"
exit 0

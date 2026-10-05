#!/usr/bin/env bash
# =============================================================================
# Install the agent skills declared in skills.json (postStartCommand).
#
# Each entry is a GitHub repository, a full commit sha, and the folder holding
# its skills, one subfolder with a SKILL.md each. They are copied into
# .claude/skills at the repository root, which Claude Code reads from
# /workspace/development and every folder above it, and which .gitignore keeps
# out of every commit: a skill is installed here, never redistributed, so a
# repository with no licence, frappe/skills among them, can still be used.
#
# Idempotent: a repository already installed at its pinned commit is skipped,
# so it runs on every start. Warns and exits 0 rather than blocking the start.
# =============================================================================
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<'EOF'
Usage: get-skills.sh [--force]

Copy the skills of every repository in skills.json, at its pinned commit, into
.claude/skills at the repository root, where Claude Code finds them.

  --force   reinstall even when the pinned commit is already installed
  -h        show this help

To add a repository, append to skills.json:
  {"repo": "owner/name", "ref": "<full commit sha>", "path": "<folder of skills>"}
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

MANIFEST="$DEV_DIR/skills.json"
SKILLS_DIR="$REPO_DIR/.claude/skills"
# One "repo sha" line per installed repository.
STATE="$SKILLS_DIR/.installed"

command -v jq >/dev/null || {
    log_warn "jq is not on PATH, so no skill is installed. Rebuild the container."
    exit 0
}
[[ -f $MANIFEST ]] || exit 0

mkdir -p "$SKILLS_DIR"
touch "$STATE"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

while IFS=$'\t' read -r repo ref path; do
    if [[ $force == false ]] && grep -qxF "$repo $ref" "$STATE"; then
        continue
    fi
    log_info "Installing the skills of $repo at ${ref:0:7}..."

    # The one commit, fetched by its sha: a moved branch or tag cannot change
    # what is installed.
    src="$tmp/${repo//\//_}"
    if ! { git init --quiet "$src" &&
        git -C "$src" fetch --quiet --depth 1 "https://github.com/$repo.git" "$ref" &&
        git -C "$src" -c advice.detachedHead=false checkout --quiet FETCH_HEAD; }; then
        log_warn "Cannot fetch $ref from $repo, so its skills are not installed."
        continue
    fi

    count=0
    for skill in "$src/$path"/*/; do
        [[ -f $skill/SKILL.md ]] || continue
        name="$(basename "$skill")"
        rm -rf "${SKILLS_DIR:?}/$name"
        cp -R "$skill" "$SKILLS_DIR/$name"
        count=$((count + 1))
    done
    if ((count == 0)); then
        log_warn "$repo has no skill under $path/ at ${ref:0:7}. Check skills.json."
        continue
    fi

    awk -v repo="$repo" '$1 != repo' "$STATE" >"$tmp/state"
    echo "$repo $ref" >>"$tmp/state"
    mv "$tmp/state" "$STATE"
    log_info "  $count skill(s) from $repo."
done < <(jq -r '.[] | [.repo, .ref, .path] | @tsv' "$MANIFEST")

exit 0

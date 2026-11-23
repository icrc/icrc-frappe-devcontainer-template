#!/bin/bash
# PreToolUse hook for Claude Code's Bash tool, declared in claude-settings.json.
# It refuses two shapes of command that the sandbox handles badly, and tells
# Claude how to run the command instead:
#  * a command that starts with cd, which makes Claude ask to work outside its
#    working directory, a prompt for nothing;
#  * bench chained with cd, &&, ; or a pipe. The sandbox exclusion matches a
#    bare bench command only, so a chained one stays in the sandbox, whose
#    network cannot reach MariaDB or Redis.
# Exit 2 blocks the call and hands stderr to Claude. Exit 0 lets it run.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')

if grep -qE '^[[:space:]]*cd([[:space:]]|$)' <<<"$cmd"; then
  echo 'Do not start a command with cd. Give absolute paths, or use the Read and Grep tools.' >&2
  exit 2
fi

if grep -qE '(^|[;&|(][[:space:]]*)bench([[:space:]]|$)' <<<"$cmd" \
  && { [[ $cmd == *$'\n'* ]] || grep -qE '&&|\||;' <<<"$cmd"; }; then
  echo 'Run bench as a single command from the bench directory, without cd, &&, ; or a pipe. Only a bare bench command leaves the sandbox and reaches MariaDB and Redis.' >&2
  exit 2
fi

exit 0

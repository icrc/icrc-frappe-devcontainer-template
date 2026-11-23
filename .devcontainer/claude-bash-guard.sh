#!/bin/bash
# PreToolUse hook for Claude Code's Bash tool, declared in claude-settings.json.
# It refuses two shapes of command that the sandbox handles badly, and tells
# Claude how to run the command instead:
#  * cd chained with other commands, which makes Claude ask to work outside
#    its working directory, a prompt for nothing. A cd on its own is let
#    through: it is how a session started elsewhere gets into the bench, and
#    the directory it moves to holds for the commands that follow;
#  * bench chained with cd, &&, ; or a pipe. The sandbox exclusion matches a
#    bare bench command only, so a chained one stays in the sandbox, whose
#    network cannot reach MariaDB or Redis.
# Exit 2 blocks the call and hands stderr to Claude. Exit 0 lets it run.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')
lone_cd='^[[:space:]]*cd[[:space:]]+[^;&|<>[:space:]]+[[:space:]]*$'

if grep -qE '^[[:space:]]*cd([[:space:]]|$)' <<<"$cmd" && ! [[ $cmd =~ $lone_cd ]]; then
  echo 'Do not chain cd with other commands. Run cd on its own first, then the command, or give absolute paths.' >&2
  exit 2
fi

if grep -qE '(^|[;&|(][[:space:]]*)bench([[:space:]]|$)' <<<"$cmd" \
  && { [[ $cmd == *$'\n'* ]] || grep -qE '&&|\||;' <<<"$cmd"; }; then
  echo 'Run bench as a single command from the bench directory, without cd, &&, ; or a pipe. Only a bare bench command leaves the sandbox and reaches MariaDB and Redis. To get into the bench, run cd to it on its own first.' >&2
  exit 2
fi

exit 0

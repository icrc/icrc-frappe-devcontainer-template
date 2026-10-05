# Shortcuts for Frappe development. Sourced from ~/.zshrc by the Dockerfile.

DEV_DIR="/workspace/development"
BENCH_DIR="$DEV_DIR/frappe-bench"

# devpod ssh and docker exec announce a bare `xterm` and no COLORTERM, which
# drops Claude Code, lazygit and micro to 16 colours: Claude Code's selection
# highlight then vanishes. Every terminal that reaches this container, the
# VS Code and JetBrains ones included, does 24-bit colour.
[[ $TERM == xterm ]] && export TERM=xterm-256color
export COLORTERM="${COLORTERM:-truecolor}"

# Navigation
alias godev="cd $DEV_DIR"
alias gobench="cd $BENCH_DIR"
alias goapps="cd $BENCH_DIR/apps"
alias gosites="cd $BENCH_DIR/sites"

# Bench lifecycle. Each one is the script of the same name in development/, so
# the alias and the script never say different things.
alias frstart="$DEV_DIR/start.sh"
alias frstop="$DEV_DIR/stop-bench.sh"
alias frmigrate="$DEV_DIR/migrate-site.sh"
alias frconsole="$DEV_DIR/console.sh"
alias frdb="$DEV_DIR/db-console.sh"
alias frcache="$DEV_DIR/clear-cache.sh"
alias frbuild="$DEV_DIR/build.sh"
alias frwatch="$DEV_DIR/watch.sh"
alias frapps="$DEV_DIR/get-apps.sh"
alias frnewapp="$DEV_DIR/new-app.sh"
alias frstatus="$DEV_DIR/repo-status.sh"
alias frswitch="$DEV_DIR/switch-version.sh"

# Git
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -10'
alias gp='git pull'
alias lg='lazygit'

# pyenv's shell integration, which frappe/bench sets up in ~/.bashrc only. The
# shims are already on PATH; this adds `pyenv shell` and the rehash.
command -v pyenv >/dev/null && eval "$(pyenv init - zsh)"

# nvm as a command, for a bench on the previous Node (`nvm use 22`). PATH
# already carries the default Node, so nothing is switched here.
[[ -s $NVM_DIR/nvm.sh ]] && source "$NVM_DIR/nvm.sh" --no-use

alias logs="tail -f $BENCH_DIR/logs/bench-start.log"
alias bat='batcat'

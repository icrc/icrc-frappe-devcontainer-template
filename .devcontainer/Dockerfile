# =============================================================================
# Frappe dev container.
#
# frappe/bench, the image frappe_docker develops on, with the tooling this
# repository's scripts need: zsh as the login shell, jq for apps.json, gh for
# pull requests, and a terminal editor that does not have to be learned.
#
# frappe/bench carries bench, and pyenv and nvm with the current and the
# previous Python and Node, so a bench on either major line of Frappe runs
# here. Pinned to a release, so a rebuild is the same container, and bumped by
# a Dependabot pull request, so a new toolchain is a change that is reviewed
# before development meets it. The Frappe version and
# the default Python and Node are pinned in .env, by FRAPPE_VERSION,
# FRAPPE_PYTHON and FRAPPE_NODE. Everything else is pinned to a release.
# =============================================================================
FROM docker.io/frappe/bench:v5.31.0

# zsh-in-docker publishes no checksum, so the digest is that of the release's
# script, taken when it was pinned. Bumping the version means taking it again.
ARG ZSH_IN_DOCKER_VERSION=1.2.1
ARG ZSH_IN_DOCKER_SHA256=0cf15b6f9c63a8103eb33bad87dc4b43fed0e0ad5884dff90f943ee1e868796e

# GitHub CLI. Debian has no `gh` package, so the release tarball is fetched and
# checked against the sha256 that release publishes. Bumping GH_VERSION means
# bumping both digests, from
# https://github.com/cli/cli/releases/download/v<version>/gh_<version>_checksums.txt
ARG GH_VERSION=2.101.0
ARG GH_SHA256_AMD64=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
ARG GH_SHA256_ARM64=b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f

# betterleaks, which the pre-commit hook runs on every commit. The successor to
# gitleaks, by the same author, which now takes security patches only; it reads
# the same config and gitleaks:allow comments. Fetched the same way as gh. The
# CI workflow in .github/workflows/betterleaks.yml reads these three lines, so
# a bump here moves both. Digests from
# https://github.com/betterleaks/betterleaks/releases/download/v<version>/checksums.txt
ARG BETTERLEAKS_VERSION=1.8.1
ARG BETTERLEAKS_SHA256_AMD64=efa407244e1ea8e35f582b8a42becdeac08bdead04f68eb752adda722d583c2a
ARG BETTERLEAKS_SHA256_ARM64=bbb578b12a2f65d7082ab436abf37724232bc71d8a078e3c41336574420f1b48

# lazygit, a terminal UI for git, aliased `lg` in custom.zsh. Fetched the same
# way as gh. Digests from
# https://github.com/jesseduffield/lazygit/releases/download/v<version>/checksums.txt
ARG LAZYGIT_VERSION=0.65.1
ARG LAZYGIT_SHA256_AMD64=02beacbcda0fa342e50ae3480ba8147307353af3fb28e1d5f790e02329c201a6
ARG LAZYGIT_SHA256_ARM64=49abecdf6adf4f2dfdb11bf7b9bfada267ea523612ed809d1c6d87f6c04000a7

USER root

#   jq        reads apps.json in get-apps.sh
#   micro     the editor EDITOR names below
#   chromium  the browser agent-browser drives: Debian's, built for both
#             architectures, rather than the Chrome for Testing download
#             agent-browser installs unchecked and only for amd64
#   bat       syntax-highlighted cat, aliased in custom.zsh
#   zstd      restoring a bench backup compressed with it
#   iproute2  ss, which stop-bench.sh uses to find what holds a port, and
#             ip, which init-firewall.sh reads the Compose network from
#   iptables  the egress firewall, init-firewall.sh
#   fzf       loaded by the oh-my-zsh plugin below
#   ripgrep   `rg`, which Claude Code uses instead of its bundled copy
#             (USE_BUILTIN_RIPGREP=0 below), being faster
#   fd-find   Debian names the binary `fdfind`, so `fd` is symlinked
#   tree      directory listings
# build-essential, curl, git, less, sudo and wget are already in frappe/bench.
#
# The slim base excludes /usr/share/doc/* from every package, and that is where
# Debian ships fzf's key-bindings.zsh and completion.zsh, which the oh-my-zsh
# plugin sources. dpkg reads dpkg.cfg.d/ in order and the last match wins, so
# this file, sorting after `docker`, lets them back in.
#
# gh, betterleaks and lazygit come as release tarballs, each checked against
# its pinned digest. fetch takes the tool, the URL and the two digests; each
# names its amd64 build its own way. curl is held to HTTPS, redirects included.
RUN printf 'path-include /usr/share/doc/fzf/*\n' > /etc/dpkg/dpkg.cfg.d/fzf \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    bat \
    chromium \
    fd-find \
    fzf \
    gnupg \
    iproute2 \
    iptables \
    jq \
    lsb-release \
    micro \
    procps \
    ripgrep \
    tree \
    zsh \
    zstd \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
    amd64|arm64) ;; \
    *) echo "unsupported architecture ${arch}" >&2; exit 1 ;; \
    esac \
    && fetch() { \
    sha="$3"; [ "${arch}" = arm64 ] && sha="$4"; \
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -o "/tmp/$1.tar.gz" "$2" \
    && echo "${sha}  /tmp/$1.tar.gz" | sha256sum -c - \
    && mkdir "/tmp/$1" && tar -xzf "/tmp/$1.tar.gz" --no-same-owner -C "/tmp/$1"; \
    } \
    && gh_dir="gh_${GH_VERSION}_linux_${arch}" \
    && fetch gh "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${gh_dir}.tar.gz" \
    "${GH_SHA256_AMD64}" "${GH_SHA256_ARM64}" \
    && install -m 0755 "/tmp/gh/${gh_dir}/bin/gh" /usr/local/bin/gh \
    && asset="$([ "${arch}" = amd64 ] && echo x64 || echo arm64)" \
    && fetch betterleaks \
    "https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/betterleaks_${BETTERLEAKS_VERSION}_linux_${asset}.tar.gz" \
    "${BETTERLEAKS_SHA256_AMD64}" "${BETTERLEAKS_SHA256_ARM64}" \
    && install -m 0755 /tmp/betterleaks/betterleaks /usr/local/bin/betterleaks \
    && asset="$([ "${arch}" = amd64 ] && echo x86_64 || echo arm64)" \
    && fetch lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${asset}.tar.gz" \
    "${LAZYGIT_SHA256_AMD64}" "${LAZYGIT_SHA256_ARM64}" \
    && install -m 0755 /tmp/lazygit/lazygit /usr/local/bin/lazygit \
    && rm -rf /tmp/gh /tmp/gh.tar.gz /tmp/betterleaks /tmp/betterleaks.tar.gz \
    /tmp/lazygit /tmp/lazygit.tar.gz \
# GitHub's public host keys, system-wide, so the first clone over ssh does not
# stop at a prompt. Pinned rather than scanned, so the build trusts no network
# answer: the keys GitHub publishes at https://api.github.com/meta, whose
# fingerprints are SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU,
# SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM and
# SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s. A rotation by GitHub
# replaces them here.
    && printf 'github.com %s\n' \
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
    'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
    'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=' \
    >>/etc/ssh/ssh_known_hosts \
# The workspace and the Claude config directory, created here so a volume
# mounted over either arrives frappe-owned: Docker initialises a fresh volume
# from the image content at its target, ownership included, and creates it
# root-owned when that target is missing. ~/.ssh likewise, for the
# allowed_signers file docker-compose.yml mounts into it.
#
# ~/.gitconfig is the container's own, writable, and includes the host's,
# mounted read-only at ~/.gitconfig-host. What the editor or devpod writes
# goes after the include, so it overrides the host's value and stays in the
# container instead of landing in the host file. Appended, so anything
# frappe/bench puts there is kept.
    && chsh -s /bin/zsh frappe \
    && mkdir -p /workspace /home/frappe/.claude/plugins /home/frappe/.config/gh \
    && install -d -m 0700 -o frappe -g frappe /home/frappe/.ssh \
    && printf '[include]\n\tpath = /home/frappe/.gitconfig-host\n' >>/home/frappe/.gitconfig \
    && chown -R frappe:frappe /workspace /home/frappe/.claude /home/frappe/.config \
    /home/frappe/.gitconfig \
# devpod's git credentials server runs `su frappe -c git config` from /root, and
# git 2.55 dies when it cannot stat /root/.git. Search-only (711), no listing.
    && chmod 0711 /root

USER frappe

# The Python and Node the bench runs on, those of frappe/build at
# FRAPPE_VERSION, installed next to the ones frappe/bench ships and made the
# default. Pinned to the patch release, so a bump of frappe/bench never
# moves the interpreter the bench's virtualenv points at. pyenv skips the
# build when frappe/bench already has that exact release. The names are not
# PYTHON_VERSION and NODE_VERSION: frappe/bench sets both with ENV, which
# would silently win over a build arg of the same name.
#
# ast-grep-cli, structural code search as `ast-grep` and `sg`, goes into that
# Python too: frappe/bench has no system pip. The pinned wheel is the upstream
# release binary, hash-checked by pip, with no per-architecture download to
# maintain. pyenv's shims find it because FRAPPE_PYTHON comes first in global.
#
# agent-browser, browser automation for agents, goes into that Node: it needs
# Node 24 or later. Pinned with yarn, checked by npm against the registry's
# integrity hash, and installed without lifecycle scripts: agent-browser's only
# sets the execute bit on the native binary its package ships, done here.
# virtualenv, which `bench migrate-env` runs, is pinned too.
ARG FRAPPE_PYTHON
ARG FRAPPE_NODE
ARG AST_GREP_VERSION=0.45.3
ARG VIRTUALENV_VERSION=21.14.7
ARG AGENT_BROWSER_VERSION=0.38.1
ARG YARN_VERSION=1.22.22
RUN pyenv install -s "${FRAPPE_PYTHON}" \
    && PYENV_VERSION="${FRAPPE_PYTHON}" pip install --no-cache-dir --only-binary :all: \
    "virtualenv==${VIRTUALENV_VERSION}" "ast-grep-cli==${AST_GREP_VERSION}" \
    && pyenv global "${FRAPPE_PYTHON}" "${PYTHON_VERSION_PREV}" \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${FRAPPE_NODE}" \
    && npm install -g --ignore-scripts "yarn@${YARN_VERSION}" \
    "agent-browser@${AGENT_BROWSER_VERSION}" \
    && chmod 0755 "$(npm root -g)"/agent-browser/bin/agent-browser-linux-* \
    && nvm alias default "${FRAPPE_NODE}" \
    && nvm use default \
    && rm -rf "${NVM_DIR}/.cache" \
    && pyenv rehash

# frappectl, a client for live Frappe sites, v16 and later. With no keyring in
# a container it reads FRAPPE_SITE, FRAPPE_API_KEY and FRAPPE_API_SECRET. In a
# virtualenv of its own, so its dependencies never reach the interpreter above,
# linked into ~/.local/bin, which frappe/bench puts on PATH. Pinned like
# ast-grep, and like it installed from wheels only, so no setup script runs.
ARG FRAPPECTL_VERSION=0.19.0
RUN PYENV_VERSION="${FRAPPE_PYTHON}" python -m venv /home/frappe/.local/share/frappectl \
    && /home/frappe/.local/share/frappectl/bin/pip install --no-cache-dir --only-binary :all: \
    "frappectl==${FRAPPECTL_VERSION}" \
    && mkdir -p /home/frappe/.local/bin \
    && ln -sf /home/frappe/.local/share/frappectl/bin/frappectl /home/frappe/.local/bin/frappectl

# agent-browser drives the Debian chromium installed above.
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium

ENV SHELL=/bin/zsh

ENV USE_BUILTIN_RIPGREP=0

# frappe/bench exports this from ~/.bashrc, which zsh never reads. Here it
# reaches every process, the scripts in development/ included.
ENV BENCH_DEVELOPER=1

ENV EDITOR=micro
ENV VISUAL=micro

# zsh with the powerlevel10k theme. `-p fzf` only enables the oh-my-zsh plugin;
# the fzf it loads is the Debian package installed above. The script is checked
# against its digest before it runs.
RUN curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -o /tmp/zsh-in-docker.sh \
    "https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh" \
    && echo "${ZSH_IN_DOCKER_SHA256}  /tmp/zsh-in-docker.sh" | sha256sum -c - \
    && sh /tmp/zsh-in-docker.sh \
    -p git \
    -p fzf \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.zsh_history" \
    -x \
    && rm -f /tmp/zsh-in-docker.sh

# Root-owned and read-only, so nothing in the container rewrites the shortcuts.
COPY --chmod=0644 zsh/custom.zsh /home/frappe/.zsh-custom.zsh
RUN printf '\n# Frappe shortcuts\nsource /home/frappe/.zsh-custom.zsh\n' >> /home/frappe/.zshrc

ENV CLAUDE_CONFIG_DIR=/home/frappe/.claude

# development/ on PATH, so the git-* wrappers there answer as `git repo-status`
# and `git pr-sync` in every shell, not only the interactive zsh that sources
# custom.zsh. APPENDED, never prepended: the directory is a bind mount the
# developer writes, and it must not shadow anything in /usr/local/bin.
ENV PATH="${PATH}:/workspace/development"

# The egress firewall, and sudo cut down to it. frappe/bench gives the frappe
# user sudo for everything, which would let any process in the container flush
# the rules; what is left is the one entry that applies them.
# Last, so nothing above loses a sudo it needs, and so an allowlist change
# rebuilds this layer alone. The build fails if a wider entry survives: a base
# image that grants sudo another way must not pass unnoticed.
USER root
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY egress-allowlist /etc/icrc-egress-allowlist
RUN command -v setpriv >/dev/null \
    && chmod 0755 /usr/local/bin/init-firewall.sh \
    && chmod 0644 /etc/icrc-egress-allowlist \
    && sed -i '/^frappe[[:space:]]/d' /etc/sudoers \
    && grep -rl '^frappe[[:space:]]' /etc/sudoers.d | xargs -r rm -f \
    && (gpasswd -d frappe sudo 2>/dev/null || true) \
    && echo "frappe ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" \
    >/etc/sudoers.d/frappe-firewall \
    && chmod 0440 /etc/sudoers.d/frappe-firewall \
    && visudo -c \
    && sudo -l -U frappe | grep -q '/usr/local/bin/init-firewall.sh' \
    && ! sudo -l -U frappe | grep -Eq '(NOPASSWD: *|\) *)ALL$'
USER frappe

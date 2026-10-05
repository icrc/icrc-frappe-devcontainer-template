# =============================================================================
# Frappe dev container.
#
# frappe/bench, the image frappe_docker develops on, with the tooling this
# repository's scripts need: zsh as the login shell, jq for apps.json, gh for
# pull requests, and a terminal editor that does not have to be learned.
#
# frappe/bench carries bench, and pyenv and nvm with the current and the
# previous Python and Node, so a bench on either major line of Frappe runs
# here. latest on purpose: Frappe rebuilds it daily, so a rebuild brings the
# newest toolchain and an app meets a dependency upgrade in development first.
# The Frappe version and the default Python and Node are pinned in .env, by
# FRAPPE_VERSION, FRAPPE_PYTHON and FRAPPE_NODE. Everything else is pinned to
# a release.
# =============================================================================
FROM docker.io/frappe/bench:latest

ARG ZSH_IN_DOCKER_VERSION=1.2.1

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
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
    amd64) sha="${GH_SHA256_AMD64}" ;; \
    arm64) sha="${GH_SHA256_ARM64}" ;; \
    *) echo "gh: unsupported architecture ${arch}" >&2; exit 1 ;; \
    esac \
    && tarball="gh_${GH_VERSION}_linux_${arch}.tar.gz" \
    && curl -fsSL -o "/tmp/${tarball}" \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${tarball}" \
    && echo "${sha}  /tmp/${tarball}" | sha256sum -c - \
    && tar -xzf "/tmp/${tarball}" -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh \
    && rm -rf "/tmp/${tarball}" "/tmp/gh_${GH_VERSION}_linux_${arch}"

# betterleaks names its amd64 build x64.
RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
    amd64) asset=x64; sha="${BETTERLEAKS_SHA256_AMD64}" ;; \
    arm64) asset=arm64; sha="${BETTERLEAKS_SHA256_ARM64}" ;; \
    *) echo "betterleaks: unsupported architecture ${arch}" >&2; exit 1 ;; \
    esac \
    && tarball="betterleaks_${BETTERLEAKS_VERSION}_linux_${asset}.tar.gz" \
    && curl -fsSL -o "/tmp/${tarball}" \
    "https://github.com/betterleaks/betterleaks/releases/download/v${BETTERLEAKS_VERSION}/${tarball}" \
    && echo "${sha}  /tmp/${tarball}" | sha256sum -c - \
    && tar -xzf "/tmp/${tarball}" --no-same-owner -C /usr/local/bin betterleaks \
    && chmod 0755 /usr/local/bin/betterleaks \
    && rm -f "/tmp/${tarball}"

# lazygit names its amd64 build x86_64.
RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
    amd64) asset=x86_64; sha="${LAZYGIT_SHA256_AMD64}" ;; \
    arm64) asset=arm64; sha="${LAZYGIT_SHA256_ARM64}" ;; \
    *) echo "lazygit: unsupported architecture ${arch}" >&2; exit 1 ;; \
    esac \
    && tarball="lazygit_${LAZYGIT_VERSION}_linux_${asset}.tar.gz" \
    && curl -fsSL -o "/tmp/${tarball}" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/${tarball}" \
    && echo "${sha}  /tmp/${tarball}" | sha256sum -c - \
    && tar -xzf "/tmp/${tarball}" --no-same-owner -C /usr/local/bin lazygit \
    && chmod 0755 /usr/local/bin/lazygit \
    && rm -f "/tmp/${tarball}"

# GitHub's host keys, system-wide, so the first clone over ssh does not stop at
# a prompt. Scanned, then checked against the fingerprints GitHub publishes at
# https://api.github.com/meta: a key that does not match fails the build
# rather than being trusted.
ARG GITHUB_SSH_FINGERPRINTS="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s"
RUN ssh-keyscan -t ed25519,ecdsa,rsa github.com >/tmp/github.keys 2>/dev/null \
    && ssh-keygen -lf /tmp/github.keys | awk '{print $2}' | sort >/tmp/github.scanned \
    && printf '%s\n' ${GITHUB_SSH_FINGERPRINTS} | sort | diff - /tmp/github.scanned \
    && cat /tmp/github.keys >>/etc/ssh/ssh_known_hosts \
    && rm /tmp/github.keys /tmp/github.scanned

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
RUN chsh -s /bin/zsh frappe \
    && mkdir -p /workspace /home/frappe/.claude/plugins /home/frappe/.config/gh \
    && install -d -m 0700 -o frappe -g frappe /home/frappe/.ssh \
    && printf '[include]\n\tpath = /home/frappe/.gitconfig-host\n' >>/home/frappe/.gitconfig \
    && chown -R frappe:frappe /workspace /home/frappe/.claude /home/frappe/.config \
    /home/frappe/.gitconfig

# devpod's git credentials server runs `su frappe -c git config` from /root, and
# git 2.55 dies when it cannot stat /root/.git. Search-only (711), no listing.
RUN chmod 0711 /root

USER frappe

# The Python and Node the bench runs on, those of frappe/build at
# FRAPPE_VERSION, installed next to the ones frappe/bench ships and made the
# default. Pinned to the patch release, so a daily rebuild of latest never
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
# Node 24 or later. Pinned, and checked by npm against the registry's
# integrity hash.
ARG FRAPPE_PYTHON
ARG FRAPPE_NODE
ARG AST_GREP_VERSION=0.45.3
ARG AGENT_BROWSER_VERSION=0.38.1
RUN pyenv install -s "${FRAPPE_PYTHON}" \
    && PYENV_VERSION="${FRAPPE_PYTHON}" pip install --no-cache-dir virtualenv \
    "ast-grep-cli==${AST_GREP_VERSION}" \
    && pyenv global "${FRAPPE_PYTHON}" "${PYTHON_VERSION_PREV}" \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${FRAPPE_NODE}" \
    && npm install -g yarn "agent-browser@${AGENT_BROWSER_VERSION}" \
    && nvm alias default "${FRAPPE_NODE}" \
    && nvm use default \
    && rm -rf "${NVM_DIR}/.cache" \
    && pyenv rehash

# Two Python CLIs, each in a virtualenv of its own so neither one's
# dependencies reach the interpreter above, and linked into ~/.local/bin,
# which frappe/bench puts on PATH. Pinned like ast-grep.
#   frappectl             a client for live Frappe sites, v16 and later. With
#                         no keyring in a container it reads FRAPPE_SITE,
#                         FRAPPE_API_KEY and FRAPPE_API_SECRET
#   pretty-release-notes  release notes written from a GitHub repository's
#                         pull requests by an LLM. GitHub only
ARG FRAPPECTL_VERSION=0.19.0
ARG PRETTY_RELEASE_NOTES_VERSION=1.4.1
RUN for spec in "frappectl==${FRAPPECTL_VERSION}" \
    "pretty-release-notes==${PRETTY_RELEASE_NOTES_VERSION}"; do \
    tool="${spec%%==*}" \
    && venv="/home/frappe/.local/share/${tool}" \
    && PYENV_VERSION="${FRAPPE_PYTHON}" python -m venv "${venv}" \
    && "${venv}/bin/pip" install --no-cache-dir "${spec}" \
    && mkdir -p /home/frappe/.local/bin \
    && ln -sf "${venv}/bin/${tool}" "/home/frappe/.local/bin/${tool}" \
    || exit 1; \
    done

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
# the fzf it loads is the Debian package installed above.
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.zsh_history" \
    -x

COPY --chown=frappe:frappe zsh/custom.zsh /home/frappe/.zsh-custom.zsh
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
    && printf 'frappe ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh\n' >/etc/sudoers.d/frappe-firewall # betterleaks:allow sudoers rule, no secret
# Its own RUN, since the line above has to end on the allow comment.
RUN chmod 0440 /etc/sudoers.d/frappe-firewall \
    && visudo -c \
    && sudo -l -U frappe | grep -q '/usr/local/bin/init-firewall.sh' \
    && ! sudo -l -U frappe | grep -Eq '(NOPASSWD: *|\) *)ALL$'
USER frappe

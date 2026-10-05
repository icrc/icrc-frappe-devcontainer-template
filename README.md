# icrc-frappe-devcontainer-template

> Under construction: things can change without notice. Contributions go through pull requests, see [CONTRIBUTING.md](CONTRIBUTING.md).

A template for a Frappe dev container: MariaDB, Redis, a mail catcher, an S3 store, Keycloak and a LiteLLM proxy, with the bench and its apps built from a config file you edit. Based on the [frappe_docker devcontainer example](https://github.com/frappe/frappe_docker/tree/main/devcontainer-example), with the differences listed at the end.

It is made for working with an AI coding agent, [Claude Code](https://docs.anthropic.com/en/docs/claude-code), installed in the container, so the agent runs there rather than on your machine. A default-deny egress firewall decides which hosts the agent, and everything else in the container, can reach, and the agent cannot change it. [Claude Code and egress control](#claude-code-and-egress-control) says what that covers and what it does not.

## Quick start

1. Install Docker (or Podman) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers). Create your repository with **Use this template** on GitHub, then open it and **Reopen in Container**. Passwords are generated on first start, so there is nothing to copy or fill in. [Using this template](#using-this-template) lists what to adapt.
2. In the container terminal:

```bash
cd /workspace/development
./install-bench.sh          # bench + the apps in apps.json, a few minutes
./create-site.sh            # dev.localhost, every app installed
./start.sh                  # http://localhost:8000
```

`create-site.sh` prints the Administrator password. Recover it later with `bash .devcontainer/init-env.sh --print`.

| Service | Where |
|---|---|
| Frappe | http://localhost:8000 |
| Realtime | http://localhost:9000 |
| Mail catcher | http://localhost:8025 |
| S3 API | http://localhost:9100, `http://seaweedfs:8333` from inside |
| MariaDB | `localhost:3306`, host `mariadb` from inside |
| Keycloak | http://localhost:8080, `http://keycloak:8080` from inside. Admin `admin`, realm `frappe` with client `frappe` and user `dev` |
| LiteLLM | http://localhost:4000, `http://litellm:4000` from inside. OpenAI-compatible, key `LITELLM_MASTER_KEY` |

## Using this template

**Use this template** on GitHub gives your repository a copy of the files without this one's history. It works as it is, with a bench of Frappe alone; what makes it yours:

| Where | What |
|---|---|
| `development/apps.json` | Your apps. It ships empty; `apps-example.json` has entries to copy, and [Choosing the apps](#choosing-the-apps) the rest |
| `PROJECT_NAME` in `.devcontainer/.env` | The Compose project and the prefix of every volume, so two projects made from this template on one machine never share a database. Written on first start from your repository's name (`icrc-frappe-template` for this one), unless you choose it, see below |
| `FRAPPE_VERSION`, `FRAPPE_PYTHON`, `FRAPPE_NODE` in `.devcontainer/.env` | The release your production image runs, see [Frappe versions](#frappe-versions) |
| `NO_PROXY` and `no_proxy` in `.devcontainer/docker-compose.yml` | Your internal domains, if you work behind a proxy |
| `.devcontainer/egress-allowlist` | The public hosts your apps reach that the list does not open yet |
| `"name"` in `.devcontainer/devcontainer.json` | What the editor shows for the container |
| `.github/CODEOWNERS` | Your team, in place of this repository's |
| `README.md` | Your title and introduction. The rest describes the container and stays true |

Every generated file, `.env` among them, is git-ignored, so none of it reaches your repository.

To choose the project name, export it in the host shell before the first **Reopen in Container**, as you would the proxy, or run `init-env.sh` once on the host:

```bash
export PROJECT_NAME=acme-crm
bash .devcontainer/init-env.sh --project-name acme-crm   # the same, without the export
```

Lower case, digits, `-` and `_`. It is written into `.env` once and read from there on every start. A `PROJECT_NAME` in the shell that contradicts `.env` stops the start with an error, because Compose would take the shell's and open another project's volumes. To rename, edit `.env`; the stack then starts on new, empty volumes and the old ones stay behind.

## On the host

The container is the same on every OS. What runs before it is created, `.devcontainer/init-env.sh`, is a bash script that reads `$HOME`, and a proxy has to be set where the container is opened from.

### Windows

Keep the repository inside WSL2 and **Reopen in Container** from there, which is Microsoft's own Dev Containers workflow. Otherwise install [Git for Windows](https://git-scm.com/download/win) with `bash` on `PATH`, which also sets `HOME`. Without either, `init-env.sh` stops and says so.

### Behind a proxy

Export the proxy in the host shell before opening the container:

```bash
export HTTP_PROXY=http://proxy.example.org:8080
export HTTPS_PROXY=http://proxy.example.org:8080
```

Compose passes them to the `frappe` and `litellm` containers, whose `NO_PROXY` is hardcoded to its own service names, so the bench reaches MariaDB, Keycloak or LiteLLM directly. The host's `NO_PROXY` is not copied: a launcher may set it to `*` so that devpod goes direct, which would send every request in the container past the proxy. A project made from this template adds its internal domains to `NO_PROXY` and `no_proxy` in `.devcontainer/docker-compose.yml`. An editor started from a desktop menu may not see the shell's variables; the same two lines, without `export`, in `.devcontainer/.env` are read as a fallback. The image build takes the proxy from the `build.args` of `devcontainer.json`, and never from Compose: rootless Podman runs the build's steps on the host's network, where a container-only address such as `host.containers.internal` has no route.

Pulling the base images goes through the Docker daemon, which has its own proxy setting: Docker Desktop's *Resources, Proxies*, or the daemon's `proxies` in `/etc/docker/daemon.json`.

With no proxy, set nothing: every value is empty and every tool connects directly.

## Claude Code and egress control

Claude Code is installed when the container is created and runs as the `frappe` user, like the bench. What it can use is what the container holds:

- the repository, mounted at `/workspace`, and the bench and app checkouts under it;
- the host's `~/.claude`, so the login and settings are the ones you have on the host. Plugins are the exception: a volume of this project's own, which `.devcontainer/install-plugins.sh` fills on every start from the marketplaces and plugins your settings declare;
- the credentials the container is given for git: the forwarded ssh agent, the `gh` token in the mounted `~/.config/gh`, and the copies of `~/.gitconfig` and `~/.npmrc`. Wherever those authenticate, the agent can authenticate too. No private ssh key and no other host file enters the container.

What it can reach on the network is decided by the firewall below, and not by the agent. Root applies the rules on every start. The `frappe` user's sudo is cut down to the one script that applies them, so neither the agent nor any other process in the container can flush them. That script reads the proxy and `EGRESS_ALLOW` from the environment the container was started with, never from its caller's, so an agent cannot open a host by setting a variable first. A host the agent needs and the list lacks is a change to a tracked file, `egress-allowlist`, which goes through review, or a decision you take on the host with `EGRESS_ALLOW`.

The firewall limits where traffic goes, not what is sent there. It does not cover:

- **What an allowed host accepts.** GitHub's ranges, PyPI and npm are open for anything, so an agent can push, open a gist or publish a package wherever the credentials above allow. Keep the `gh` token and the registry tokens scoped to what the work needs.
- **DNS.** Port 53 is open to any resolver, which is a channel out for a small amount of data.
- **The proxy.** When one is set it is opened, and what it lets through is its own policy, not this list.
- **What the agent does inside.** It can change any file in the repository and the bench, and run anything the `frappe` user can. Review its changes as you would anyone's; the signed commits and the secret scan below apply to them too.

### Egress firewall

Every start applies a default-deny outbound firewall, `.devcontainer/init-firewall.sh`. It opens the Compose network, GitHub, PyPI, npm and yarn, Claude Code and the VS Code marketplace, which `.devcontainer/egress-allowlist` lists, and the proxy when one is set. It works with a proxy and without one. `init-firewall.sh --help` has the detail.

An internal host, such as a registry named in `~/.npmrc`, is opened with `EGRESS_ALLOW` on the host, set as the proxy is and never in a tracked file:

```bash
export EGRESS_ALLOW=git.example.org,registry.example.org:8443
```

A public host the whole team needs goes in `egress-allowlist`, and takes a rebuild. Names are resolved once, at start, so if a host behind a CDN stops answering after a while, run `sudo /usr/local/bin/init-firewall.sh` again.

`./net-check.sh` checks it all in a few seconds: the proxy, the Compose services, a few allowed hosts, and that anything else is still blocked.

## Agent skills and tools

**Skills.** `development/skills.json` pins each skill repository to a commit, and `get-skills.sh` copies its skills into `.claude/skills` at the repository root on every start, where Claude Code finds them from `development/`. That folder is git-ignored: a skill is installed, never committed, so a repository without a licence can be used but is never shipped. Pinned today:

- [frappe/skills](https://github.com/frappe/skills): Frappe best practices for DocTypes, controllers, APIs, tests and the bench CLI. It has no licence yet. `/deep-app-audit` and `/draft-security-advisory` run only when called.
- [agent-browser](https://github.com/vercel-labs/agent-browser)'s skill, which teaches the agent the tool below.

To move a pin, set its `ref` to a newer commit sha and run `./get-skills.sh`.

**AGENTS.md.** `get-apps.sh` writes one at the bench root, saying what a bench is, and `new-app.sh` writes one into each new app from `development/templates/app-AGENTS.md`. Both end with the [ponytail-lite](https://github.com/ilindaniel/ponytail-lite) rules: the smallest change that works. An existing file is never overwritten, so an app's AGENTS.md is the project's to edit.

**Tools**, in the image:

| Tool | For | Set up |
|---|---|---|
| `gh` | GitHub from the command line | `./gh-login.sh`, once per host |
| `agent-browser` | Browser automation, to test a UI flow | Drives the image's Chromium, through `AGENT_BROWSER_EXECUTABLE_PATH` |
| `frappectl` | Listing, reading and changing documents on a live Frappe site, v16 and later | `FRAPPE_SITE`, `FRAPPE_API_KEY` and `FRAPPE_API_SECRET` exported in the shell, from an API key of a site user: there is no keyring in a container. The agent can do whatever that user can, so give it the roles the work needs |
| `pretty-release-notes` | Readable release notes from a GitHub repository's pull requests. GitHub only | `pretty-release-notes setup` writes `~/.pretty-release-notes/config.toml`, with a GitHub token and an LLM key, and a rebuild loses it. An `anthropic:` model reaches a host the firewall already opens; another provider needs its host in `EGRESS_ALLOW` |

## Frappe versions

Three pins in `.devcontainer/.env`, written once by `init-env.sh`:

- `FRAPPE_VERSION` (`v16.35.0`), the exact Frappe release `install-bench.sh` installs. Set it to the release your production image uses. Avoid a floating tag such as `v16`, which resolves to the newest v16 at install time.
- `FRAPPE_PYTHON` (`3.14.7`) and `FRAPPE_NODE` (`24.21.0`), the Python and Node [frappe/build](https://hub.docker.com/r/frappe/build/tags) carries at that tag, so the bench runs on the production toolchain. Read them with `docker run --rm --entrypoint sh frappe/build:v16.35.0 -c 'python --version; node --version'`.

The container is [frappe/bench](https://hub.docker.com/r/frappe/bench/tags)`:latest`, which Frappe rebuilds daily, so a rebuild brings the newest tooling and an app meets a dependency upgrade here before production does. The Dockerfile installs the pinned Python and Node with its pyenv and nvm and makes them the default, so a rebuild never moves the interpreter the bench runs on. The Python and Node frappe/bench ships stay installed next to them.

After changing `FRAPPE_PYTHON`, rebuild the container and recreate the bench's virtualenv on it: `cd frappe-bench && bench migrate-env python3.14`.

### Moving to another release on the same line

```bash
./switch-version.sh frappe v16.36.0   # checks out, migrates every site, rewrites FRAPPE_VERSION
```

If frappe/build at the new tag has another Python or Node, set `FRAPPE_PYTHON` and `FRAPPE_NODE` to match and rebuild.

### Testing the next major line

Do it on a second bench next to the first, so the current one stays usable. Every script takes the bench from `BENCH_NAME`, default `frappe-bench`, and `BENCH_PYTHON` picks the Python `install-bench.sh` creates it on.

```bash
BENCH_NAME=frappe-bench-v17 ./install-bench.sh version-17
```

If `frappe/build:version-17` has another Python or Node than the pins, add them for that bench first, until the next rebuild: `pyenv install 3.X.Y`, `nvm install N && nvm use N`, and `BENCH_PYTHON="$(pyenv root)/versions/3.X.Y/bin/python"`. Restore a backup into a site on the new bench, then run `BENCH_NAME=frappe-bench-v17 ./migrate-site.sh`. To move for good, set the three pins to the v17 release, rebuild, and `bench migrate-env` the bench.

### A bench on the previous major line

frappe/bench also ships the previous Python and Node (3.12 and 22 today):

```bash
nvm use 22
BENCH_NAME=frappe-bench-v15 BENCH_PYTHON=python3.12 ./install-bench.sh version-15
```

Only one bench can serve on port 8000 at a time: `./stop-bench.sh` one before `./start.sh` on the other.

### Checking a bench against a production image

`bench version -f table` lists each app with its version, branch and commit. In a production image only the version is left, because the image build removes every `.git`. The version comes from `__version__` in the app, so it tells two builds apart only when the app bumps it on every release. An app followed at a branch head, such as frappe/telephony at `0.0.1`, reads the same in every build.

The fix belongs in the production image build, not here: stamp the commit into `__version__` before installing the app, as a PEP 440 local label, `0.0.1+g0123abc`. The `-` form (`0.0.1-0123abc`) is not valid PEP 440 and flit, the build backend Frappe apps use, refuses it. Parity is then the version in the image against the version and commit `bench version` shows here.

## Choosing the apps

`development/apps.json` is the list, in the shape `bench` itself uses. The template ships it empty, so the bench holds Frappe alone until you add an entry:

```json
[
  { "url": "https://github.com/frappe/erpnext.git", "branch": "version-16" }
]
```

Add an entry, run `./get-apps.sh`, and only the new app is fetched. `apps-example.json` holds a longer list to copy from.

bench clones one commit deep, which is all a dependency needs. For an app you develop on, add `"history": true` to its entry and the full history is fetched right after the clone, so `git log`, `blame` and a rebase work in `frappe-bench/apps/<name>`. That checkout is a normal git repository on the declared branch: work from there, and `repo-status.sh` shows where each one stands.

To start a new app in a repository that already exists, with at least a first commit:

```bash
./new-app.sh my_app https://github.com/your-org/my_app.git          # commit only
./new-app.sh --push my_app https://tfs.example.org/Coll/Proj/_git/my_app
```

It runs `bench new-app --no-git`, puts the scaffold on `feat/init-my_app` cut from the remote's default branch, keeps any file the repository has that the scaffold does not, and asks before replacing one both have. The result is one commit to merge through a pull request. Then declare the app in `apps.json`, or `apps.local.json` for an internal host.

Nothing in this repository authenticates to a git host, which is what lets the same file reach any of them:

```jsonc
// public, over https
{ "url": "https://github.com/frappe/helpdesk.git", "branch": "v1.22.1" }

// private, over ssh, using the agent your editor forwards in
{ "url": "git@github.com:your-org/your_app.git", "branch": "main" }

// an on-premises Azure DevOps collection, using the credentials already in
// the ~/.gitconfig mounted from your host
{ "url": "https://tfs.example.org/YourCollection/Your%20Project/_git/your_app",
  "branch": "main" }
```

A private repository on a public host can go in `apps.json`, provided everyone using this repository can reach it (a clone that fails stops `install-bench.sh`). Keep in `development/apps.local.json`, which `get-apps.sh` reads too and git ignores, what must not be published: an internal host such as an on-premises Azure DevOps, and your personal additions. It is read first, so an entry there for an app `apps.json` also declares, by the same repository name, replaces the shared one: that is how you take an app from your fork or another branch without touching the team's list. Both files matter only when an app is first fetched; `switch-version.sh` moves one already in the bench.

## The scripts

All in `development/`, all with `--help`, all aliased in the shell.

| Script | Alias | Does |
|---|---|---|
| `install-bench.sh` | | Create the bench and install the apps. Run once |
| `get-apps.sh` | `frapps` | Install any app in `apps.json` not yet in the bench, and the pre-commit hooks of every app declared there |
| `new-app.sh` | `frnewapp` | Scaffold an app with `bench new-app` on a feature branch of an existing repository |
| `create-site.sh` | | Create a site and install apps into it |
| `delete-site.sh` | | Drop a site, its database and its files |
| `start.sh` | `frstart` | Run the development server |
| `stop-bench.sh` | `frstop` | Kill every bench process and free the ports |
| `migrate-site.sh` | `frmigrate` | Apply schema changes. Needed after any DocType edit |
| `build.sh` / `watch.sh` | `frbuild` / `frwatch` | Build assets once, or on change |
| `clear-cache.sh` | `frcache` | Clear the cache when the browser shows an old build |
| `console.sh` / `db-console.sh` | `frconsole` / `frdb` | A Python console, or a database shell |
| `switch-version.sh` | `frswitch` | Move an app, frappe included, to another tag or branch and migrate every site |
| `s3-create-buckets.sh`, `s3-list-buckets.sh`, `s3-list-files.sh` | | The local object store |
| `repo-status.sh` | `frstatus`, `git repo-status` | The git state of every app checkout, in one table |
| `pr-sync.sh` | `git pr-sync` | Return an app to its default branch once its PR is merged |
| `gh-login.sh` | | Authenticate `gh`, once per host, with the device flow |
| `get-skills.sh` | | Install the agent skills `skills.json` pins. Runs on every start |

Navigation: `godev`, `gobench`, `goapps`, `gosites`. Log tail: `logs`.

The two git ones are git subcommands as well, completed by `git <TAB>`, so neither has to be remembered as a file name. Under that form the help is `-h`: git answers `--help` with a man page before the script runs.

## Adding a tool

A tool goes in the apt list in `.devcontainer/Dockerfile`, and arrives with the next rebuild. There is no `sudo apt-get` in the container: the `frappe` user's sudo is cut down to the firewall script, so that nothing in the container can take the firewall down.

## Secrets

`.devcontainer/init-env.sh` runs before the container starts and writes `.devcontainer/.env` with a random 32-character value per secret: the database root password, the Frappe Administrator password, the object store keys, the Keycloak admin and test-user password, the Keycloak client secret and the LiteLLM master key. The file is git-ignored, it is never regenerated behind your back, and no default password exists anywhere in this repository.

The model-provider keys LiteLLM needs (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, the `AZURE_*` three) are yours: `init-env.sh` leaves them empty in `.env`, and `litellm-config.yaml` says which model uses which. Fill in the ones you use and restart the `litellm` service.

```bash
bash .devcontainer/init-env.sh --print   # show the current values
bash .devcontainer/init-env.sh --force   # rotate them
```

Rotating invalidates the database the old password created. `init-env.sh --help` has the rest.

### Secret scanning

[betterleaks](https://github.com/betterleaks/betterleaks), the successor to gitleaks by the same author, checks every commit twice. In the container, a pre-commit hook scans what is staged and refuses the commit on a finding. On GitHub, the `betterleaks` workflow scans the commits a pull request adds, so a commit made with `--no-verify` or outside the container is still caught. Both cover this repository only, not the app checkouts under `frappe-bench/apps/`. An app that ships its own `.pre-commit-config.yaml`, with betterleaks in it or not, gets those hooks installed by `get-apps.sh`, which also wires them into an app cloned before.

The hook is installed when the container is created. In a container created before it existed, run `pre-commit install` once. A false positive is silenced with a `betterleaks:allow` comment on the line, which a reviewer then sees; `gitleaks:allow` is still honoured. A false positive already committed, which no comment can reach, is listed by fingerprint in `.betterleaksignore`.

The workflow blocks a merge only once `betterleaks` is a required status check in the branch ruleset of `main`.

## Git and GitHub

- **git** uses the ssh key from your host's agent, which the editor forwards into the container. No private key is copied in and only the public `allowed_signers` list reaches `~/.ssh`, so clone, pull and push over ssh (to GitHub or any other host) work as they do on your machine. The only prerequisite is on the host: an agent running with your key loaded (`ssh-add`) before you reopen in the container.
- **gh** uses its own OAuth token, because an ssh key cannot authenticate an API call. Run `./gh-login.sh` once and approve the code in a browser; the token lands in the host's mounted `~/.config/gh`, so it survives every rebuild.
- **git config** is the host's `~/.gitconfig`, copied into `.devcontainer/` by `init-env.sh` on every start and included by the container's own `~/.gitconfig`. A change made on the host arrives at the next start. `git config --global` inside the container writes the container's file and never touches the host's. The copy is git-ignored, and can hold whatever credential your host config holds.
- **npm config** is the host's `~/.npmrc`, copied the same way and mounted read-only as the container's `~/.npmrc`, so a private registry and its token work for npm and yarn in the bench. Any `prefix` line is left out, since nvm refuses to run under one. Change it on the host; it arrives at the next start. With no host `~/.npmrc`, npm uses the public registry.

An app cloned over https, like every entry in `apps-example.json`, can still push over ssh with one line in your host `~/.gitconfig`:

```bash
git config --global url."git@github.com:".pushInsteadOf "https://github.com/"
```

Check with `ssh -T git@github.com` and `gh auth status`. If ssh fails, confirm the agent arrived: `SSH_AUTH_SOCK` must be set and `ssh-add -L` must list your key.

## Commits must be signed

Every commit here carries a verified signature. An unsigned commit is rejected at review, because a signature ties a change to a person rather than to a `user.email` string anyone can set.

We sign with SSH, so the key you push with is the key you sign with.

```bash
ssh-keygen -t ed25519 -a 100 -C "you@yourmail.com"      # if you have no key
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
```

Then add the **public** key at [Settings, SSH and GPG keys](https://github.com/settings/keys) **twice**: once as an *Authentication Key*, once as a *Signing Key*. They are separate entries, and only the second produces the Verified badge.

In a dev container, forward the agent rather than mounting `~/.ssh`, and point at the key itself so no file is needed:

```bash
git config user.signingkey "key::$(ssh-add -L | head -1)"
```

To check signatures locally, as `git log --show-signature` does, git needs the list of keys you trust. On the host:

```bash
echo "you@yourmail.com $(cat ~/.ssh/id_ed25519.pub)" >>~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile '~/.ssh/allowed_signers'
```

Keep the single quotes: git expands the `~` on each machine, so the same setting finds the file on the host and in the container, where `init-env.sh` copies it on every start. It changes nothing about signing or about GitHub's Verified badge, only what a local check reports.

### Documentation

- [About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [Telling Git about your signing key](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key#telling-git-about-your-ssh-key)
- [Adding a new SSH key to your GitHub account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)

## herdr (optional)

[herdr](https://herdr.dev) shows whether the agent in each pane is working or waiting by watching the pane, which needs nothing from the container. Its Claude Code hook also reports the session id to herdr over a control socket, which the container reaches through the host's `~/.config/herdr`, mounted at `~/.herdr-host`.

To opt in, run `herdr integration install claude` on the host, then enter the container from a herdr pane with:

```bash
devpod ssh <workspace> \
  --set-env HERDR_ENV=1 \
  --set-env HERDR_SOCKET_PATH=/home/frappe/.herdr-host/herdr.sock \
  --set-env HERDR_PANE_ID="$HERDR_PANE_ID"
```

Without those variables the hook exits and nothing changes. `herdr integration install` writes the hook's absolute host path into `~/.claude/settings.json`, which does not exist in the container: change it to `bash "$HOME/.claude/hooks/herdr-agent-state.sh" session`, and again after a herdr update.

Linux hosts only: a unix socket does not cross the VM of Docker Desktop on macOS or Windows.

## Divergence from upstream

Kept from [frappe_docker](https://github.com/frappe/frappe_docker/tree/main/devcontainer-example): the Compose-backed container, the `frappe` service and user, the workspace mounted with the bench one level inside it, and the port ranges.

| | Upstream | Here |
|---|---|---|
| Distribution | A folder inside frappe_docker, copied by hand | A GitHub template repository; `PROJECT_NAME` keeps each copy's containers and volumes apart |
| Image | `frappe/bench:latest`, used as is | `frappe/bench:latest` too, plus GitHub's host keys, zsh, `micro`, `gh`, `lazygit`, `jq`, `bat`, `fzf`, `rg`, `fd`, `tree`, `ast-grep`, `chromium`, `agent-browser`, `frappectl`, `pretty-release-notes`. Every other image pinned to a release |
| Passwords | `123`, hardcoded in three places | Generated per install into `.env` |
| Apps | `installer.py`, honoured only at `bench init` | `apps.json` + `get-apps.sh`, which works on an existing bench |
| Site | `installer.py` | `create-site.sh`, with an explicit app list |
| Bench lifecycle | Nothing | The table above |
| Services | MariaDB, Redis. Mailpit and Postgres commented out | MariaDB, Redis, Mailpit, S3, Keycloak with a dev realm imported, LiteLLM. Postgres dropped |
| Credentials | Host `~/.ssh` bind-mounted | Host `~/.gitconfig`, `~/.ssh/allowed_signers` and `~/.npmrc` copied in on every start, `~/.config/gh` mounted, ssh through the forwarded agent |
| Proxy | Nothing | Host `HTTP_PROXY` and `HTTPS_PROXY` passed to the containers, `NO_PROXY` hardcoded to the services, empty when unset; the build's proxy comes from `devcontainer.json` |
| Egress | Open, and the `frappe` user has full sudo | Default-deny firewall at every start, with or without a proxy; sudo cut down to the firewall script |
| Windows | Nothing | `init-env.sh` runs under WSL2 or Git Bash, and no host file is mounted by an absolute path |
| Repository work | Nothing | `gh`, `repo-status.sh`, `pr-sync.sh` |
| Claude Code | Nothing | Installed, with the host `~/.claude` shared, and behind the egress firewall. Skills pinned in `skills.json`, and an AGENTS.md written into the bench and each new app |

## Licence

Copyright (c) 2026 International Committee of the Red Cross (ICRC), portions Copyright (c) 2017 Frappe Technologies Pvt. Ltd.

BSD 3-Clause License. See [LICENSE](LICENSE). A project made from this template may license its copy as it chooses, provided it keeps both notices.

Portions derived from [frappe_docker](https://github.com/frappe/frappe_docker), Copyright (c) 2017 Frappe Technologies Pvt. Ltd., under the MIT licence. See [LICENSES/MIT-frappe_docker.txt](LICENSES/MIT-frappe_docker.txt).

`development/templates/ponytail-lite.md` is [ponytail-lite](https://github.com/ilindaniel/ponytail-lite), Copyright (c) 2026 DietrichGebert and Daniel Ilin, under the MIT licence. See [LICENSES/MIT-ponytail-lite.txt](LICENSES/MIT-ponytail-lite.txt). Every AGENTS.md written from it carries that notice.

# Frappe Prot dev container

The Frappe development container of the ICRC Digital Protection Program: MariaDB, Redis, a mail catcher, an S3 store, Keycloak and a LiteLLM proxy, with the bench and the Prot apps built from a config file. Made from [icrc-frappe-devcontainer-template](https://github.com/icrc/icrc-frappe-devcontainer-template), itself based on the [frappe_docker devcontainer example](https://github.com/frappe/frappe_docker/tree/main/devcontainer-example), with the differences listed at the end.

It is made for working with an AI coding agent, [Claude Code](https://docs.anthropic.com/en/docs/claude-code), installed in the container, so the agent runs there rather than on your machine. A default-deny egress firewall decides which hosts the agent, and everything else in the container, can reach, and the agent cannot change it. [Claude Code and egress control](#claude-code-and-egress-control) says what that covers and what it does not.

## Quick start

1. Install Docker (or Podman) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers), or IntelliJ with its dev container support.
2. Give git access to Azure DevOps, once per machine, as [Azure DevOps access](#azure-devops-access) shows: `frappe_prot_ucm_icrc` is cloned from there.
3. Clone this repository, open it and **Reopen in Container**. Passwords are generated on first start, so there is nothing to copy or fill in.
4. In the container terminal:

```bash
cd /workspace/development
./gh-login.sh               # once per machine, see GitHub access
./install-bench.sh          # bench + the Prot apps of apps.json, a few minutes
./create-site.sh            # dev.localhost, every app installed, developer mode on
./start.sh                  # http://localhost:8000
```

The apps are those the Prot application image is built from, Frappe Insights aside for now, so the bench is ready to work on: `frappe_prot_ucm_core` and `frappe_prot_ucm_icrc` are full checkouts on `develop`, in `frappe-bench/apps/`. `create-site.sh` prints the Administrator password. Recover it later with `bash .devcontainer/init-env.sh --print`.

| Service | Where |
|---|---|
| Frappe | http://localhost:8000 |
| Realtime | http://localhost:9000 |
| Mail catcher | http://localhost:8025 |
| S3 API | http://localhost:9100, `http://seaweedfs:8333` from inside |
| MariaDB | `localhost:3306`, host `mariadb` from inside |
| Keycloak | http://localhost:8080, `http://keycloak:8080` from inside. Admin `admin`, realm `frappe` with client `frappe` and user `dev` |
| LiteLLM | http://localhost:4000, `http://litellm:4000` from inside. OpenAI-compatible, key `LITELLM_MASTER_KEY` |

## Azure DevOps access

git authenticates to Azure DevOps with a Personal Access Token kept in your system's credential store, never in a file. The editor forwards your host's credential helper into the container, so git there gets the token when it needs it, and the token is never written into the container or the repository folder. Set it up once, on the host:

Create a Personal Access Token with the **Code (Read & Write)** scope only, and the shortest expiry you can work with.

Give git a credential helper backed by the system's store, if it has none. Git for Windows installs Git Credential Manager as the default. On macOS, use `git config --global credential.helper osxkeychain`. On Ubuntu or Debian, build the libsecret helper git ships, then use it. Never use the `store` helper, which writes the token in cleartext to `~/.git-credentials`.

```bash
sudo apt install libsecret-1-0 libsecret-1-dev
sudo make --directory=/usr/share/doc/git/contrib/credential/libsecret
git config --global credential.helper \
  /usr/share/doc/git/contrib/credential/libsecret/git-credential-libsecret
```

Send the user agent the ICRC F5 BIG-IP APM gateway expects. Without it, the gateway redirects git to `/my.policy`, and git fails with `Recv failure: Connection reset by peer` or an unexpected HTML response.

```bash
git config --global 'http.https://tfs.ext.icrc.org.userAgent' choco
```

Store the token by reaching Azure DevOps once from the host, giving any username and the token as the password.

```bash
git ls-remote https://tfs.ext.icrc.org/ICRCCollection/Digital%20Protection%20Program/_git/frappe-prot-devcontainer HEAD
```

When the token expires, git asks again on the next request, and the helper stores the new one.

The token is reachable only through an attached editor. The Azure DevOps marketplaces are therefore skipped at container start: run `bash /workspace/.devcontainer/install-plugins.sh` from a terminal once attached. A shell opened with `docker exec` cannot reach Azure DevOps at all. While an editor is attached, any process in the container, the agent included, can ask the helper for the token, which is why its scope and expiry are what limit it.

**Fallback, only when no credential helper can be used**, for instance on a Windows machine where Git Credential Manager is not installed and cannot be, or with an editor that does not forward the helper: the token can go into `~/.gitconfig` as an `extraheader`, from which git sends it on every request without asking.

```bash
git config --global 'http.https://tfs.ext.icrc.org.extraheader' \
  "AUTHORIZATION: basic $(printf 'PAT:%s' '<your-personal-access-token>' | base64 -w0)"
```

`-w0` keeps the value on one line, since a wrapped one is an invalid header; on macOS, drop it. To rotate the token, run the command again. Base64 is not encryption: the token is in cleartext in `~/.gitconfig`, `init-env.sh` copies it into `.devcontainer/.gitconfig.host`, and every process in the container can read it, the agent included, attached editor or not. Keep `~/.gitconfig` readable only by you (`chmod 600 ~/.gitconfig`), give the token the shortest expiry you can, and move to a credential helper as soon as one is available: revoke the token, then `git config --global --unset 'http.https://tfs.ext.icrc.org.extraheader'`.

`tfs.ext.icrc.org` and Nexus, `repository.ext.icrc.org`, are opened by `egress-allowlist` and sent past the proxy by `NO_PROXY_DOMAINS` in `.devcontainer/project.env`, so nothing more is needed in the container.

## GitHub access

`frappe_prot_ucm_core` is a private repository on GitHub, so `install-bench.sh` fails until git can reach GitHub. In the container, git reaches GitHub over https with the token of the GitHub CLI, `gh`. The host's own gh login and git credentials are not used, and nothing needs installing on the host. Log in once, from the container terminal, before `install-bench.sh`:

```bash
cd /workspace/development
./gh-login.sh
```

It prints a one-time code and `https://github.com/login/device`. Open that URL in a browser on the host, enter the code and authorize the GitHub CLI, for the `icrc` organization too if GitHub asks. Then check:

```bash
gh auth status
git ls-remote https://github.com/icrc/frappe_prot_ucm_core.git HEAD
```

The token is written to `hosts.yml` in the host's `~/.config/gh`, which is mounted into the container, so the login survives every rebuild. The token is in cleartext in that file, and any process in the container can read it, the agent included. To revoke it, go to GitHub's *Settings, Applications, Authorized OAuth Apps*, and revoke *GitHub CLI*.

Where that folder is on the host:

| Host | Folder | A gh login made on the host |
|---|---|---|
| Linux | `~/.config/gh` | Is in the same folder, but gh keeps the token in the system keyring when it can, where the container cannot read it. Run `gh-login.sh` anyway |
| Windows, WSL2 | `~/.config/gh` in the WSL distribution | Made with gh for Windows, is in `%AppData%\GitHub CLI` and is not seen |
| Windows, Git Bash | `%USERPROFILE%\.config\gh` | Same as above |

If the check fails:

- git asks for a username or a password: gh is not logged in. Run `./gh-login.sh`.
- `Repository not found` while `gh auth status` is fine: your GitHub account has no access to `icrc/frappe_prot_ucm_core`, or the `icrc` organization has not approved the GitHub CLI for your token. Ask an owner of the organization.
- `ssh: connect to host github.com port 22`: a rule in the host `~/.gitconfig` sends GitHub back to ssh. See [Git](#git).

**Commit signing, optional.** git signs with the ssh key of your host's agent, which the editor forwards. GitHub access does not need it. The agent must run, with your key loaded, before you reopen in the container:

- Linux: most desktops start an agent. Load the key with `ssh-add`.
- Windows, WSL2: the editor forwards the agent of the WSL distribution. Start one from `~/.bash_profile`, as the [VS Code documentation](https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials) shows, and load the key with `ssh-add`.
- Windows, Git Bash: the editor forwards the Windows OpenSSH agent, not the Git Bash one. That service is disabled by default. Enable it once, from a PowerShell run as administrator, then load the key from a normal PowerShell:

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

```powershell
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

## Using the template

In sync with the template at commit `bf7f407`. What differs from it is Prot's, and `.template-sync` lists every such file:

| Where | What |
|---|---|
| `development/apps.json` | The Prot apps |
| `.devcontainer/project.env`, which the template does not have | The release of the Prot image and its toolchain, and `.icrc.org` past the proxy |
| `.devcontainer/egress-allowlist` | The ICRC hosts |
| `azure-pipelines.yml` | The Azure DevOps gates, in place of the template's GitHub workflows and Dependabot. `.pre-commit-config.yaml` is the template's, and the lint job runs it |
| `README.md`, `PROJECT.md` | This project's. `AGENTS.md` is the template's and imports `PROJECT.md`, and there is no `CLAUDE.md`, so Claude Code reads `AGENTS.md` itself |

To bring a later template change here, run `template-sync.sh`, which prints the diff of every file that differs from the template on GitHub, take what applies, and move the commit above. With `--quiet` it prints the report only. The script exits 0 once every shared file not listed in `.template-sync` is identical to the template's.

The Compose project is named from the repository, `frappe-prot-devcontainer`, so its volumes are new: a bench and a database from the earlier layout of this repository are not reused. Remove the old `development/frappe-bench` and run `install-bench.sh`, which asks before removing it.

## On the host

The container is the same on every OS. What runs before it is created, `.devcontainer/init-env.sh`, is a bash script that reads `$HOME`, and a proxy has to be set where the container is opened from.

### Windows

Keep the repository inside WSL2 and **Reopen in Container** from there, which is Microsoft's own Dev Containers workflow. Otherwise install [Git for Windows](https://git-scm.com/download/win) with `bash` on `PATH`, which also sets `HOME`. Without either, `init-env.sh` stops and says so.

`init-env.sh` writes the home folder bash sees into `.devcontainer/.env` as `HOST_HOME`, in the form Docker takes, `C:/Users/you` from Git Bash, and the container mounts `~/.config/gh` and `~/.claude` from there. How the editor was started does not matter. A WSL2 checkout uses the home folder of the distribution, and a Windows one `%USERPROFILE%`, so a `gh` login or a Claude Code login made in one is not seen from the other.

### Behind a proxy

Export the proxy in the host shell before opening the container:

```bash
export HTTP_PROXY=http://proxy.example.org:8080
export HTTPS_PROXY=http://proxy.example.org:8080
```

Compose passes them to the `frappe` and `litellm` containers, whose `NO_PROXY` is hardcoded to its own service names, followed by `.icrc.org` from `NO_PROXY_DOMAINS` in `.devcontainer/project.env`, so the bench reaches MariaDB, Keycloak, LiteLLM or Azure DevOps directly. The host's `NO_PROXY` is not copied: a launcher may set it to `*` so that it goes direct itself, which would send every request in the container past the proxy. An editor started from a desktop menu may not see the shell's variables; the same two lines, without `export`, in `.devcontainer/.env` are read as a fallback. The image build takes the proxy from the `build.args` of `devcontainer.json`, and never from Compose: rootless Podman runs the build's steps on the host's network, where a container-only address such as `host.containers.internal` has no route.

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
- **What the agent does inside.** It can change any file in the repository and the bench, and run anything the `frappe` user can. Review its changes as you would anyone's; the secret scan and the pipeline below apply to them too.

### Claude Code's sandbox

When your organisation's policy requires it, Claude Code runs each Bash command in a sandbox. The sandbox's network carries only web traffic, through a proxy, so a sandboxed command cannot reach MariaDB or Redis: a bench command fails with `Unknown server host 'mariadb'`.

`.devcontainer/claude-settings.json` holds the settings this container adds to yours, and the `claude` alias in `custom.zsh` loads it with `--settings`. They are not in `~/.claude/settings.json`, because that file is the host's and every container shares it. The file:

- runs `bench` outside the sandbox, so that it reaches the database and Redis. Claude Code still asks before each bench command, unless you allow it in your own settings. Only a bare `bench` command matches: a `bench` chained with `cd`, `&&`, `;` or a pipe stays in the sandbox;
- runs `gh` outside the sandbox too, so that it finds your GitHub login in `~/.config/gh`, which the sandbox cannot read. It acts with that login wherever it allows, and Claude Code asks before each `gh` command as for bench;
- lets the sandbox read `~/.bench` and `~/.local/lib`, where bench is installed;
- declares a hook, `claude-bash-guard.sh`, which refuses a `cd` or a `bench` chained with other commands, and tells Claude how to run it instead. A `cd` on its own is let through: it is how a session started outside the bench gets into it.

A script in `development/` is not excluded, so one that reaches the database fails when Claude runs it. For `migrate-site.sh`, which only runs `bench migrate`, Claude runs the bench command itself. Run the others yourself, with `!` in Claude Code. A session that is not started from the container's shell, such as one from an IDE extension, does not load the file.

### Egress firewall

Every start applies a default-deny outbound firewall, `.devcontainer/init-firewall.sh`. It opens the Compose network, GitHub, Azure DevOps and Nexus, PyPI, npm and yarn, Claude Code and the VS Code marketplace, which `.devcontainer/egress-allowlist` lists, and the proxy when one is set. It works with a proxy and without one. `init-firewall.sh --help` has the detail.

A host only you need is opened with `EGRESS_ALLOW` on the host, set as the proxy is and never in a tracked file:

```bash
export EGRESS_ALLOW=git.example.org,registry.example.org:8443
```

A host the whole team needs goes in `egress-allowlist`, and takes a rebuild. Names are resolved once, at start, so if a host behind a CDN stops answering after a while, run `sudo /usr/local/bin/init-firewall.sh` again.

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
| `semgrep` | Static analysis, with local rules or a registry ruleset such as `semgrep --config p/python` | Nothing. Metrics are off, so `--config auto`, which needs them, is refused: name the ruleset |

## Frappe versions

Three pins in `.devcontainer/.env`, written once by `init-env.sh` from `.devcontainer/project.env`, which holds the current values:

- `FRAPPE_VERSION`, the exact Frappe release `install-bench.sh` installs, the one the Prot image is built from in `frappe_docker_build`. Avoid a floating tag such as `v16`, which resolves to the newest v16 at install time.
- `FRAPPE_PYTHON` and `FRAPPE_NODE`, the Python and Node [frappe/base](https://hub.docker.com/r/frappe/base/tags) carries at that tag, so the bench runs on the production toolchain. Read them with `docker run --rm --entrypoint sh frappe/base:<FRAPPE_VERSION> -c 'python --version; node --version'`. frappe/build has no tag for every release.

The container is [frappe/bench](https://hub.docker.com/r/frappe/bench/tags) at the release in the Dockerfile's `FROM`, the release the CI of the Prot apps runs their tests on, so a rebuild is the same container; bump both together. Its pyenv must know `FRAPPE_PYTHON`: a release older than that Python fails the build at `pyenv install`. The Dockerfile installs the pinned Python and Node with its pyenv and nvm and makes them the default, so a rebuild never moves the interpreter the bench runs on. The Python and Node frappe/bench ships stay installed next to them.

After changing `FRAPPE_PYTHON`, rebuild the container and recreate the bench's virtualenv on it with `./update-python.sh`. The rebuild removes the Python the virtualenv was made on, so until then every script stops and says so. `update-python.sh` keeps the previous virtualenv in `frappe-bench/archived/envs/` and puts it back if the update fails.

### Moving to another release on the same line

```bash
./switch-version.sh frappe <release>   # checks out, migrates every site, rewrites FRAPPE_VERSION
```

If frappe/base at the new tag has another Python or Node, set `FRAPPE_PYTHON` and `FRAPPE_NODE` to match, rebuild, and run `./update-python.sh`.

### Testing the next major line

Do it on a second bench next to the first, so the current one stays usable. Every script takes the bench from `BENCH_NAME`, default `frappe-bench`, and `BENCH_PYTHON` picks the Python `install-bench.sh` creates it on.

```bash
BENCH_NAME=frappe-bench-v17 ./install-bench.sh version-17
```

If `frappe/build:version-17` has another Python or Node than the pins, add them for that bench first, until the next rebuild: `pyenv install 3.X.Y`, `nvm install N && nvm use N`, and `BENCH_PYTHON="$(pyenv root)/versions/3.X.Y/bin/python"`. Restore a backup into a site on the new bench, then run `BENCH_NAME=frappe-bench-v17 ./migrate-site.sh`. To move for good, set the three pins to the v17 release, rebuild, and run `./update-python.sh`.

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

`development/apps.json` is the list, in the shape `bench` itself uses. It holds the apps of the Prot image, from `apps.json` in `frappe_docker_build`:

| App | From | Branch |
|---|---|---|
| `frappe_prot_ucm_core` | GitHub | `develop`, full history |
| `frappe_prot_ucm_icrc` | Azure DevOps | `develop`, full history |
| `dfp_external_storage` | GitHub | `v1.1.3` |

Frappe Insights, in the image too, is left out for now. To add it, or any app, add an entry and run `./get-apps.sh`, and only the new app is fetched:

```json
{ "url": "https://github.com/frappe/insights.git", "branch": "v3.14.2" }
```

bench clones one commit deep, which is all a dependency needs. For an app you develop on, `"history": true` fetches the full history right after the clone, for `git log`, `blame` and a rebase.

That checkout, in `frappe-bench/apps/<name>`, is a normal git repository on the declared branch: work from there, on a feature branch, and `repo-status.sh` shows where each one stands.

To start a new app in a repository that already exists, with at least a first commit:

```bash
./new-app.sh --push my_app https://tfs.ext.icrc.org/ICRCCollection/Digital%20Protection%20Program/_git/my_app
```

It runs `bench new-app --no-git`, puts the scaffold on `feat/init-my_app` cut from the remote's default branch, keeps any file the repository has that the scaffold does not, and asks before replacing one both have. The result is one commit to merge through a pull request. Then declare the app in `apps.json`.

Nothing in this repository authenticates to a git host: an https URL uses the credentials in your `~/.gitconfig`, an ssh one the agent your editor forwards. A clone that fails stops `install-bench.sh`, so an entry in `apps.json` must be reachable by everyone.

Your personal additions go in `development/apps.local.json`, which `get-apps.sh` reads too and git ignores. It is read first, so an entry there for an app `apps.json` also declares, by the same repository name, replaces the shared one, to take an app from your fork or another branch.

Both files matter only when an app is first fetched; `switch-version.sh` moves one already in the bench.

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
| `update-python.sh` | | Recreate the bench's virtualenv on `FRAPPE_PYTHON`, or another Python, with every app. Needed after a rebuild on another `FRAPPE_PYTHON` |
| `load-dictionary.sh` | | Load the Data Dictionary into a site, with the Application Fields and mappings of `resources/`. Prot's own, not the template's |
| `s3-create-buckets.sh`, `s3-list-buckets.sh`, `s3-list-files.sh` | | The local object store |
| `repo-status.sh` | `frstatus`, `git repo-status` | The git state of every app checkout, in one table. `--pull`, or `frpull`, fast-forwards this repository and every app, and says when the dev container has to be rebuilt |
| `pr-sync.sh` | `git pr-sync` | Return an app to its default branch once its PR is merged |
| `template-sync.sh` | | Show how this project differs from the template on GitHub, and check that every file shared with it is identical, except the ones `.template-sync` lists |
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

[betterleaks](https://github.com/betterleaks/betterleaks), the successor to gitleaks by the same author, checks every commit twice. In the container, a pre-commit hook scans what is staged and refuses the commit on a finding. On Azure DevOps, the secrets job of `azure-pipelines.yml` scans the whole history, so a commit made with `--no-verify` or outside the container is still caught. Both cover this repository only, not the app checkouts under `frappe-bench/apps/`. An app that ships its own `.pre-commit-config.yaml`, with betterleaks in it or not, gets those hooks installed by `get-apps.sh`, which also wires them into an app cloned before.

The hook is installed when the container is created. In a container created before it existed, run `pre-commit install` once. A false positive is silenced with a `betterleaks:allow` comment on the line, which a reviewer then sees; `gitleaks:allow` is still honoured. A false positive already committed, which no comment can reach, is listed by fingerprint in `.betterleaksignore`.

## Pipeline

`azure-pipelines.yml` holds the gates [ADR-018](https://tfs.ext.icrc.org/ICRCCollection/Digital%20Protection%20Program/_wiki/wikis/Digital-Protection-Program.wiki?pagePath=/Architecture/Decisions/ADR-018-ICRC-Code-Scans-on-Every-Repository-and-Dependency-Scans-on-the-Image) gives a repository on Azure DevOps, through the shared ICRC pipeline templates, each blocking:

| Job | Checks |
|---|---|
| Formatting and linting | `pre-commit run --all-files`: whitespace, YAML and JSON, ShellCheck |
| Secret scanning | betterleaks over the whole history, the release the Dockerfile pins |
| SonarQube | Static analysis, with ShellCheck, under the `pne` prefix. No coverage: there is no unit test |
| Checkmarx SAST | Static analysis. No dependency scan, which ADR-018 leaves to the application image |

It runs on `main`, and blocks a merge once it is the build validation of the branch policy of `main`. Run the lint locally with `pre-commit run --all-files`.

## Git

- **Azure DevOps** uses the token in your host's credential store, through the helper the editor forwards, see [Azure DevOps access](#azure-devops-access).
- **gh** and **git to GitHub** share one OAuth token. Run `./gh-login.sh` once and approve the code in a browser; the token lands in the host's mounted `~/.config/gh`, so it survives every rebuild. See [GitHub access](#github-access).
- **git to GitHub** goes over https, through the proxy, with gh as its credential helper, since a corporate proxy does not relay ssh on port 22. `git@github.com:` and `ssh://git@github.com/` remotes are rewritten to `https://github.com/`, so existing clones keep working.
- **git to any other host** over ssh, and commit signing, use the key from your host's agent, which the editor forwards in. No private key is copied in and only the public `allowed_signers` list reaches `~/.ssh`. The only prerequisite is on the host: an agent running with your key loaded (`ssh-add`) before you reopen in the container.
- **git config** is the host's `~/.gitconfig`, copied into `.devcontainer/` by `init-env.sh` on every start and included by the container's own `~/.gitconfig`. A change made on the host arrives at the next start. `git config --global` inside the container writes the container's file and never touches the host's. The copy is git-ignored, and can hold whatever credential your host config holds.
- **npm config** is the host's `~/.npmrc`, copied the same way and mounted read-only as the container's `~/.npmrc`, so a private registry and its token work for npm and yarn in the bench. Any `prefix` line is left out, since nvm refuses to run under one. Change it on the host; it arrives at the next start. With no host `~/.npmrc`, npm uses the public registry.

At start, `post-start.sh` clones plugins and skills with gh as the only credential helper, since the helper an editor forwards can fail, hang or abort the start when asked before the editor is attached. A marketplace on another host that needs your host's credential helper is skipped with a warning: run `bash /workspace/.devcontainer/install-plugins.sh` from a terminal once attached, where the editor forwards that helper.

A host `~/.gitconfig` rule that rewrites `https://github.com/` to ssh, as `insteadOf` or `pushInsteadOf`, wins over the container's rewrite and sends git back to port 22. Remove it, or the clone or push fails in the container.

Check with `gh auth status` and `git ls-remote https://github.com/cli/cli HEAD`. If git asks for a password, gh is not logged in. For signing, confirm the agent arrived: `SSH_AUTH_SOCK` must be set and `ssh-add -L` must list your key.

## Troubleshooting

### Cannot clone from Azure DevOps

First run the `git ls-remote` of [Azure DevOps access](#azure-devops-access) on the host: it must answer without asking for a password. If it fails there, fix the host first. A `Connection reset by peer` usually means the `userAgent = choco` line is missing from the host `~/.gitconfig`, or that you are off the ICRC network; after adding it, restart the container so `init-env.sh` copies it again. If it works on the host but not in the container, run git from a terminal of the attached editor, the only place the token reaches.

### Cannot connect to MariaDB from the IntelliJ database tool

The host to use depends on where the IDE runs. With JetBrains Remote Dev the IDE backend runs inside the `frappe` container: use `mariadb`, port `3306`. An IDE on your machine uses `localhost`, which Compose publishes. Log in as `root` with `DB_ROOT_PASSWORD` from `bash .devcontainer/init-env.sh --print`, not with a site's own user, which only authenticates from the bench.

The run configuration in `.run/frappe.run.xml` serves the bench on port 8000 under the IntelliJ debugger, with the bench's Python, `development/frappe-bench/env/bin/python`.

## herdr (optional)

[herdr](https://herdr.dev) shows whether the agent in each pane is working or waiting by watching the pane, which needs nothing from the container. Its Claude Code hook also reports the session id to herdr over a control socket, which the container reaches through the host's `~/.config/herdr`, mounted at `~/.herdr-host`. A host without that folder gets an empty one in its place, `.devcontainer/.herdr.host`, and nothing is created in its home folder. If you install herdr after the container was created, rebuild it so the real folder is mounted.

To opt in, run `herdr integration install claude` on the host, then open a shell in the container from a herdr pane with these three variables set, for instance with `docker exec` (`podman exec` takes the same flags):

```bash
docker exec -it -u frappe -w /workspace/development \
  -e HERDR_ENV=1 \
  -e HERDR_SOCKET_PATH=/home/frappe/.herdr-host/herdr.sock \
  -e HERDR_PANE_ID="$HERDR_PANE_ID" \
  <frappe container> zsh
```

Without those variables the hook exits and nothing changes. `herdr integration install` writes the hook's absolute host path into `~/.claude/settings.json`, which does not exist in the container: change it to `bash "$HOME/.claude/hooks/herdr-agent-state.sh" session`, and again after a herdr update.

Linux hosts only: a unix socket does not cross the VM of Docker Desktop on macOS or Windows.

## Divergence from upstream

Kept from [frappe_docker](https://github.com/frappe/frappe_docker/tree/main/devcontainer-example): the Compose-backed container, the `frappe` service and user, the workspace mounted with the bench one level inside it, and the port ranges.

| | Upstream | Here |
|---|---|---|
| Distribution | A folder inside frappe_docker, copied by hand | Made from a GitHub template repository; `PROJECT_NAME` keeps each copy's containers and volumes apart |
| Image | `frappe/bench:latest`, used as is | `frappe/bench` pinned to a release, plus GitHub's host keys, zsh, `micro`, `gh`, `lazygit`, `jq`, `bat`, `fzf`, `rg`, `fd`, `tree`, `ast-grep`, `chromium`, `agent-browser`, `frappectl`, `semgrep`, and `bubblewrap` and `socat` for the Claude Code sandbox. Every other image pinned to a release |
| Passwords | `123`, hardcoded in three places | Generated per install into `.env` |
| Apps | `installer.py`, honoured only at `bench init` | `apps.json` + `get-apps.sh`, which works on an existing bench |
| Site | `installer.py` | `create-site.sh`, with an explicit app list |
| Bench lifecycle | Nothing | The table above |
| Services | MariaDB, Redis. Mailpit and Postgres commented out | MariaDB, Redis, Mailpit, S3, Keycloak with a dev realm imported, LiteLLM. Postgres dropped |
| Credentials | Host `~/.ssh` bind-mounted | Host `~/.gitconfig`, `~/.ssh/allowed_signers` and `~/.npmrc` copied in on every start, `~/.config/gh` mounted and serving git to GitHub over https, ssh to other hosts through the forwarded agent |
| Proxy | Nothing | Host `HTTP_PROXY` and `HTTPS_PROXY` passed to the containers, `NO_PROXY` hardcoded to the services, empty when unset; the build's proxy comes from `devcontainer.json` |
| Egress | Open, and the `frappe` user has full sudo | Default-deny firewall at every start, with or without a proxy; sudo cut down to the firewall script |
| Windows | Nothing | `init-env.sh` runs under WSL2 or Git Bash and writes the host's home folder into `.env`, so no mount depends on the editor's environment |
| Repository work | Nothing | `gh`, `repo-status.sh`, `pr-sync.sh` |
| CI | Nothing | pre-commit, betterleaks, SonarQube and Checkmarx SAST on Azure DevOps |
| Claude Code | Nothing | Installed, with the host `~/.claude` shared, and behind the egress firewall. Skills pinned in `skills.json`, and an AGENTS.md written into the bench and each new app |

## Licence

Copyright (c) 2026 International Committee of the Red Cross (ICRC), portions Copyright (c) 2017 Frappe Technologies Pvt. Ltd.

BSD 3-Clause License. See [LICENSE](LICENSE). A project made from this template may license its copy as it chooses, provided it keeps both notices.

Portions derived from [frappe_docker](https://github.com/frappe/frappe_docker), Copyright (c) 2017 Frappe Technologies Pvt. Ltd., under the MIT licence. See [LICENSES/MIT-frappe_docker.txt](LICENSES/MIT-frappe_docker.txt).

`development/templates/ponytail-lite.md` is [ponytail-lite](https://github.com/ilindaniel/ponytail-lite), Copyright (c) 2026 DietrichGebert and Daniel Ilin, under the MIT licence. See [LICENSES/MIT-ponytail-lite.txt](LICENSES/MIT-ponytail-lite.txt). Every AGENTS.md written from it carries that notice.

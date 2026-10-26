# AGENTS.md

Guidance for coding agents working in this repository. Humans: [README.md](README.md) is the one to read, and everything here is true for you too.

## What this is

A Frappe development container: [icrc-frappe-devcontainer-template](https://github.com/icrc/icrc-frappe-devcontainer-template), or a project made from it. It ships no application code: the apps come from `development/apps.json` and are cloned into `development/frappe-bench/`, which is generated and git-ignored. A change here is a change to the environment, never to an app. A Compose project, container or volume name is derived from `PROJECT_NAME`, which `init-env.sh` writes into `.env`, never fixed.

This file is the same in the template and in every project made from it. What this repository is, its apps and the rules of its own are in PROJECT.md, which adds to this file:

@PROJECT.md

A change that is not specific to one project belongs in the template first, so that every project made from it gets it, and is then brought into the project with `development/template-sync.sh`.

You are probably running inside that container. Its egress firewall is what bounds an agent's network access, and README.md's "Claude Code and egress control" says what it covers. A connection it refuses is the control doing its job, not a fault to work around.

## Layout

```
.devcontainer/    the container: Dockerfile, Compose services, init-env.sh
development/      the scripts, apps.json, skills.json, and (generated) frappe-bench/
development/templates/   the AGENTS.md written into the bench and into a new app
```

Inside the container the repository is at `/workspace` and the bench at `/workspace/development/frappe-bench`. Do not hardcode either: every script derives its paths from its own location through `development/common.sh`, which is what lets the repository be mounted anywhere.

## Running things

Every script lives in `development/`, takes `--help`, and is the only supported way to do its job. Prefer them over raw `bench` commands, because they carry the flags and the checks.

```bash
cd /workspace/development
./install-bench.sh      # once, creates the bench
./get-apps.sh           # after editing apps.json
./create-site.sh        # a site, with apps installed
./start.sh              # the server
./migrate-site.sh       # after ANY DocType change
./repo-status.sh        # the git state of every app checkout
./get-skills.sh         # after editing skills.json; also runs on every start
./update-python.sh      # after a rebuild on another FRAPPE_PYTHON
```

## Rules

**Never edit anything under `frappe-bench/apps/frappe/`**, or under any other upstream app such as `helpdesk` or `telephony`. They are external checkouts, and a local edit is lost on the next update and invisible in review. Extend them from your own app instead, through hooks, `override_whitelisted_methods`, `override_doctype_class`, `doc_events` or a custom script. If no extension point exists, the change belongs in a pull request upstream.

**Run `./migrate-site.sh` after changing a DocType JSON.** Without it the column does not exist, the field never appears on the form, and the failure looks like a bug in the code.

**Never write a secret into a tracked file.** Every password is generated into `.devcontainer/.env` by `init-env.sh` and read from the environment. There is no default password in this repository and no new one should appear: if a script needs a secret, add it to `SECRETS` in `init-env.sh` and read it through `require_secret` in `common.sh`. betterleaks enforces this, in a pre-commit hook and on every pull request; never answer a finding with `--no-verify` or a `betterleaks:allow` (or `gitleaks:allow`) on a real secret.

**An internal host is named only where the container needs it**: `development/apps.json`, `.devcontainer/egress-allowlist` and `.devcontainer/project.env`, and only where PROJECT.md allows one at all. A personal addition goes in `apps.local.json`, which is git-ignored.

**The licence in LICENSE is chosen by ICRC when the repository is created, and is kept.** Copy third-party code in only under a licence compatible with it, with that licence's text added to `LICENSES/` and a line in README.md's Licence section. Code under an incompatible licence, or under none, is installed when the container is built or run, never committed. When compatibility is unclear, ask rather than copy.

**Every change goes through a feature branch and a pull request.** PROJECT.md says where they go and what checks them.

## Conventions for a change here

- A new script: `set -euo pipefail`, source `common.sh`, a `usage()` with a `--help` case, and `require_bench` / `require_secret` where they apply. Add it to the table in README.md and to `.devcontainer/zsh/custom.zsh` if it deserves an alias.
- Pin every version you add: an image tag, a release tarball with its sha256, an app branch in `apps.json`. A floating version makes a rebuild a different container, and the `frappe/bench` base is no exception: it moves by a reviewed pull request. The Frappe pins are `FRAPPE_VERSION`, the release installed, and `FRAPPE_PYTHON` and `FRAPPE_NODE`, the toolchain frappe/build carries at that tag. A developer's are in `.devcontainer/.env`, written from `.devcontainer/project.env` when the project has one.
- A host the whole team needs goes in `.devcontainer/egress-allowlist`, and one for a single developer in their `EGRESS_ALLOW`. Never widen the `frappe` user's sudo or drop the firewall from `postStartCommand` to get past a blocked connection.
- Check a shell change with `bash -n` at minimum, and `pre-commit run --all-files`. There is no test suite; the end-to-end check is a container rebuild, `install-bench.sh`, `create-site.sh`, `start.sh`, and the site loading.
- Keep the divergence table in README.md current when you change something the upstream frappe_docker example does differently. That table is how anyone tells our decisions from theirs.

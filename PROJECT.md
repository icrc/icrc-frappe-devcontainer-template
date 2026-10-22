# PROJECT.md

What this repository is and the rules of its own, which AGENTS.md reads. A project made from the template replaces this file with its own and lists it in `.template-sync`.

## What this is

The template itself, which projects copy with GitHub's **Use this template**. `development/apps.json` ships empty, so the bench holds Frappe alone. A change here reaches every project made from the template: nothing in a tracked file may be specific to one of them.

## Rules

**No ICRC-internal hostname, URL, project name or address anywhere.** This repository is licensed for publication. An internal example goes in `apps.local.json`, which is git-ignored, or in a placeholder form such as `tfs.example.org`. So `egress-allowlist` holds public hosts only, the template ships no `project.env`, and an internal host goes in the developer's `EGRESS_ALLOW`.

**Commits are signed**, and pull requests go to GitHub. README.md has the ssh signing setup.

**Dependabot** bumps `frappe/bench`, the service images and the GitHub Actions by pull request.

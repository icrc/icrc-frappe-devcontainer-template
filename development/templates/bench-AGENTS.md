# AGENTS.md

This directory is a Frappe Framework bench. Installed apps with respective repositories are in the `apps/` directory. Sites/tenants are in the `sites/` directory.

Each app under `apps/` is its own git repository, and its own AGENTS.md wins over this file. `apps/frappe` and every other upstream app are read, never edited. The scripts in `../` run every bench task, and `../../AGENTS.md` has the rules of the environment.

# AGENTS.md

Guidance for coding agents working in APP_NAME, a Frappe app. It is developed in a bench, two levels up from this checkout, whose own AGENTS.md describes it.

## Layout

```
APP_NAME/hooks.py                          how the app plugs into Frappe
APP_NAME/modules.txt                       the modules; a new one goes here first
APP_NAME/patches.txt                       data migrations, run by bench migrate
APP_NAME/<module>/doctype/<doctype>/       a DocType: JSON, controller, form script, tests
```

## Rules

**Change a DocType through its JSON, then migrate the site.** Without the migration the column does not exist and the field never appears on the form.

**Extend Frappe and every other app from here**, through `hooks.py`: `doc_events`, `override_doctype_class`, `override_whitelisted_methods`, fixtures. Never edit another app's code.

**Check permissions in every whitelisted method** before reading or writing, with `frappe.has_permission` or `frappe.only_for`. `ignore_permissions=True` never applies to data a user sent.

**Query through `frappe.qb` or `frappe.get_all`**, never through SQL built from a formatted string.

**Never write a secret into a tracked file.** Read it from the site config or the environment.

**Let the pre-commit hooks run.** A failing hook is fixed, never skipped with `--no-verify`.

## Tests

Prefer a test that runs without a site, with its data in fixtures, wherever the logic allows: it answers in seconds, which is what lets an agent iterate. Run the full suite through the bench before a pull request:

```bash
bench --site <site> run-tests --app APP_NAME
```

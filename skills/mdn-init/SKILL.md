---
name: mdn-init
model: low
description: >
  Meridian project initializer. On first run, detects missing config and asks the user for
  their Obsidian vault path, writing it to ~/.config/meridian/config.md. Then creates a
  new Meridian project (one project.md file) inside the vault's `meridian/` directory.
  Use when the user says "create a new Meridian project", "init a project", "start a new
  project in Meridian", or runs `/mdn-init name:<slug>`.
---

## Invocation

```
/mdn-init name:<slug> [title:"Human readable title"] [description:"One-line summary"] [repo:<absolute path>]
```

| Argument | Required | Description |
|---|---|---|
| `name` | yes | Project slug: kebab-case, used as the folder name and the `project:` field. |
| `title` | no | Human-readable title. Defaults to the title-cased slug. |
| `description` | no | One-line summary shown under the heading. |
| `repo` | no | Absolute path of the code repository. Defaults to the current git toplevel when there is one; otherwise left empty. |

Format reference: `docs/protocol.md`. Primitive used: WRITE.

## Steps

### 1. Resolve config

Config path: `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`. If it exists, READ `vault:` and continue.

If it is missing (first-run setup):
1. Tell the user Meridian is not configured and ask once: "What is the absolute path to your Obsidian vault?"
2. Validate that the path exists on disk. Stop until answered.
3. WRITE the config file:

````markdown
---
vault: <absolute-path>
delivery:
---

# Meridian Configuration

> `vault`: absolute path of the Obsidian vault root. Projects live in `<vault>/meridian/<slug>/project.md`.
> `delivery` (optional): a free-text sentence passed verbatim to the ODD workflow by `/mdn-run`,
> for example `single PR; I accept size:exception`. Leave it empty to use the ODD defaults.
````

### 2. Validate arguments

Extract `name`, `title`, `description`, `repo`. `name` must match `^[a-z0-9]+(-[a-z0-9]+)*$`; if missing or invalid, ask once. Generate `title` from the slug when absent (`my-app` -> `My App`).

### 3. Check for conflicts

If `<vault>/meridian/<slug>/` already exists, warn and ask whether to abort or continue; never overwrite an existing file.

### 4. Create the project note

Create `<vault>/meridian/` if needed, then WRITE `<vault>/meridian/<slug>/project.md` from `templates/Project.md` (installed copy: `~/.config/meridian/templates/Project.md`). Replace the Templater expressions with literal values:

- `title`: the title; `project`: the slug; `status: active`.
- `repo`: the path when known, otherwise remove the line.
- The description line under the heading, when given.

No other file or folder is created. `TASK_HISTORY.md` appears later, when `/mdn-archive` first runs.

Run `scripts/mdn-lint.sh <project.md>` (resolve it from the Meridian repository; if not found, say the check was skipped). A note with no tasks is valid.

### 5. Confirm

```
Project initialised: <vault>/meridian/<slug>/project.md

Next:
  /mdn-add "<description>" project:<slug>     queue a task for later
  /mdn-run "<description>" project:<slug>     record and execute a task now
```

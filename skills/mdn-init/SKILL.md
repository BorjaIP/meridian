---
name: mdn-init
model: low
description: >
  Meridian project initializer. On first run, detects missing config and asks the user for
  their Obsidian vault path, writing it to ~/.config/meridian/config.md. Then creates a new
  Meridian project folder structure inside the vault's `meridian/` directory. Use when the
  user says "create a new Meridian project", "init a project", "start a new project in
  Meridian", or runs `/mdn-init name:<slug>`.
---

## Invocation

```
/mdn-init name:<slug> [title:"Human readable title"] [description:"One-line summary"]
```

| Argument | Required | Description |
|---|---|---|
| `name` | yes | Project slug — kebab-case, used as folder name and `project:` field |
| `title` | no | Human-readable title. Defaults to title-cased slug. |
| `description` | no | One-line summary shown in project note header. |

## Execution steps

### Step 0 — Resolve config
Config path: `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`.

**If exists:** read `vault` and `date-format`. Run Date generation snippet → `<NOW>`.

**If missing (first-run setup):**
1. Tell user: "Meridian is not configured yet. I need the path to your Obsidian vault."
2. Ask: "What is the absolute path to your Obsidian vault?"
3. Validate the path exists on disk.
4. Compute `<NOW>` using this snippet:
   ```bash
   d=$(date +%-d); case $((d % 100)) in 11|12|13) suf="th";; *) case $((d % 10)) in 1) suf="st";; 2) suf="nd";; 3) suf="rd";; *) suf="th";; esac;; esac; date "+%A ${d}${suf} %B %Y %H:%M"
   ```
5. Write `~/.config/meridian/config.md`:

````markdown
---
vault: <absolute-path>
created: <NOW>
version: 1
date-format: "dddd Do MMMM YYYY HH:mm"
---

# Meridian Configuration

> Edit `vault` to point to your Obsidian vault root.
> Run `/mdn-init name:<slug>` to create a new project inside it.

## Date generation

```bash
d=$(date +%-d); case $((d % 100)) in 11|12|13) suf="th";; *) case $((d % 10)) in 1) suf="st";; 2) suf="nd";; 3) suf="rd";; *) suf="th";; esac;; esac; date "+%A ${d}${suf} %B %Y %H:%M"
```
````

6. Confirm config written. Continue with provided path as `<vault>`.

### Step 1 — Parse and validate arguments
Extract `name`, `title`, `description`. Validate `name` is kebab-case. If missing: ask. If `title` not given: generate from slug (`my-app` → `My App`).

### Step 2 — Check for conflicts
If `<vault>/meridian/<slug>/` already exists: warn and ask to abort or continue (will not overwrite existing files).

### Step 3 — Create folder structure
Create placeholder files so folders are visible in Obsidian and tracked by git:
- `<vault>/meridian/<slug>/plans/.gitkeep`
- `<vault>/meridian/<slug>/tasks/.gitkeep`
- `<vault>/meridian/<slug>/notes/.gitkeep`
- `<vault>/meridian/<slug>/meeting-notes/.gitkeep`
- `<vault>/meridian/<slug>/docs/.gitkeep`

Create `<vault>/meridian/` first if it doesn't exist.

### Step 4 — Create project note
Write `<vault>/meridian/<slug>/project.md` using `@~/.config/meridian/templates/Project.md`. Fill in: `title`, `created: <NOW>`, `project: <slug>`, description placeholder, `# <title>` heading. Plans and Tasks tables start empty.

### Step 5 — Confirm to user

```
✓  Project initialised: <vault>/meridian/<slug>/
   plans/ tasks/ notes/ meeting-notes/ docs/
   project.md

→  Next steps:
   1. Open project.md and add your first task
   2. Drop a planning artifact in docs/ and run:
      /mdn-load project:<slug> path:meridian/<slug>/docs/<file>.md type:<type>
   3. Or run /mdn-run project:<slug> to plan inline
```

## Meridian protocol reference

- Config: `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`
- Required frontmatter: `project: <slug>`, `status: active`

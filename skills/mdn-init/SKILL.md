---
name: mdn-init
model: low
description: >
  Meridian project initializer. On first run, detects missing config and asks the user for
  their Obsidian vault path, writing it to ~/.config/meridian/config.md. Then creates a
  new Meridian project (one project.md file) inside the vault's `meridian/` directory and
  fills its one-line description from the repository context. Also runs in auto mode when
  another Meridian command finds the project not initialized. Use when the user says "create a new Meridian project", "init a project", "start a new
  project in Meridian", or runs `/mdn-init name:<slug>`.
---

## Invocation

```
/mdn-init [name:<slug>] [title:"Human readable title"] [description:"One-line summary"] [repo:<absolute path>]
```

| Argument | Required | Description |
|---|---|---|
| `name` | interactive: yes | Project slug: kebab-case, used as the folder name and the `project:` field. In auto mode it defaults to the kebab-case basename of the git toplevel. |
| `title` | no | Human-readable title. Defaults to the title-cased slug. |
| `description` | no | One-line summary. When given it is used as is; otherwise it is derived (see "Description derivation"). |
| `repo` | no | Absolute path of the code repository. Defaults to the current git toplevel when there is one; otherwise left empty. |

Format reference: `docs/protocol.md`. Primitives used: READ, GREP, WRITE, EDIT.

## Modes

- **Interactive** (the user runs `/mdn-init`): may ask questions, as written in the steps.
- **Auto mode**: see "Auto mode" below; used by the init guard of the other commands.

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

Extract `name`, `title`, `description`, `repo`. `name` must match `^[a-z0-9]+(-[a-z0-9]+)*$`; if missing or invalid, ask once (interactive) or derive it (auto mode). Generate `title` from the slug when absent (`my-app` -> `My App`).

### 3. Check for an existing project

If `<vault>/meridian/<slug>/project.md` already exists, this is a re-run:

- If its description line (the first `> ` line under the heading) still starts with `> TODO:`, go to "Description derivation" and replace that one line only.
- Otherwise say `already initialized: <path>` and stop.
- Never change anything else on a re-run: no other line, no other file, no tasks, no frontmatter.

If the folder exists without a `project.md`, warn and ask whether to continue (interactive) or stop and report (auto mode). Never overwrite an existing file.

### 4. Create the project note

Create `<vault>/meridian/` if needed, then WRITE `<vault>/meridian/<slug>/project.md` from `templates/Project.md` (installed copy: `~/.config/meridian/templates/Project.md`). Replace the Templater expressions with literal values:

- `title`: the title; `project`: the slug; `status: active`.
- `repo`: the path when known, otherwise remove the line.
- The description line under the heading: the `description` argument if given, otherwise the line from "Description derivation" (formatted `> <line>`), otherwise the `> TODO: add a one-line description of this project.` placeholder.

**Text safety.** Before writing any title, description, acceptance, note or reason into a vault note or log, wrap every tag-like placeholder such as `<branch-name>`, `<name>` or `</x>` in backticks, unless it is already inside backticks. Obsidian reads a bare `<word>` as an unclosed HTML tag and stops rendering everything below it. Plain text like `a < b` needs no change. `mdn-log.sh` applies this rule to log text by itself; `mdn-lint.sh` reports any that slipped through. A derived description already has backticks and HTML stripped (see "Description derivation"); this rule covers a `description` argument given as is.

The `logs/` folder appears later, when the first event or `/mdn-archive` writes to it.

Run `scripts/mdn-lint.sh <project.md>` (look in `~/.config/meridian/scripts/` first, then the repository's `scripts/`; if not found, say the check was skipped). A note with no tasks is valid.

Log the creation: `mdn-log.sh event <vault>/meridian/<slug> init - "<description source>"` (the evidence file, `argument` or `placeholder`). Logging rule: look for `mdn-log.sh` in `~/.config/meridian/scripts/` first, then the repository's `scripts/`. If it is missing or fails, print a one-line warning and continue; logging must never fail or block the command.

Dashboard: if `<vault>/meridian/dashboard.md` does not exist, create it by copying `~/.config/meridian/templates/Dashboard.md` (or the repository's `templates/Dashboard.md` when the installed copy is missing). If it exists, never overwrite it, even on a re-run; do not touch it. Skip silently if no template is found.

### 5. Confirm

```
Project initialised: <vault>/meridian/<slug>/project.md
Description: <the line, or "placeholder kept: <reason>">
Dashboard: <created <vault>/meridian/dashboard.md | already present, kept>
Evidence: <source file or command, or "none">

Next:
  /mdn-add "<description>" project:<slug>     queue a task for later
  /mdn-run "<description>" project:<slug>     record and execute a task now
```

## Description derivation

Runs when creating a project without a `description` argument, and on a re-run whose description is still the `> TODO:` placeholder.

**Repo:** the `repo:` frontmatter value or argument; otherwise the git toplevel of the current directory (`git rev-parse --show-toplevel`). With no repo, keep the placeholder and tell the user in one line: `Description left as placeholder: no repository found.`

**Evidence, in this order; stop at the first source that yields a usable sentence:**

1. `README.md` (or `README*`): the first meaningful paragraph (skip badges, images, HTML, link-only lines, tables of contents, headings); if there is only a title, use the title plus its tagline (a blockquote or italic line right after it).
2. Package manifests: `package.json` `description`; `pyproject.toml` `[project] description` or `setup.cfg` `description`; `Cargo.toml` `description`; `go.mod` module path combined with the README title.
3. The head of `CLAUDE.md` or `AGENTS.md` (first meaningful paragraph).
4. Last resort: the repository name from `git remote get-url origin`, as "Repository <name>." and nothing more.

**Writing the line:**

- One plain sentence in English, at most 140 characters, no markdown (strip emphasis, links, backticks, HTML). Condense or cut at a word boundary; translate non-English evidence faithfully.
- Use only what the evidence says: never invent. Do not guess the purpose from file names, dependencies or the project name.
- If no source yields a usable sentence, keep the `> TODO:` placeholder and tell the user exactly why in one line, for example `Description left as placeholder: README.md has no paragraph and no manifest has a description.`
- Interactive mode only: when evidence is insufficient, ask the user once for the description. Never ask in auto mode.
- The final report shows the chosen line and its evidence source (file, or `git remote`).

## Auto mode

Used by the init guard of the other commands (add, run, done, daily, status, archive) when Meridian is not initialized for the current project. Same steps as above, with these differences:

- No questions, except the vault path when `~/.config/meridian/config.md` is missing.
- The project slug is the `project:` argument when the calling command received one; otherwise the kebab-case basename of the git toplevel (lower-case, non-alphanumeric runs to `-`). With no repo and no `project:` argument, stop and say so.
- `title` defaults from the slug; `repo` is the git toplevel.
- A description that cannot be derived stays a placeholder; do not ask.
- Create `dashboard.md` only if missing (never overwrite) and do it silently, mentioning it only in the one-line summary.
- Finish with a single line, then return control to the calling command: `Initialized <slug> (<vault>/meridian/<slug>/project.md); description: <line or placeholder>; dashboard <created|kept>.`

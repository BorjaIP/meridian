# Configuration

---

## Config File

Meridian follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/). Configuration lives at:

```
${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md
```

Typically: `~/.config/meridian/config.md`

### Format

```markdown
---
vault: /absolute/path/to/obsidian/vault
created: Saturday 4th April 2026 14:00
version: 1
date-format: "dddd Do MMMM YYYY HH:mm"
model-low: haiku
model-medium: sonnet
model-high: opus
---

# Meridian Configuration

> Edit `vault` to point to your Obsidian vault root.
> Run `/mdn-init name:<slug>` to create a new project inside it.

## Date generation

```bash
d=$(date +%-d); case $((d % 100)) in 11|12|13) suf="th";; *) case $((d % 10)) in 1) suf="st";; 2) suf="nd";; 3) suf="rd";; *) suf="th";; esac;; esac; date "+%A ${d}${suf} %B %Y %H:%M"
```
```

**Rules:**
- `vault` is the only required field. It must be an absolute path to the Obsidian vault root.
- `date-format` controls the datetime format used in all notes.
- `model-low/medium/high/max` set the Claude model tiers used by skills (haiku/sonnet/opus).
- All Meridian skills read `vault` from this file before operating.
- If `config.md` does not exist, the first skill invoked runs first-time setup automatically.
- This file is agent-agnostic — any Meridian adapter (Claude, Cursor, Codex) reads it from the same location.

---

## Project Note

Each project lives in `<vault>/meridian/<slug>/` and is created by `/mdn-init`.

**Location:** `<vault>/meridian/<slug>/project.md`

**Folder structure:**

```
<vault>/
  meridian/
    <slug>/
      project.md         ← project note (entry point)
      plans/             ← Plan index notes
      tasks/             ← extended task notes (optional)
      notes/             ← general notes
      meeting-notes/     ← meeting notes
      docs/              ← external artifacts (PRDs, ADRs…)
```

**Required frontmatter:**

```yaml
---
title: Project Name
created: <date>
project: project-slug        # machine-readable, kebab-case — canonical ID
status: active               # active | paused | done | archived
tags:
  - project
draft: true
---
```

### Plans Table

Each project note has a `## Plans` section listing all loaded planning artifacts:

```markdown
## Plans

| Plan | Type | Task | Status | Loaded |
|---|---|---|---|---|
| [[prd-auth]] | PRD | Build auth flow | approved | Saturday 3rd April 2026 12:00 |
| [[adr-db]]   | ADR | Choose database  | pending-review | Saturday 3rd April 2026 12:00 |
```

This table is managed by `mdn-load`. Agents read it to find plans linked to their current task.

---

## Task Format

Tasks are Markdown checkboxes inside a `## Tasks` section:

```markdown
## Tasks

- [ ] #task owner::agent status::backlog type::feature priority::high
  **Title:** Short imperative title
  **Description:** What needs to be done and why.
  **Acceptance:** What does "done" look like?
  **Depends on:** (optional) title of prerequisite task

- [ ] #task owner::me status::review type::review
  **Title:** Review: PRD for feature X
  **Description:** Agent has prepared a plan. Read and approve before execution starts.
  **Artifact:** [[meridian/<slug>/plans/feature-x]]
```

### Task Fields

| Field | Values | Description |
|---|---|---|
| `owner` | `me` \| `agent` | Who executes this task |
| `status` | `backlog` \| `planning` \| `review` \| `approved` \| `in-progress` \| `done` \| `blocked` | Lifecycle state |
| `type` | `feature` \| `fix` \| `research` \| `review` \| `chore` | Nature of the work |
| `priority` | `high` \| `medium` \| `low` | Optional urgency signal |

Fields use `key::value` syntax (Dataview-compatible). Regex: `/\b(\w+)::(\S+)/g`.

---

## Plan Note Format

Plan notes are index files that point to artifacts. They live at `<vault>/meridian/<slug>/plans/<plan-name>.md` and are created by `mdn-load`.

**Frontmatter:**

```yaml
---
title: "Plan: <descriptive title>"
created: <date>
project: <slug>
task: <linked task title>
status: pending-review | approved | superseded
tags:
  - plan
draft: true
---
```

**Body structure:**

```markdown
> One-line summary synthesizing Description + Acceptance into a statement of intent.

---

## Artifacts

| Type | Document | Description |
|---|---|---|
| PRD | [[path/to/prd]] | Full product requirements |
| ADR | /absolute/path/to/adr.md | Architecture decision |

---

## Key Points
- Most important things to know before executing

---

## Execution Order
1. Read the PRD first
2. Then the ADR
3. Start with X

---

## Notes
> Free-form notes added during review or execution.
```

The `## Artifacts` table accepts vault wikilinks, absolute paths, or any path format. `mdn-run` reads every artifact listed here before executing the task.

---

## Tooling Adapters (Optional)

The core protocol only requires config resolution and Markdown read/write access to the vault. These adapters are optional enhancements.

### Decision Tree

```
Need to operate on a KNOWN file path?
  └─► Native (grep/Edit/Write) — always use this

Need to DISCOVER files or query the vault index?
  ├─► Obsidian installed? → Use Obsidian CLI adapter
  └─► No Obsidian?        → Native grep across vault

Creating or editing a vault note?
  └─► Include obsidian-markdown skill for formatting conventions
```

### Adapter A — Obsidian CLI

Use when the agent needs to query the vault index rather than operate on a known file path.

| Operation | Native | With Obsidian CLI |
|---|---|---|
| Find project by slug | `grep -rl "project: <slug>" .` | `obsidian search query="project: <slug>"` |
| List all vault tags | `grep -rh "tags:" .` + parse | `obsidian tags` |
| Backlinks to a plan note | `grep -rl "[[plan-note]]" .` | `obsidian backlinks file="plan-note"` |
| Set frontmatter property | Regex edit on YAML block | `obsidian property:set path="..." name="..." value="..."` |

Not suitable for: CI pipelines, remote agents, MCP servers, or environments without Obsidian installed. Native is always the safe fallback.

### Adapter B — kepano/obsidian-skills

Source: [github.com/kepano/obsidian-skills](https://github.com/kepano/obsidian-skills)

Markdown instruction files injected into the agent context. No runtime dependency.

| Skill | What it adds | When to include |
|---|---|---|
| `obsidian-markdown` | Wikilink syntax, callouts, embeds, frontmatter formatting | Always — when creating or editing vault notes |
| `obsidian-bases` | How to read/write `.base` files | Only if the project uses `.base` files |
| `obsidian-cli` | How to invoke the Obsidian CLI correctly | When using Adapter A |
| `defuddle` | Extract clean Markdown from web pages | When ingesting web content |

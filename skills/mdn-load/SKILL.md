---
name: mdn-load
model: low
description: >
  Meridian ingestion skill. Registers an external planning artifact (PRD, ADR, RFC, spec, DD,
  research doc) into a Meridian project as a Plan index note. The artifact can live anywhere:
  inside the Obsidian vault, inside a git repository, at an absolute path, or any custom
  location the user provides. Use when the user says "load this plan", "ingest this PRD",
  "add this doc to my project", "register this in Meridian", or runs `/mdn-load`.
---

## Artifact path handling

| Format | Example | Stored as |
|---|---|---|
| Vault-relative | `my-notes/prd.md` | `[[my-notes/prd]]` |
| Absolute | `/home/user/projects/app/docs/prd.md` | Absolute path |
| Repo-relative | `./docs/prd.md` | Path as provided |
| Custom | any string | Verbatim |

Resolution order: (1) absolute, (2) `<vault>/<path>`, (3) relative to CWD. If unresolved: ask.

## Invocation

```
/mdn-load project:<slug> path:<path> type:<type> [plan:<plan-name>] [task:<task-title>]
```

| Argument | Required | Description |
|---|---|---|
| `project` | yes | Meridian project slug |
| `path` | yes | Path to artifact |
| `type` | yes | `prd` \| `adr` \| `rfc` \| `spec` \| `dd` \| `research` |
| `plan` | no | Plan index filename (kebab-case, no ext). Default: artifact filename stem. |
| `task` | no | Exact title of the task this plan belongs to. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>` (use for every `created:`, `Loaded`, `**Completed by:**` field). If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Parse and validate arguments
Validate `project`, `path`, `type` present. `type` must be one of: `prd`, `adr`, `rfc`, `spec`, `dd`, `research`. If missing: ask before proceeding.

### Step 3 — Resolve and read the artifact
Try resolution order above. If unresolved: report full paths tried and ask.

Extract first non-empty, non-frontmatter heading/line as one-line description.

Determine reference string:
- Inside vault → `[[vault-relative-path-without-extension]]`
- Otherwise → absolute resolved path

### Step 4 — Resolve plan name
Use `plan:` if given; otherwise derive from artifact filename stem.

Plan note path: `<vault>/meridian/<slug>/plans/<plan-name>.md`

### Step 5 — Create or update plan index note

**New plan:** read `@~/.config/meridian/templates/Plan.md` byte-for-byte. Apply substitutions:
- `<% tp.file.title.replace('Plan - ', '') %>` → plan name (frontmatter `title:` and `# Plan:` heading)
- `<% tp.date.now(...) %>` → `<NOW>`
- `project:` → `project: <slug>`
- `task:` → `task: "<task title>"` (empty string if no `task:`)
- Placeholder row `| | | |` in `## Artifacts` → `| <TYPE> | <reference> | <description> |`
- Leave `status: pending-review` and `tags:` unchanged.
Write the resulting string as the complete file.

**Existing plan:** append after last non-empty/non-header row in `## Artifacts`:
```markdown
| <TYPE> | <reference> | <description> |
```

TYPE is uppercase: PRD, ADR, RFC, SPEC, DD, RESEARCH.

### Step 6 — Update project note's Plans table
Upsert row:
```markdown
| [[<plan-name>]] | <type> | <task title or —> | pending-review | <NOW> |
```
Header if missing: `| Plan | Type | Task | Status | Loaded |`

### Step 6.5 — Sync plan note status
Read plan note, replace `^status:\s*.*$` in YAML frontmatter with `status: pending-review`. Write back. Warn if missing.

### Step 7 — Update Sources
If artifact path is absolute (outside vault), add its parent directory to `## Sources` in `PROJECT.md` if not already present. Create `## Sources` section before `## Plans` if missing.

### Step 9 — Create review task
Append to `## Tasks` in `PROJECT.md`:
```markdown
- [ ] #task owner::me status::review type::review priority::high
  **Title:** Review plan: <plan-name>
  **Description:** Plan loaded for review. Open [[<plan-name>]], check Key Points and Execution Order, then mark approved to unlock /mdn-run.
  **Artifact:** [[<plan-name>]]
```

If `task:` given: also find that task, replace `status::backlog`/`status::planning` → `status::review`, add `**Artifact:** [[<plan-name>]]` if absent.

### Step 9.5 — Update Tasks table
Upsert: `| Review plan: <plan-name> | [[<plan-name>]] | me | review |`

If `task:` given and transitioned: also upsert: `| <task title> | [[<plan-name>]] | <owner> | review |`

### Step 10 — Post-action task resolution
Scan `owner::me status::backlog` tasks. Close a task only if it passes **all three gates**:

- **Gate 1 (never close):** `type::review`, tasks with `**Artifact:**`, tasks with unresolved `**Depends on:**`
- **Gate 2 (action verb):** title or description contains: `load`, `ingest`, `carga`, `mdn-load`, `añadir plan`, `registrar`
- **Gate 3 (subject overlap):** ≥2 tokens from {artifact filename stem + type + project slug} appear in task title+description (case-insensitive), OR ≥1 token if Gate 2 verb in title

Print evidence before closing:
```
◇  Auto-close candidate: "<task title>"
   Gate 2 matched: "<verb>"
   Gate 3 matched: <N> tokens → threshold met
   → Closing.
```

On match: `status::backlog` → `status::done`, `- [x]`, append `**Completed by:** /mdn-load on <NOW>`.

### Step 11 — Confirm to user

```
✓  Plan index: [[<plan-name>]]
✓  Artifact registered: <TYPE> → <reference>
✓  Review task created: "Review plan: <plan-name>" [owner::me status::review]

→  Next:
   1. Open [[<plan-name>]] and fill in Key Points / Execution Order
   2. Run /mdn-approve project:<slug> to approve and execute
```

## Meridian protocol reference

- Plan index: `<vault>/meridian/<slug>/plans/<plan-name>.md`
- State machine: `backlog → planning → review → approved → in-progress → done`

---
name: mdn-sync
model: low
description: >
  Meridian sync skill. Scans all source directories registered in a project's ## Sources
  section and ingests any .md files not yet indexed as plan notes. Use when the user says
  "sync plans", "ingest all plans", "load all artifacts from sources", or runs
  `/mdn-sync project:<slug>`.
---

## Invocation

```
/mdn-sync project:<slug> [type:<type>] [dry-run:yes]
```

| Argument | Required | Description |
|---|---|---|
| `project` | yes | Meridian project slug |
| `type` | no | Force type for all ingested artifacts. Default: `spec`. |
| `dry-run` | no | `yes` to preview without writing. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Read project note and Sources
Read `<vault>/meridian/<slug>/project.md`. Extract `## Sources` list items as directory paths. If missing/empty: report and suggest adding paths or running `/mdn-load` first.

### Step 2 — Collect existing plan references
From `## Plans` table, extract all wikilink stems (`[[<name>]]` → `<name>`). Build indexed set.

### Step 3 — Scan source directories
For each source directory: list all `.md` files (non-recursive). Derive plan name from filename stem. Skip if already in indexed set. Add new files to ingestion queue with absolute path.

### Step 4 — Dry run (if `dry-run:yes`)
Print preview and stop:
```
◇  Dry run — nothing will be written

Sources scanned:
  /path/to/dir/ (N files, N new)

Would ingest:
  - <file>.md → plan: <name> [<type>]

Already indexed (skipped):
  - <file>.md
```

### Step 5 — Ingest new artifacts
For each file in queue, apply mdn-load Steps 4–7 logic:
- Derive plan name from filename stem
- Read file → extract first non-empty heading/line as description
- Create plan note at `<vault>/meridian/<slug>/plans/<plan-name>.md`
- Append artifact row to plan's `## Artifacts` table
- Upsert row in project note's `## Plans` table

### Step 6 — Confirm to user

```
✓  Sync complete for <slug>

Sources scanned: <N>
New plans indexed: <N>
Already indexed (skipped): <N>

New plans:
  [[<name>]] ← <description>

→  Next: review each new plan. Run /mdn-run project:<slug> when approved.
```

If nothing new: `✓  Nothing new to sync for <slug>.`

## Meridian protocol reference

- Sources section: `## Sources` — list of directory paths
- Plan index: `<vault>/meridian/<slug>/plans/<plan-name>.md`

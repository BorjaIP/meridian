---
name: mdn-archive
model: low
description: >
  Meridian archive skill. Scans all status::done tasks in a project, appends them to
  tasks/history.md (creating the file if needed), and removes them from project.md.
  Tasks are never deleted — archived verbatim with a timestamped section header.
  Use when the user says "archive tasks", "clean up done tasks", "move done to history",
  or runs `/mdn-archive`.
---

## Invocation

```
/mdn-archive project:<slug>
```

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/project.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Collect done task blocks
Scan `## Tasks` for blocks matching `- [x]` + `status::done`. A block = the `- [x]` line plus all continuation lines (2+ leading spaces). Collect full text into `done_blocks`. Also extract each block's `**Title:**` (fallback: first 60 chars).

If none found: report "No done tasks to archive in `<slug>`." and stop.

### Step 3 — Ensure history file
Path: `<vault>/meridian/<slug>/tasks/history.md`. If missing, create with:

```markdown
---
title: Task History
project: <slug>
---

# Task History

> Archived tasks for project `<slug>`. Tasks are appended in reverse-chronological order.
> Never edit this file manually — use `/mdn-archive` to add entries.

```

### Step 4 — Append to history file
Append at end of file:

```markdown
## Archived on <NOW>

<task_block_1>
<task_block_2>
```

Each block verbatim, blank line between blocks.

### Step 5 — Remove done blocks from project.md
For each block in `done_blocks`: remove the `- [x]` line, its continuation lines, and the immediately preceding blank line. Do not touch other tasks.

### Step 6 — Update Tasks table
Remove rows from `## Tasks` table where Task column matches an archived title.

### Step 7 — Confirm to user

```
[ok] Archived <N> task(s) from <slug>:
  - <title>
  ...

History file: <vault>/meridian/<slug>/tasks/history.md
project.md: <N> task block(s) removed, Tasks table updated.
```

## Meridian protocol reference

- History file: `<vault>/meridian/<slug>/tasks/history.md`
- State machine: `backlog → planning → review → approved → in-progress → done`

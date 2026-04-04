---
name: mdn-daily
model: low
description: >
  Meridian daily review skill. Surfaces all tasks that need human attention today across
  all active projects: items pending review, high-priority backlog items owned by the user,
  and any blocked tasks. Use when the user says "what do I need to do today", "show my
  tasks", "daily meridian", or runs `/mdn-daily`.
---

## Symbol vocabulary

| Symbol | Meaning |
|--------|---------|
| `◆` | Header / project section |
| `▸` | Review item — needs your action |
| `▲` | High-priority human task |
| `■` | Blocked item |
| `◎` | Agent in progress (informational) |
| `→` | Agent ready / run command / artifact link |
| `✓` | All-clear |
| `·` | Separator |

## Invocation

```
/mdn-daily
```

No arguments. Always scans all active projects.

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Discover active projects
Glob `<vault>/meridian/*/project.md`. Filter to `status: active` frontmatter.

### Step 2 — Collect tasks per project
For each project note, scan `## Tasks` into five buckets:

- **A — Review** (`owner::me status::review`): title + `**Artifact:**` wikilink
- **B — High-priority** (`owner::me status::backlog priority::high`): title + description first sentence (truncate at first `.` or 120 chars)
- **C — Blocked** (`owner::me status::blocked` or `owner::agent status::blocked`): title + owner tag + `**Note:**` if present
- **D — In progress** (`owner::agent status::in-progress`): title + `**Artifact:**` if present
- **E — Agent ready** (`owner::agent status::approved`): title + `**Artifact:**` if present

### Step 3 — Print daily brief

```
◆  Meridian Daily  ─  <Day Nth Month YYYY>
────────────────────────────────────────────
```

For each project with items in any bucket, print one project block. Skip projects with no items.

**Project block:**
```
◆  <title>  (<slug>)

  ▸  <task title>  →  [[<plan-name>]]
  ▸  <task title>  (no plan)
  ▲  <task title>
     <first sentence of description>
  ■  <task title> [agent]  —  <note if present>
  ◎  <task title>  [[<plan-name>]]
  →  /mdn-run project:<slug>   # "<task title>"
```

Rules: one blank line before each project block. Order: A→B→C→D→E. No sub-headers. Artifact links inline. Bucket A: show `(no plan)` if no artifact. Bucket B: description line indented 5 spaces. Two spaces before each symbol.

### Step 4 — Summary

**Human attention needed (A, B, or C non-empty):**
```
────────────────────────────────────────────
▸  <N> items need your attention  ·  <X> pending review  ·  <Y> high-priority  ·  <Z> blocked
   ◎  <N> in progress  ·  <N> ready to run    ← only if D or E non-empty
```
Omit zero-count segments.

**All clear (A, B, C empty):**
```
────────────────────────────────────────────
✓  All clear — nothing needs your attention.
  →  /mdn-run project:<slug>   # "<task title>"    ← for each E item
  ◎  <task title>  (project:<slug>)                ← for each D item
```

**All five buckets empty:**
```
✓  All clear — no tasks pending and no agents queued.
```

## Meridian protocol reference

- Project notes: `<vault>/meridian/*/project.md` with `status: active`
- Task inline fields: `key::value`

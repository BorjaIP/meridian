---
name: mdn-status
model: low
description: >
  Meridian dashboard skill. Scans all active Meridian projects in the vault and prints
  a summary table with task counts by status and owner. Use when the user says "show
  project status", "what's the state of my projects", "meridian dashboard", or runs
  `/mdn-status`.
---

## Invocation

```
/mdn-status [project:<slug>]
```

| Argument | Required | Description |
|---|---|---|
| `project` | no | Limit output to a single slug. Omit for all active projects. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`, `date-format`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Discover project notes
Glob `<vault>/meridian/*/PROJECT.md`. Filter to `status: active` in frontmatter. If `project:` given, filter to that slug. If none found: report and stop.

### Step 2 — Count tasks per project
For each project note, scan `## Tasks`. Parse `owner::` and `status::` from all task lines (`- [ ]` and `- [x]`). Build count map:

```
{ backlog/planning/review/approved/in-progress/done/blocked } × { agent/me }
```

Collect titles of `status::review owner::me` tasks separately.

### Step 3 — Print dashboard

One block per project:

```
## <title> (`<slug>`)

| Status      | Agent | Me |
|-------------|-------|----|
| backlog     |   N   |  N |
| ...         |       |    |

▸  Needs your attention:
  - <task title>  [status::review owner::me]
```

Omit zero rows. Omit "Needs your attention" if empty. If `project:` given, also print the full `## Plans` table.

### Step 4 — Summary line

```
─────────────────────────────────────────
<N> active project(s) · <N> pending your review · <N> agent tasks approved and ready
```

## Meridian protocol reference

- Project notes: `<vault>/meridian/*/PROJECT.md` with `status: active`
- Task inline fields: `key::value`

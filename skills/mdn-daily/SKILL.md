---
name: mdn-daily
model: low
description: >
  Meridian daily review skill. Read-only. Surfaces what needs the human today across all
  active projects: tasks in review (the agent finished and is waiting for you), your own
  tasks in backlog or in progress, and blocked tasks. Use when the user says "what do I
  need to do today", "show my tasks", "what is waiting for my review", "daily meridian",
  or runs `/mdn-daily`.
---

## Invocation

```
/mdn-daily
```

No arguments. Always scans all active projects. Format reference: `docs/protocol.md`. Primitives used: READ, GREP. This skill never writes anything.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. If missing, tell the user to run `/mdn-init`.
2. Discover projects: READ each `<vault>/meridian/*/project.md` and keep those with `status: active` in the frontmatter.
3. For each project GREP the task lines (`/^- \[.\] #task/`) and collect three buckets, each task with its blocks:
   - **A - Review:** `status::review` (any owner). Agent finished or you asked for review; it waits for `/mdn-done`.
   - **B - Mine:** `owner::me` with `status::backlog` or `status::in-progress` (any priority).
   - **C - Blocked:** `status::blocked` (any owner), with its `**Note:**` when present.
4. Print the brief. Skip projects with no items. Within a project the order is A, then B, then C. Inside B, `priority::high` first.

```
Meridian Daily - <YYYY-MM-DD>
--------------------------------------------

<title> (<slug>)
  [review]  <slug>  <title>  [<owner>]  trace: <link, or "none">
  [mine]    <slug>  <title>  [<priority>]  <status>
  [blocked] <slug>  <title>  [<owner>]  <note, if present>
```

   - The trace is the first Markdown link of the `**Trace:**` block, printed as the link text; if the block has no link, print its first segment (`commits ...`).
   - After the brief print the actions that apply: `/mdn-done <slug>` for review items, `/mdn-run task:<slug>` for unblocked agent work the user wants started.

5. Summary line, omitting zero counts:

```
--------------------------------------------
<N> need your attention · <X> in review · <Y> mine · <Z> blocked
```

   If every bucket is empty, print `All clear: nothing needs your attention.`

## Notes

- `in-progress` agent tasks are not listed here; `/mdn-status` shows them and flags stale runs.
- Agent tasks in `backlog` are not listed: they are deferred on purpose and started with `/mdn-run`.

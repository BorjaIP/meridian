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

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. (The init guard guarantees it exists.)
2. Discover projects: for each `<vault>/meridian/*/project.md` READ only the frontmatter and keep those with `status: active`.
3. For each active project run `mdn-index.sh <project.md>` (look in `~/.config/meridian/scripts/` first, then the repository's `scripts/`; if not found, say the digest is unavailable and stop). Build the report from its output only; do not read the whole note:
   - **A - Review:** the `review=` lines (slug, owner, priority, title, trace text). Agent finished or you asked for review; it waits for `/mdn-done`.
   - **B - Mine:** the `mine=` lines (`owner::me`, backlog or in-progress).
   - **C - Blocked:** the `blocked=` lines, with the note when present.
   READ a task's full block (GREP its `slug::`) only when you need a Trace link or Note for a task the digest listed. Never read `logs/`.
4. Print the brief. Skip projects with no items. Within a project the order is A, then B, then C. Inside B, `priority::high` first.

```
Meridian Daily - <YYYY-MM-DD>
--------------------------------------------

<title> (<slug>)
  [review]  <slug>  <title>  [<owner>]  trace: <link, or "none">
  [mine]    <slug>  <title>  [<priority>]  <status>
  [blocked] <slug>  <title>  [<owner>]  <note, if present>
```

   - The trace is the `trace=` text of the digest line (the first Markdown link text, or the first segment such as `commits ...`).
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

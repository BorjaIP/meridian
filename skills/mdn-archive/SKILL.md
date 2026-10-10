---
name: mdn-archive
model: low
description: >
  Meridian archive skill. Moves the done tasks of a project, with their full Run and
  Trace blocks, from project.md to TASK_HISTORY.md in the same project folder under a
  dated section. Nothing is deleted. Use when the user says "archive tasks", "clean up
  done tasks", "move done to history", or runs `/mdn-archive`.
---

## Invocation

```
/mdn-archive [project:<slug>]
```

`project` defaults to the project whose `repo:` matches the current git toplevel; otherwise ask once. Format reference: `docs/protocol.md`. Primitives used: READ, GREP, EDIT, INSERT, WRITE.

## Rules

- Move, never delete: every archived block is written to the history file first, and removed from `project.md` only after the write is read back.
- Blocks are archived verbatim, including `**Run:**`, `**Trace:**` and `**Note:**`.
- Only `- [x]` tasks with `status::done` are moved. Review, blocked and open tasks are never touched.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. If missing, tell the user to run `/mdn-init`.
2. Resolve the project and READ `<vault>/meridian/<project>/project.md`; verify `project:` in the frontmatter.
3. Collect the done blocks: each `- [x] #task ... status::done ...` line plus all following lines indented by two or more spaces. Keep the slug and `**Title:**` of each. If there are none, report `No done tasks to archive in <slug>.` and stop.
4. Ensure `<vault>/meridian/<project>/TASK_HISTORY.md` exists. If not, WRITE it:

```markdown
---
title: Task History
project: <slug>
---

# Task History

> Archived tasks for project `<slug>`. Tasks are moved here verbatim by `/mdn-archive`.
```

5. Append at the end of the history file, with the date from `date "+%Y-%m-%d %H:%M"`:

```markdown

## Archived on <YYYY-MM-DD HH:MM>

<block 1>

<block 2>
```

6. READ the history file back and confirm that every slug is present. Only then remove each block from `project.md` (the task line, its indented lines, and one adjacent blank line). Do not touch other tasks.
7. Run `scripts/mdn-lint.sh <project.md>` (resolve it from the Meridian repository; if not found, say the check was skipped). A slug may now be reused by a new task: the history file is not linted.
8. Confirm:

```
Archived <N> task(s) from <slug>:
  - <slug>: <title>
History: <vault>/meridian/<slug>/TASK_HISTORY.md
```

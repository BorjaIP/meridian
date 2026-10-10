---
name: mdn-archive
model: low
description: >
  Meridian archive skill. Moves the done tasks of a project, with their full Run and
  Trace blocks, from project.md to the project's monthly log (logs/YYYY-MM.md) through
  mdn-log.sh. Nothing is deleted. Use when the user says "archive tasks", "clean up
  done tasks", "move done to history", or runs `/mdn-archive`.
---

## Invocation

```
/mdn-archive [project:<slug>]
```

`project` defaults to the project whose `repo:` matches the current git toplevel; otherwise ask once. Format reference: `docs/protocol.md`. Primitives used: READ, GREP, EDIT, INSERT, WRITE.

## Rules

- Move, never delete: `mdn-log.sh archive` writes the block to `logs/YYYY-MM.md` and removes it from `project.md` in one step. Never edit `project.md` or the logs by hand for this.
- Blocks are archived verbatim, including `**Run:**`, `**Trace:**` and `**Note:**`.
- Only `- [x]` tasks with `status::done` are moved. Review, blocked and open tasks are never touched.

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. (The init guard guarantees it exists.)
2. Resolve the project and READ `<vault>/meridian/<project>/project.md`; verify `project:` in the frontmatter.
3. Collect the done blocks: each `- [x] #task ... status::done ...` line plus all following lines indented by two or more spaces. Keep the slug and `**Title:**` of each. If there are none, report `No done tasks to archive in <slug>.` and stop.
4. Resolve `mdn-log.sh` (`~/.config/meridian/scripts/` first, then the repository's `scripts/`). If it is missing, say archiving is unavailable and stop; do not fall back to hand editing.
5. For each done slug run `mdn-log.sh archive <vault>/meridian/<project> <project.md> <slug>`. Exit 0: archived. Exit 3 (task missing or not done) or 4 (already archived in that month): report the slug and the script message, skip that task, and keep going. Never retry by hand.
6. READ `project.md` back and confirm the archived slugs are gone.
7. Run `mdn-lint.sh <project.md>` (look in `~/.config/meridian/scripts/` first, then the repository's `scripts/`; if not found, say the check was skipped). A slug may now be reused by a new task: logs are not linted.
8. Confirm:

```
Archived <N> task(s) from <slug>:
  - <slug>: <title>
Skipped <M>: <slug> (<reason>)        (only when M > 0)
Logs: <vault>/meridian/<slug>/logs/
```

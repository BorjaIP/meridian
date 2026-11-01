---
name: mdn-done
model: low
description: >
  Meridian review-closing skill. The human accepts a task that is in review, marking it
  done with an optional review note, or sends it back to in-progress with a reason. Use
  when the user says "mark as done", "accept this task", "close the task", "I reviewed
  it", "reopen the task", or runs `/mdn-done`.
---

## Invocation

```
/mdn-done <slug> [project:<slug>] [note:"review comment"]
/mdn-done <slug> [project:<slug>] reopen:"reason"
```

The format and the state machine are defined in `docs/protocol.md`. Primitives used: READ, GREP, EDIT, INSERT.

## Rules

- This is the human's decision. Run it only when the user asks for it; never close a task on your own initiative.
- Never invent verification. Write only the comment the user gave. Do not claim that tests passed or that the work was checked.
- Never modify `**Run:**` or `**Trace:**`, except that a reopen keeps them untouched.
- All text written to the vault is in English.

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. (The init guard guarantees it exists.)
2. Resolve the project: the `project:` argument; otherwise the project whose `repo:` matches the current git toplevel; otherwise ask once. READ `<vault>/meridian/<project>/project.md` and verify `project:` in the frontmatter.
3. GREP `slug::<slug>` among the task lines. If not found, report it and stop. Read the task's status, owner and blocks.

### Close (default)

4. Validate the transition:
   - `owner::agent`: the status must be `review`. Any other status: report it and stop (`backlog` and `in-progress` tasks are executed with `/mdn-run`; `blocked` tasks go back to `backlog` by editing the note).
   - `owner::me`: the status may be `review`, `backlog` or `in-progress`.
   - Already `done`: report it and stop.
5. For `owner::agent`, the task must have a `**Trace:**` block. If it is missing, refuse and tell the user the run is incomplete; suggest `/mdn-run task:<slug>`.
6. EDIT the checkbox `- [ ]` to `- [x]` and `status::<old>` to `status::done`.
7. If the user gave a comment, INSERT `  **Note:** <comment>` as the last block of the task (after Trace). Otherwise add nothing.

   **Text safety.** Before writing any title, description, acceptance, note or reason into a vault note or log, wrap every tag-like placeholder such as `<branch-name>`, `<name>` or `</x>` in backticks, unless it is already inside backticks. Obsidian reads a bare `<word>` as an unclosed HTML tag and stops rendering everything below it. Plain text like `a < b` needs no change. `mdn-log.sh` applies this rule to log text by itself; `mdn-lint.sh` reports any that slipped through.

### Reopen (`reopen:"reason"`)

4. The task must be `owner::agent status::review`. Otherwise report its state and stop.
5. EDIT `status::review` to `status::in-progress`; keep the checkbox `[ ]`, and keep the `**Run:**` and `**Trace:**` blocks unchanged so a later `/mdn-run task:<slug>` resumes with the original `started` and `base`.
6. INSERT `  **Note:** Reopened: <reason>` as the last block of the task. The **Text safety** rule in the accept flow above applies to the reason too.

### Finish

8. READ the note back and confirm the task line, checkbox and note. Run `scripts/mdn-lint.sh <project.md>` (look in `~/.config/meridian/scripts/` first, then the repository's `scripts/`; if not found, say the check was skipped) and fix any diagnostic that points at this task.
9. Log with `mdn-log.sh event <vault>/meridian/<project> done <slug>` when accepted, or `reopened <slug> "<reason>"` when sent back. Logging rule: look for `mdn-log.sh` in `~/.config/meridian/scripts/` first, then the repository's `scripts/`. If it is missing or fails, print a one-line warning and continue; logging must never fail or block the command.
10. Reply in one or two lines: slug, new status, and for a reopen the command to resume it: `/mdn-run task:<slug>`.

## Edge cases

| Case | Handling |
|---|---|
| Slug not found | Report it; do not guess a similar slug. |
| Agent task in review without Trace | Refuse; the run did not finish. |
| `owner::me` task without Run or Trace | Allowed to close; the protocol does not require them. |
| Several `**Note:**` lines | Append another; never overwrite an earlier one. |

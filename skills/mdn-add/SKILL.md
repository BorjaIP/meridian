---
name: mdn-add
model: low
description: >
  Meridian task creation skill. Adds a deferred task (agent or human) to the backlog of a
  Meridian project without executing it. Use when the user says "add a task", "create a
  task", "I need to track this", "add this to the project", "queue this for later", or
  runs `/mdn-add`.
---

## Invocation

```
/mdn-add "<title or description>" [project:<slug>] [owner:me|agent] [type:feature|fix|research|chore] [priority:high|medium|low] [acceptance:"..."]
```

Only the description is required. Everything else is inferred without asking questions.

| Argument | Default |
|---|---|
| `project` | The project whose `repo:` matches the current git toplevel; otherwise ask once. |
| `owner` | `agent` |
| `type` | Inferred: fix or bug words -> `fix`; investigate, review, audit -> `research`; add, create, implement, build -> `feature`; otherwise `chore`. |
| `priority` | `medium`; urgent, critical, asap, blocker -> `high`; eventually, optional, nice to have -> `low`. |

The task format is defined in `docs/protocol.md`. Primitives used: READ, GREP, INSERT.

## Rules

- This skill only records a task. It never executes it, never creates other files, and never changes the state of existing tasks.
- A new task always starts as `status::backlog` with a `[ ]` checkbox, for both owners.
- All text written to the vault is in English, regardless of the language of the input.
- Ask at most one question, and only when the project cannot be resolved.

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. (The init guard guarantees it exists.)
2. Resolve the project (see the table above). READ `<vault>/meridian/<project>/project.md` and verify `project:` in the frontmatter. (The init guard guarantees the file exists.)
3. Build the fields:
   - **Title:** imperative phrase, at most 80 characters.
   - **Description:** one sentence (at most 120 characters) stating what and why.
   - **Acceptance:** the user's criteria; for agent tasks without any, write 1 to 3 short measurable criteria inferred from the title. Optional for `owner::me`.
   - **Slug:** 2 to 5 words, kebab-case, pattern `^[a-z0-9]+(-[a-z0-9]+)*$`. GREP `slug::<slug>` in the note; on collision append `-2`, `-3`.
4. INSERT at the end of the `## Tasks` section (after the last task block, preceded by one blank line):

```markdown
- [ ] #task owner::<owner> status::backlog priority::<priority> type::<type> slug::<slug>
  **Title:** <title>
  **Description:** <description>
  **Acceptance:** <acceptance>
```

5. READ the note back and confirm the line is present, then run `scripts/mdn-lint.sh <project.md>` (resolve it from the Meridian repository). Fix any diagnostic that points at the new task. If the script is not found, say the check was skipped.
6. Confirm:

```
Task added to <project>: "<title>" [owner::<owner> status::backlog type::<type> priority::<priority> slug::<slug>]
Next:
  agent task -> /mdn-run task:<slug>
  my task    -> /mdn-daily shows it; /mdn-done <slug> closes it
```

## Edge cases

| Case | Handling |
|---|---|
| Slug collides | Append `-2`, `-3`. |
| `## Tasks` section missing | Append it at the end of the note, then the task. |
| User wants the work started now | Suggest `/mdn-run "<description>"`, which records and executes in one step. |

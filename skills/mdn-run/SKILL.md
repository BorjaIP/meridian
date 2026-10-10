---
name: mdn-run
model: medium
description: >
  Meridian execution skill and the single trigger of the ODD flow. Records a task in the
  Meridian project note before work starts, runs the work through the gentle-ai ODD
  workflow in the main thread, then completes the Run and Trace metadata from git/gh and
  moves the task to review. Accepts a free-text description, `task:<slug>` to run or
  resume an existing task, or `next` for the first agent backlog task. Use when the user
  says "run this", "implement this and track it", "run the next task", "resume the task",
  "retoma la feature", or runs `/mdn-run`.
---

## Invocation

```
/mdn-run "<description>" [project:<slug>] [priority:high|medium|low] [type:feature|fix|research|chore]
/mdn-run task:<slug> [project:<slug>]
/mdn-run next [project:<slug>]
```

| Form | Meaning |
|---|---|
| `"<description>"` | Create a new task and run it. Defaults: `priority::medium`, `type` inferred. |
| `task:<slug>` | Run an existing `owner::agent` task in `backlog`, or resume one `in-progress`. |
| `next` | First `owner::agent status::backlog` task in the project. |

The format of the project note and its blocks is defined in `docs/protocol.md`. Primitives used below: READ, GREP, EDIT (inline field or checkbox), INSERT (block after a line), WRITE.

## Rules

- Run in the main thread. Never run this skill as a subagent, and never launch gentle-ai as a subagent. ODD may delegate on its own; that is its decision.
- Never run `gentle-ai review mode` or any receipt-driven development toggle.
- Never set `status::done`. Only the human does that, from `review`.
- Metadata (dates, branch, commits, diffstat, PR, odd documents) comes from `mdn-trace.sh`, never from your own recollection.
- All text written to the vault is in English.

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

### 1. Resolve config, project and repo

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. Take the optional `delivery:` value (a free-text sentence such as "single PR; I accept size:exception"). (The init guard guarantees the config exists.)
2. Project: the `project:` argument; otherwise the project whose frontmatter `repo:` equals `git rev-parse --show-toplevel` of the current directory. If several or none match, ask once which project.
3. READ `<vault>/meridian/<project>/project.md` and verify `project:` in the frontmatter.
4. Repository: the note's `repo:`; otherwise the current git toplevel. If neither exists, ask the user once for the path and stop until answered.
5. Resolve `mdn-trace.sh` and `mdn-lint.sh`: look in `~/.config/meridian/scripts/` first, then in the `scripts/` folder of the Meridian repository. If a script is not found, continue and say which check was skipped.

### 2. Select the task

- **New description:** derive a kebab-case slug (2 to 5 words, `^[a-z0-9]+(-[a-z0-9]+)*$`) and make it unique: GREP `slug::<slug>` in the note, and check that `<repo>/odd/tasks/<slug>.md` does not exist; on collision append `-2`, `-3`.
- **`task:<slug>`:** GREP the task line. It must be `owner::agent` and `backlog` or `in-progress`. Otherwise report its state and stop.
- **`next`:** first `owner::agent status::backlog` line. If none, report that and stop.

An `in-progress` task with a `**Run:**` block is a **resume**: keep its original `started` and `base`, skip step 3, and tell ODD to resume the feature `<slug>` ("retoma la feature <slug>").

### 3. Start: record before executing

1. Run `mdn-trace.sh start <repo>`. Save its full output to a scratch file (it is the snapshot you pass to `finish`). Keep `branch`, `base`, `started`.
2. If `git status --porcelain` shows uncommitted or untracked changes other than under `.atl/` and `odd/` (tooling folders, not user work), record `dirty tree at start` in a `**Note:**` line. Do not stash, reset or clean anything.
3. Write the task to `project.md`:
   - New task: append under `## Tasks` the line `- [ ] #task owner::agent status::in-progress priority::<p> type::<t> slug::<slug>` with `**Title:**` and `**Description:**` (and `**Acceptance:**` when the user gave one).
   - Existing backlog task: EDIT `status::backlog` to `status::in-progress`.
   - Add `  **Run:** started <started> · ended · repo <repo> · branch <branch> · base <base>` after the existing blocks.
4. READ the note back and confirm the line and the Run block are there. Run `mdn-lint.sh <project.md>`; fix any diagnostic before continuing.

### 4. Execute with ODD

Do the work in this thread. The gentle-ai ODD workflow applies automatically; treat the request as an explicit implementation request. Build the working prompt from the Title, Description and Acceptance, and add:

- "Use `<slug>` as the ODD feature name (`odd/tasks/<slug>.md`)."
- The `delivery:` sentence from the config, verbatim, when present.

Follow ODD as it dictates (exploration, task document, tests, work-unit commits). Do not push or open a pull request unless the user or ODD's delivery strategy says so.

If ODD asks the user a question, wait for the answer. Never answer for the user.

### 5. Finish: complete the metadata

Run `mdn-trace.sh finish <repo> <base> <snapshot-file> --slug <slug> --pr` (use `--pr` only when a remote exists; the script tolerates a missing `gh`). Then update the note:

1. EDIT the Run block: fill `ended <ended>` and set `branch` to the `branch` printed by `finish` (the branch the work ended on; it can differ from the branch at start).
2. INSERT `**Trace:**` after the Run block, segments joined by ` · `:
   - For each `odd_doc` (the slug document first): `[<relative path>](<unc_link>)`.
   - `engram odd/<slug>/tasks`, only when an odd document exists. If the real document name differs from the slug (the model ignored it), use the detected name and record it, e.g. `engram odd/<real-name>/tasks`.
   - `commits <shas separated by ", ">` from `commits`; write `commits` with nothing after it if there are none.
   - `PR <value>` when `pr` is non-empty.
   - When no odd document was created (small task): omit the link and engram segments and add `diffstat <diffstat_committed>`; add the uncommitted diffstat when non-empty.
3. EDIT `status::in-progress` to `status::review`. Keep the checkbox `[ ]`.
4. If ODD stopped on an unresolved question or a failure instead: set `status::blocked`, still write `ended` and the Trace with whatever exists, and add `  **Note:** <one-line reason>`.
5. READ back and run `mdn-lint.sh <project.md>`.

### 6. Report

Reply briefly: task title and slug, final status, what changed in one or two lines, and the trace (odd document path, commits, diffstat, PR). Say that the task is waiting for the human review and that `/mdn-done` (or editing the note) closes it.

## Edge cases

| Case | Handling |
|---|---|
| ODD created no document | Trace has commits and diffstat only; no engram topic. |
| Model ignored the slug | Use the changed odd document `finish` reports and record its real name. |
| Session interrupted | The task stays `in-progress` with its Run block. `/mdn-run task:<slug>` resumes it and keeps the original `started` and `base`. |
| ODD asks a question | Wait for the user; do not answer or assume. |
| Dirty tree at start | Note it; never stash, reset or clean. |
| Repository unknown | Ask once, then stop until answered. |
| `finish` reports no commits and no changes | Still move to `review`, with a Trace that says `commits` and a `**Note:**` that nothing changed. |

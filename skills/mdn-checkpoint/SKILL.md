---
name: mdn-checkpoint
model: low
description: >
  Meridian progress-memory skill. Writes a session checkpoint to
  `checkpoints/checkpoint-<date>.md`, indexes it in `PROGRESS.md`,
  runs `/clear`, and resumes the session from the checkpoint. Use when the
  context is getting long (past ~70% usage), when the user says "save a
  checkpoint", "checkpoint the session", "save progress", "summarize and
  continue", or when invoked by the Agent Loop orchestrator via
  `/mdn-checkpoint`.
---

## Role

`mdn-checkpoint` is the third autonomous role of **Agent Loop Mode** (see
`docs/agent-loop.md`). It keeps long loops alive by periodically compressing
session state into a durable file and resetting the conversation context.

Unlike `mdn-reviewer` and `mdn-generator`, this skill can be invoked in any
session — not only inside an Agent Loop run. Any long-running Meridian session
benefits from it.

## Invocation

```
/mdn-checkpoint [project:<slug>] [note:"<one-line summary>"]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `project` | no | — | Meridian project slug. If given, checkpoints live inside the project folder. If omitted, they live at vault root. |
| `note` | no | auto-generated | Optional one-line label for the index entry. If omitted, the skill derives one from the checkpoint body. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Compute
a timestamp string `<STAMP>` of the form `YYYY-MM-DD-HHMM` from the current
local time. If the config file is missing: tell user to run `/mdn-init` and stop.

### Step 1 — Resolve the checkpoints directory and progress index
- If `project:<slug>` is given:
  - Verify `<vault>/meridian/<slug>/PROJECT.md` exists and has `project: <slug>`
    in frontmatter. If not: warn and fall back to vault root.
  - `CHECKPOINTS_DIR = <vault>/meridian/<slug>/checkpoints/`
  - `PROGRESS_INDEX = <vault>/meridian/<slug>/PROGRESS.md`
- Otherwise:
  - `CHECKPOINTS_DIR = <vault>/checkpoints/`
  - `PROGRESS_INDEX = <vault>/PROGRESS.md`

Create `CHECKPOINTS_DIR` if it does not exist. The index file `PROGRESS.md`
lives at the **project root** (next to `PROJECT.md`), not inside
`checkpoints/`.

### Step 2 — Summarize the current session
Produce a structured summary of the current conversation and working state. The
summary is generated **by this skill itself** — the user does not have to type
anything. Internally, answer:

1. **Accomplished** — what concretely changed (files written, tasks moved to
   done, decisions made, artifacts produced). Be specific — include file paths
   and task titles.
2. **Current State** — where the work is right now: what is in-progress, what
   open questions remain, what was just about to happen next, any partial
   output.
3. **Next Steps** — the smallest set of steps needed to pick up where we left
   off. Written as an ordered list the resumed session can act on immediately.

If inside an Agent Loop run, also capture:
- Active mode (`iterations` or `goal`).
- For `iterations` mode: the current `Remaining` counter from `PROJECT.md`.
- For `goal` mode: the active goal title from `GOAL.md`.

### Step 3 — Write the checkpoint file
Write `<CHECKPOINTS_DIR>/checkpoint-<STAMP>.md` with this exact shape:

```markdown
---
date: <full ISO datetime>
project: <slug or "-">
mode: iterations | goal | -
iterations_remaining: <n>        # only if applicable
goal: <goal title>               # only if applicable
---

# Checkpoint — <STAMP>

> One-line summary: <the single sentence that will also go into PROGRESS.md>

## Accomplished
- <bullet>
- <bullet>

## Current State
- <bullet>
- <bullet>

## Next Steps
1. <step>
2. <step>
3. <step>
```

The "one-line summary" is either the explicit `note:` argument or the first
concrete accomplishment phrased in under ~80 characters.

### Step 4 — Update the progress index
Ensure `<PROGRESS_INDEX>` exists. Create it with this header if not:

```markdown
# Progress — <slug or "vault">

> Index of all Meridian session checkpoints, newest first.
> Checkpoint files live in `checkpoints/`.

```

Prepend (not append — newest first) this line immediately under the header
block:

```markdown
- [[checkpoints/checkpoint-<STAMP>]] — <one-line summary>
```

### Step 5 — Emit the sentinel for the orchestrator
Print the following machine-readable sentinel as the final output of this skill:

```
checkpoint-result: file=<absolute-path-to-checkpoint> index=<absolute-path-to-PROGRESS.md> resume_with="Let us continue our work @<vault-relative-path-to-checkpoint>"
```

Where:
- `file` is the absolute path to `<CHECKPOINTS_DIR>/checkpoint-<STAMP>.md`
- `index` is the absolute path to `<PROGRESS_INDEX>` (`PROGRESS.md` at the
  project root)
- `resume_with` is the exact string the orchestrator should issue after `/clear`
  (vault-relative path, using `@` prefix for context loading)

**When invoked standalone (not via `mdn-loop`):** after the sentinel line, also
print user-facing instructions:

```
✓  Checkpoint saved → <CHECKPOINTS_DIR>/checkpoint-<STAMP>.md
✓  Indexed in        → <PROGRESS_INDEX>

To clear the context and resume from this checkpoint, run:
  /clear
Then paste:
  Let us continue our work @<vault-relative-path-to-checkpoint>
```

**When invoked by `mdn-loop`:** the orchestrator reads the `checkpoint-result:`
line, issues `/clear` itself (the orchestrator's turn has this privilege), then
immediately issues the `resume_with` message. The skill does not run `/clear` —
it cannot, because a skill runs inside the current turn and the CLI command
executes outside the model.

## When to auto-trigger

Inside Agent Loop Mode, the orchestrator should call `/mdn-checkpoint
project:<slug>` whenever **both** of these are true at the end of an iteration:

- Estimated context usage is above ~70%.
- There is at least one full iteration's worth of remaining work (otherwise
  finishing normally is cheaper than checkpointing).

Outside the loop, users can call it manually whenever a session starts to feel
crowded, or before switching to a new task area.

## Meridian protocol reference

- This skill writes only inside `<CHECKPOINTS_DIR>` and to `<PROGRESS_INDEX>`. No task states are mutated.
- The vault remains the single source of truth — checkpoints are a courtesy for
  the conversation model, not authoritative project state.

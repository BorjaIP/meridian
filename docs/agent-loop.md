# Agent Loop Mode

> A fully autonomous operating mode for Meridian where the human is removed from the inner loop. Specialized sub-agents take over the roles the human normally fills (review, verification, task generation) and keep the work moving until a pre-agreed stop condition is reached.

---

## Why a new mode?

The default Meridian workflow requires a human in the loop for three things:

1. Reviewing plans (`status::review → approved`)
2. Verifying execution (`type::review` checkpoints after `mdn-run`)
3. Deciding what to work on next (writing new backlog tasks)

That design is deliberate — it keeps the human in control. But there are workflows where the user wants to **hand the project to Meridian and walk away**: long-running research, bulk refactors, "keep iterating until this app exists" goals, or simply running experiments overnight.

Agent Loop Mode makes this possible without changing the underlying protocol. Every artifact it produces is still a normal Meridian task, plan, or note. A human can jump back in at any time by simply closing the loop and resuming the standard flow.

---

## Activation

The user activates the mode with the `/mdn-loop` skill:

```
/mdn-loop project:<slug> type:iterations count:20
/mdn-loop project:<slug> type:goal goal:"build a CLI that can parse Meridian tasks and print a status table"
```

Or via a natural instruction that triggers the skill:

> "Activate Agent Loop mode for project `X`, type: iterations, 20 iterations."

The **`mdn-loop` skill is the orchestrator**. It does not do work itself — it spawns sub-agents (`Task` tool in Claude Code, equivalent in other adapters) for every unit of work. This keeps the orchestrator's context window small and lets the loop run for a long time without degrading.

Two stop conditions are supported, chosen at activation time:

| Type | Input | Stop condition |
|---|---|---|
| `iterations` | An integer `N` | Loop halts after exactly `N` iterations. Counter lives in `PROJECT.md > ## Iterations`. |
| `goal` | A free-form objective | Loop halts when the **Agent Reviewer** declares the goal reached. Goal lives in `GOAL.md`. |

Only one Agent Loop mode can be active per project at a time.

---

## The three autonomous roles

Agent Loop Mode introduces three specialized sub-agents. Each is implemented as a Meridian skill (`mdn-reviewer`, `mdn-generator`, `mdn-checkpoint`) so they can be invoked standalone or from inside the loop.

### 1. Agent Reviewer — stands in for the human

The Reviewer impersonates `owner::me` for every task that normally waits on a human. It:

- Scans `## Tasks` for every `owner::me status::review` task (both plan-review checkpoints from `mdn-plan` and verification checkpoints from `mdn-run`).
- For each one, reads the linked artifact (plan note, source files, test output…), re-runs the acceptance criteria mentally, and **writes a report block to `REVIEW.md`**.
- Based on its verdict, transitions the task to `done`, `blocked`, or inserts a new `owner::agent status::backlog` correction task.
- **In goal mode only**, after processing all review tasks it compares the accumulated work against `GOAL.md` and decides whether to stop the loop.

The Reviewer is the **only** role that can stop a goal-mode loop. It must therefore be capable of reasoning about what "done" looks like for an arbitrary goal — treated as a human-like judge, not a rule engine.

### 2. Agent Generator — keeps the backlog alive

Without a human writing tasks, the backlog would drain and the loop would starve. The Generator refills it. It reads:

- The current backlog
- Recently completed tasks
- `REVIEW.md` (what the Reviewer thought of previous work)
- `GOAL.md` **or** the remaining iteration count
- The project note itself

…and emits fresh `owner::agent status::backlog` tasks that move the project forward. Tasks follow the exact same format as tasks written by `/mdn-add`, so every existing Meridian skill keeps working.

### 3. Progress Memory — keeps the loop alive

Long loops saturate the orchestrator's context. Past ~70% usage, responses begin to degrade. The Progress Memory skill (`mdn-checkpoint`) is the answer:

- Produces a structured checkpoint file at `checkpoints/checkpoint-<date>.md` summarizing what happened, the current state, and the next steps.
- Appends a one-line entry to `PROGRESS.md` (the index).
- Emits a `checkpoint-result:` sentinel line with the file path and the resume message.

The `/clear` command and the resume message are **the orchestrator's responsibility**, not the skill's. The skill runs inside the current model turn and cannot force the CLI to reset the conversation — only the orchestrator's top-level turn can issue `/clear`. After parsing the `checkpoint-result:` sentinel, `mdn-loop` issues `/clear` and then the `resume_with` message from the sentinel.

The orchestrator triggers this automatically between iterations once context usage crosses 70%. Users can also run it manually at any time — in that case, the skill prints user-friendly instructions for running `/clear` themselves.

---

## Files written by the mode

All files live inside the project folder at `<vault>/meridian/<slug>/`:

```
<vault>/meridian/<slug>/
  PROJECT.md                 ← gains `## Iterations` section in iterations mode
  GOAL.md                    ← goal mode: one active goal + history
  REVIEW.md                  ← one report block per reviewed task
  PROGRESS.md                ← index of every checkpoint
  checkpoints/
    checkpoint-<date>.md     ← individual session snapshots
```

All files except `PROJECT.md` are created on demand by the skill that owns
them. `mdn-init` is unchanged.

### `GOAL.md` format

```markdown
# Goals — <project slug>

## <YYYY-MM-DD HH:MM> — <one-line goal title>
**Status:** active | reached | abandoned
**Goal:** <full statement of the objective>
**Started:** <NOW>
**Reached:** <filled by Reviewer when status flips to reached>
**Iterations used:** <count, filled by Reviewer>

<optional notes>
```

Only one goal may carry `status: active` at a time. Past goals are kept as history.

### `REVIEW.md` format

Each reviewed task becomes one block appended to the file:

```markdown
## <YYYY-MM-DD HH:MM> — <reviewed task title>
**Task:** <linked task title>
**Artifact:** [[...]]                  (if any)
**Verdict:** approved | blocked | needs-correction
**Analysis:** <2–6 lines of reasoning>
**Next action:** <mark done | create correction task | block>
```

At the end of every goal-mode Reviewer pass, one additional block is written:

```markdown
## GOAL CHECK <NOW>
**Goal:** <goal title>
**Verdict:** reached | not-reached
**Rationale:** <why>
**Next focus (if not reached):** <one-line hint for the Generator>
```

### `PROGRESS.md` format

```markdown
# Progress — <project slug>

- [[checkpoint-2026-04-05-1430]] — Finished initial scaffolding, CLI parser working.
- [[checkpoint-2026-04-05-1615]] — Task dispatch implemented, 3 failing tests.
- ...
```

### `checkpoints/checkpoint-<date>.md` format

```markdown
---
date: <NOW>
project: <slug>
mode: iterations | goal
iterations_remaining: <n>     (iterations mode only)
goal: <goal title>            (goal mode only)
---

# Checkpoint — <date>

## Accomplished
- ...

## Current State
- ...

## Next Steps
- ...
```

### `PROJECT.md > ## Iterations` section

Only added when a loop is started in `type:iterations` mode:

```markdown
## Iterations
- **Mode:** iterations
- **Total:** 20
- **Remaining:** 14
- **Started:** 2026-04-05 14:30
- **Last iteration:** 2026-04-05 16:02
```

---

## Orchestration loop (executed by the main session)

Pseudocode for what the main session (the orchestrator) does once the mode is activated:

```
initialize:
  if type == iterations: write ## Iterations (total=N, remaining=N)
  if type == goal:       append new goal entry to GOAL.md (status=active)

loop:
  # 1. Make sure there is work to do
  if no owner::agent tasks with status in {backlog, approved}:
    spawn sub-agent → /mdn-generator project:<slug> mode:<type> target:3

  # 2. Execute one task
  pick the first owner::agent status::backlog task
  spawn sub-agent → /mdn-run project:<slug> task:"<title>"
    (mdn-run's existing "simple flow" — no human approval needed)

  # 3. Clear the review queue the way a human normally would
  spawn sub-agent → /mdn-reviewer project:<slug> mode:<type>

  # 4. Protect the context before the next iteration
  if estimated context usage > 70%:
    spawn sub-agent → /mdn-checkpoint project:<slug>

  # 5. Stop condition
  if type == iterations:
    decrement ## Iterations.Remaining
    if Remaining == 0: break
  if type == goal:
    if last REVIEW.md GOAL CHECK verdict == reached: break

finalize:
  print summary: iterations run, tasks done, REVIEW.md path, GOAL.md status
```

Key points:

- Every numbered step above is a **sub-agent invocation**, not inline work. The orchestrator holds only the loop variables (slug, mode, remaining, stop flag). This is what keeps the context small.
- `mdn-run` already supports a "simple flow" (`task:<title>`) that skips the review/approve hop — see `skills/mdn-run/SKILL.md`. Agent Loop uses this directly; no new execution skill is introduced.
- If the Generator produces a complex task that warrants a plan, the orchestrator can spawn `mdn-plan` first, then let the Reviewer approve it via `mdn-approve` on the next pass. This reuses the existing planning machinery without bypassing it.

---

## Stop conditions

### Iterations mode

- `## Iterations.Remaining` is the single source of truth.
- The orchestrator decrements it once per full iteration (after the Reviewer pass).
- Hits zero → orchestrator exits cleanly, writes a final `## Iterations` update with `**Ended:** <NOW>`.
- Manual abort: the user can edit `Remaining` to `0` and the loop will exit at the top of the next iteration.

### Goal mode

- Only the Reviewer can declare the goal reached.
- At the end of each Reviewer pass, the Reviewer reads `GOAL.md` plus all `status::done` tasks produced during the current loop, and writes a `## GOAL CHECK` block to `REVIEW.md`.
- Verdict `reached` → Reviewer updates the active goal entry in `GOAL.md` to `status: reached`, fills `**Reached:**` and `**Iterations used:**`. The orchestrator sees this on its next poll and exits.
- Verdict `not-reached` → the block must include a `**Next focus:**` line, which the Generator reads on the following iteration to decide what tasks to emit.

Starting a new goal after a previous one is simply another invocation of the mode with `type:goal` — the previous entry stays in `GOAL.md` as history.

---

## Relationship to existing Meridian skills

Agent Loop mode does **not** replace or fork the existing protocol. Every existing skill works unchanged:

| Skill | Role under Agent Loop |
|---|---|
| `mdn-init` | Unchanged. Creates projects the same way. |
| `mdn-add` | Still usable by the human before or after a loop. |
| `mdn-load` | Still usable to inject external plans. |
| `mdn-plan` | Called by the orchestrator when a task warrants a plan. |
| `mdn-approve` | Called **by the Reviewer** when it wants to approve a plan the same way a human would. |
| `mdn-run` | Called every iteration (simple flow). |
| `mdn-status` / `mdn-daily` | Still usable — the loop produces normal task states. |

The only net-new skills are `mdn-reviewer`, `mdn-generator`, and `mdn-checkpoint`.

---

## Safety and guarantees

- **Read-only exits:** the loop writes only inside `<vault>/meridian/<slug>/`. Task execution happens in whatever working directory the user chose before activation — the Reviewer will not touch files outside the vault.
- **Observability:** the user can read `REVIEW.md`, `GOAL.md`, and `PROGRESS.md` at any time to see exactly what the loop has been doing.
- **Resumability:** if the session crashes, the vault is the single source of truth. Re-activating the mode picks up from the current `## Iterations.Remaining` and the active goal.
- **Pause:** the user can edit `## Iterations.Remaining` to `0` or set the active goal entry to `status: abandoned` to stop the loop cleanly.
- **No silent human approvals outside the loop:** the Reviewer's approvals are always recorded in `REVIEW.md` with explicit rationale. Nothing in the project state is mutated without an audit trail.

---

## Example — iterations run

```
User: Activate Agent Loop mode for project meridian, 3 iterations.

Session:
  → writes ## Iterations (total:3, remaining:3)
  → iteration 1:
      generator (backlog was empty): +2 tasks
      run:       task "Add XDG config validator" → done
      reviewer:  approves the verify checkpoint, writes 1 REVIEW.md block
      remaining: 2
  → iteration 2:
      run:       task "Write validator tests" → done
      reviewer:  verdict needs-correction, inserts correction task, writes REVIEW.md
      remaining: 1
  → iteration 3:
      run:       task "<correction task>" → done
      reviewer:  approves, writes REVIEW.md
      remaining: 0
  ✓ loop exited after 3 iterations. See REVIEW.md.
```

## Example — goal run

```
User: Activate Agent Loop mode for project meridian, goal: "Build a minimal CLI
      that parses PROJECT.md tasks and prints them as a table."

Session:
  → writes GOAL.md entry (status: active)
  → iteration 1..N:
      generator → run → reviewer (writes per-task blocks + GOAL CHECK block)
      once GOAL CHECK verdict == reached, exits
  ✓ goal reached after 7 iterations. GOAL.md updated.
```

---

## Related

- Protocol specification: [[Meridian]]
- Concepts: [[concepts]]
- Standard workflow: [[workflow]]
- Skills: `mdn-loop` (orchestrator), `mdn-reviewer`, `mdn-generator`, `mdn-checkpoint`

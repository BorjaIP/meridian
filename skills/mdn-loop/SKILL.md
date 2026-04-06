---
name: mdn-loop
model: medium
description: >
  Meridian Agent Loop orchestrator. Runs the autonomous agent loop for a project
  in either iterations mode (fixed count) or goal mode (run until objective is
  met). Spawns mdn-generator, mdn-run, mdn-reviewer, and mdn-checkpoint as
  sub-agents and manages the stop condition. Use when the user says "activate
  agent loop", "run agent loop", "start autonomous mode", or invokes
  `/mdn-loop`.
---

## Role

`mdn-loop` is the **orchestrator** for Agent Loop Mode (see `docs/agent-loop.md`).
It does not do work itself — it spawns specialized sub-agents for every unit of
work and manages state in `PROJECT.md`. This keeps the orchestrator's context
window small and lets the loop run for a long time.

Two stop conditions are supported:

| Type | Stop condition |
|---|---|
| `iterations` | Loop halts after exactly `count` iterations. Counter lives in `PROJECT.md > ## Iterations`. |
| `goal` | Loop halts when the Agent Reviewer declares the goal reached. Goal lives in `GOAL.md`. |

Only one Agent Loop run can be active per project at a time.

## Invocation

```
/mdn-loop project:<slug> type:iterations count:<N>
/mdn-loop project:<slug> type:goal goal:"<objective>"
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `project` | yes | — | Project slug |
| `type` | yes | — | `iterations` or `goal` |
| `count` | if `type:iterations` | — | Number of iterations to run |
| `goal` | if `type:goal` | — | Free-form goal statement |
| `checkpoint-every` | no | `5` | Run `/mdn-checkpoint` every N iterations |
| `max-iterations` | no | `50` | Hard safety cap in goal mode |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run the
standard date generation snippet → `<NOW>` (format `YYYY-MM-DD HH:MM`). If
missing: tell user to run `/mdn-init` and stop.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in
frontmatter. If missing: suggest `/mdn-init name:<slug>` and stop.

### Step 2 — Guard against concurrent loops
- `type:iterations`: check if `## Iterations` with `**Remaining:** <n>` (where
  n > 0) already exists. If so: print "An active iterations loop is already
  running (Remaining: <n>). Edit `Remaining` to 0 to abort it first." and stop.
- `type:goal`: read `<vault>/meridian/<slug>/GOAL.md` if it exists. If an
  entry with `**Status:** active` is found: print "An active goal loop is already
  running. Set it to `abandoned` first." and stop.

### Step 3 — Initialize loop state and generate Loop-ID

Generate `<LOOP-ID>` as a timestamp string of the form `YYYYMMDD-HHMM`.

**`type:iterations`:**
Upsert the `## Iterations` section in `PROJECT.md` (append after frontmatter /
before `## Sources` if section does not exist):

```markdown
## Iterations
- **Mode:** iterations
- **Total:** <count>
- **Remaining:** <count>
- **Started:** <NOW>
- **Loop-ID:** <LOOP-ID>
```

**`type:goal`:**
Ensure `<vault>/meridian/<slug>/GOAL.md` exists at the project root with
header:

```markdown
# Goals — <slug>

```

Append a new goal entry to `GOAL.md`:

```markdown
## <NOW> — <goal title (first 8 words of goal statement)>
**Status:** active
**Goal:** <full goal statement>
**Started:** <NOW>
**Loop-ID:** <LOOP-ID>
```

### Step 4 — Loop

Initialize: `ITERATION = 0`, `STOP = false`.

Repeat until `STOP == true`:

#### 4a. Make sure there is work to do
Scan `## Tasks` in `PROJECT.md` for any `- [ ]` + `owner::agent` + `status` ∈
`{backlog, approved}`. If none found:

Spawn sub-agent:
```
/mdn-generator project:<slug> mode:<type> target:3 loop-id:<LOOP-ID>
```
Wait for sub-agent to complete before continuing.

#### 4b. Execute one task
Pick the first `owner::agent status::backlog` task title from `## Tasks`.

Spawn sub-agent:
```
/mdn-run project:<slug> task:"<title>" loop-id:<LOOP-ID>
```
Wait for sub-agent to complete before continuing.

#### 4c. Clear the review queue
Spawn sub-agent:
```
/mdn-reviewer project:<slug> mode:<type> loop-id:<LOOP-ID>
```
Wait for sub-agent to complete. Capture the `reviewer-result:` output line.

#### 4d. Checkpoint if context is getting long
Increment `ITERATION`. If `ITERATION % checkpoint-every == 0`:

Spawn sub-agent:
```
/mdn-checkpoint project:<slug>
```
Wait for sub-agent to complete. Parse the `checkpoint-result:` sentinel line from
its output:
```
checkpoint-result: file=<absolute-path> index=<absolute-path> resume_with="<message>"
```
Issue `/clear` to reset the conversation context. Immediately issue the
`resume_with` message from the sentinel to reload state.

#### 4e. Evaluate stop condition

**`type:iterations`:**
1. Re-read `## Iterations.Remaining` from `PROJECT.md`.
2. Decrement: write `Remaining: <n-1>` back to `PROJECT.md`.
3. If new `Remaining == 0`:
   - Append `**Ended:** <NOW>` to the `## Iterations` block.
   - Set `STOP = true`.

**`type:goal`:**
1. Parse the `reviewer-result:` line captured in 4c. Check `goal_reached=true`.
2. If `goal_reached=true`: set `STOP = true`.
3. If `ITERATION >= max-iterations`:
   - Read `GOAL.md`, find the active goal entry, set `**Status:** abandoned`.
   - Append `**Abandoned:** <NOW> (hit max-iterations cap of <max-iterations>)`.
   - Set `STOP = true`. Print a warning.

### Step 5 — Finalize

Print a summary:

```
✓  Agent Loop completed for `<slug>`.
   Mode:            <iterations|goal>
   Iterations run:  <ITERATION>
   Tasks done:      <count of status::done tasks added during this loop>
   Loop-ID:         <LOOP-ID>
   REVIEW.md:       <vault>/meridian/<slug>/REVIEW.md
   GOAL.md:         <vault>/meridian/<slug>/GOAL.md   (goal mode only)
   Stop reason:     <iterations exhausted | goal reached | max-iterations cap | manual>
```

## Meridian protocol reference

- Orchestrator spawns sub-agents using the Task tool (Claude Code) or equivalent.
- All loop state lives in the vault — if the session crashes, re-activating the
  loop picks up from the current `## Iterations.Remaining` or active goal entry.
- The `/clear` + resume in Step 4d is the orchestrator's privilege; `mdn-checkpoint`
  only writes the artifact and emits the sentinel.
- Related skills: `mdn-generator`, `mdn-run`, `mdn-reviewer`, `mdn-checkpoint`.
- Full spec: `docs/agent-loop.md`.

---
name: mdn-reviewer
model: medium
description: >
  Meridian Agent Loop reviewer skill. Impersonates `owner::me` for every pending
  review task in a project: reads the linked artifact, analyzes whether the work
  meets the acceptance criteria, writes a structured report block to
  `REVIEW.md`, and transitions each task to `done`, `blocked`, or inserts a
  correction task. In goal mode, also reads `GOAL.md`, decides whether the
  active goal has been reached, and writes a `## GOAL CHECK` block. Use when the
  user says "review pending tasks", "run the reviewer", "clear the review queue",
  or when invoked by the Agent Loop orchestrator via `/mdn-reviewer`.
---

## Role

This skill is one of the three autonomous roles of **Agent Loop Mode** (see
`docs/agent-loop.md`). It stands in for the human reviewer so the loop can run
unattended. It is the **only** role authorized to end a goal-mode loop.

## Invocation

```
/mdn-reviewer project:<slug> [mode:iterations|goal] [goal-file:<path>] [loop-id:<id>]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `project` | yes | — | Meridian project slug. |
| `mode` | no | `iterations` | `iterations` or `goal`. Controls whether a GOAL CHECK block is produced. |
| `goal-file` | no | `<vault>/meridian/<slug>/GOAL.md` | Path to the goal file (goal mode only). At the project root. |
| `loop-id` | no | — | Loop identifier from `mdn-loop`. When present, scope task queries to tasks stamped with this `loop-id::` inline field. |

The skill can be run standalone by a human, but its primary caller is the Agent
Loop orchestrator.

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run the
standard date generation snippet → `<NOW>` (format `YYYY-MM-DD HH:MM`). If missing:
tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in frontmatter.
If missing: report "Project `<slug>` not found" and stop.

### Step 2 — Ensure REVIEW.md exists
Ensure `<vault>/meridian/<slug>/REVIEW.md` exists at the project root. Create
it with this header if newly created:

```markdown
# Review Log — <slug>

> Autonomous review reports written by the Agent Reviewer.
> One block per reviewed task. Append-only.

```

### Step 3 — Collect review tasks
Scan `## Tasks` in `PROJECT.md` for every block matching **all** of:

- `- [ ] #task`
- `owner::me`
- `status::review`

If `loop-id:<id>` was supplied, additionally filter to blocks that contain
`loop-id::<id>` on their checkbox line (tasks stamped by `mdn-run`/`mdn-generator`
during the current loop). Tasks without the field are excluded from loop-scoped
reviews but are still visible when running the skill standalone.

Parse each block to capture: checkbox line number, `**Title:**`, `**Description:**`,
`**Artifact:**` (optional), `**Depends on:**` (optional). Tasks with type::review
(verification checkpoints from `mdn-run`) and tasks from plan reviews are both in
scope.

If no review tasks are found:
- `mode:iterations` → print "No pending review tasks in `<slug>`." and stop.
- `mode:goal` → skip to Step 6 (still run the goal check).

### Step 4 — Review each task
Process tasks **in order** (top-to-bottom in the file). For each one:

#### 4a. Gather evidence
- If the block has `**Artifact:** [[<wikilink>]]`, read
  `<vault>/meridian/<slug>/plans/<plan-name>.md` (or resolve the wikilink directly).
- Look for references to the completed agent task this checkpoint was created for
  (Verify tasks from `mdn-run` immediately follow the completed task block — read
  the preceding `- [x]` block and its `**Note:**` field).
- If the task references files or commits, read them to the extent needed to
  judge completeness.

#### 4b. Form a verdict
Compare the evidence against the task's **Acceptance** criteria (on the reviewed
task or the preceding completed task). Produce one of:

| Verdict | Meaning |
|---|---|
| `approved` | Acceptance criteria are visibly met. |
| `needs-correction` | Partial — a follow-up task can fix the gap. |
| `blocked` | Work cannot proceed without human input (ambiguous spec, missing access, etc.). |

Be conservative: if unsure between `approved` and `needs-correction`, choose
`needs-correction`. The loop can afford another iteration; silently approving
broken work breaks the goal-mode stop condition.

#### 4c. Append to REVIEW.md
Append exactly this block to `<vault>/meridian/<slug>/REVIEW.md`:

```markdown
## <NOW> — <reviewed task title>
**Task:** <reviewed task title>
**Artifact:** [[<plan-name>]]          (omit line if no artifact)
**Verdict:** approved | blocked | needs-correction
**Analysis:** <2–6 lines of reasoning, concrete, no filler>
**Next action:** <mark done | create correction task: "<new title>" | block>

```

#### 4d. Apply the verdict to PROJECT.md

**approved:**
1. Check the box: `- [ ]` → `- [x]`
2. Replace `status::review` → `status::done`
3. Append `**Approved by:** Agent Reviewer on <NOW>`
4. If the review task has `type::review` and is a `Verify:` checkpoint, remove its
   row from the `## Tasks` table if present.

**needs-correction:**
1. Replace `status::review` → `status::blocked`
2. Append `**Note:** Agent Reviewer found gaps; see REVIEW.md <NOW>.`
3. Immediately below the review block, insert a new backlog task:
   ```markdown
   - [ ] #task owner::agent status::backlog type::fix priority::high
     **Title:** <correction title>
     **Description:** <concrete description of what needs fixing, derived from 4b>
     **Acceptance:** <what would satisfy the original acceptance criterion>
     **Review ref:** See REVIEW.md block "<NOW> — <reviewed task title>"
   ```
4. Upsert a corresponding row in the `## Tasks` table with status `backlog`.

**blocked:**
1. Replace `status::review` → `status::blocked`
2. Append `**Note:** Agent Reviewer blocked; see REVIEW.md <NOW>.`
3. Do **not** insert a correction task — blocked means human attention is needed.

All `PROJECT.md` edits must happen in a single sequential pass per task to avoid
line-number drift.

### Step 5 — If mode is iterations, stop here
Print a summary:

```
✓  Reviewed <n> task(s) in `<slug>`.
   approved:         <k>
   needs-correction: <k>
   blocked:          <k>
   REVIEW.md → <vault>/meridian/<slug>/REVIEW.md
```

### Step 6 — Goal check (goal mode only)
Read `<vault>/meridian/<slug>/GOAL.md`. Find the entry with `**Status:** active`.
If none: print "No active goal in GOAL.md — nothing to check." and stop.

Read the **Goal** statement from that entry. Read all `status::done` tasks from the
current project note. When `loop-id:<id>` is present, filter to tasks with matching
`loop-id::<id>` inline field — do not count tasks from prior loops or manual
human tasks. The question to answer: **does the accumulated work satisfy the goal?**

Think like a product owner, not a rule matcher:
- The goal is a statement of intent in natural language, not a checklist.
- Partial coverage is common mid-loop — the correct verdict is `not-reached` with a
  concrete next-focus hint.
- A single flawless task rarely reaches a multi-faceted goal. Look for breadth of
  coverage across the goal's components.
- When tasks have produced artifacts (code, notes, files), inspect them rather than
  relying on task titles alone.

Append this block to `REVIEW.md`:

```markdown
## GOAL CHECK <NOW>
**Goal:** <goal title>
**Verdict:** reached | not-reached
**Rationale:** <3–8 lines: what has been done, what maps to which part of the goal,
what remains (if not-reached)>
**Next focus (if not reached):** <one line, actionable, consumable by the Generator>
```

If verdict is **reached**:
1. Edit the active entry in `GOAL.md`:
   - `**Status:** active` → `**Status:** reached`
   - Append `**Reached:** <NOW>`
   - Append `**Iterations used:** <count from PROJECT.md ## Iterations, or "n/a">`
2. Print the stop signal for the orchestrator:
   ```
   ⏹  GOAL REACHED — Agent Loop should exit.
   ```

If verdict is **not-reached**:
Print:
```
↻  GOAL NOT REACHED — next focus: <hint>
```

### Step 7 — Output contract
Always end with a single line of machine-readable output for the orchestrator:

```
reviewer-result: reviewed=<n> approved=<k> corrections=<k> blocked=<k> goal_reached=<true|false|n/a>
```

## Meridian protocol reference

- State machine: `backlog → planning → review → approved → in-progress → done` (+ `blocked`).
- This skill writes to `REVIEW.md` and (in goal mode) `GOAL.md`.
- Never touches files outside `<vault>/meridian/<slug>/` except when reading
  evidence referenced by a task.

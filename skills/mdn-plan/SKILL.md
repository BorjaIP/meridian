---
name: mdn-plan
model: claude-sonnet-4-6
description: >
  Meridian planning skill. Orchestrator: finds all owner::agent status::backlog tasks with
  no Artifact field and spawns one sub-agent per task. Each sub-agent uses native Plan Mode
  (Claude EnterPlanMode, OpenCode, Cursor, etc.) to explore the codebase and generate a real
  implementation plan, then creates a Meridian index note that summarises and links to the
  plan artifact via absolute path. If method:<skill-name> is given, uses that skill instead
  of native Plan Mode. All tasks are planned in parallel by default. PROJECT.md writes are
  always sequential after sub-agents complete. After planning, each task transitions to
  status::review and a review checkpoint is created.
---

## Invocation

```
/mdn-plan project:<slug> [tasks:all|<n>] [parallel:yes|no] [method:<framework-name>]
```

| Argument | Required | Default | Description |
|---|---|---|---|
| `project` | yes | — | Meridian project slug |
| `tasks` | no | `all` | `all` or N to plan only first N |
| `parallel` | no | `yes` | `yes` = spawn sub-agents concurrently (recommended); `no` = sequential |
| `method` | no | — | Skill name to use instead of native Plan Mode. If absent: sub-agent uses its framework's native Plan Mode (Claude → EnterPlanMode, OpenCode → its plan, etc.). |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`, `model-medium` (default: `sonnet`). Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Find unplanned agent tasks
Scan `## Tasks` for blocks matching **all**:
- `- [ ] #task`
- `owner::agent`
- `status::backlog`
- NO `**Artifact:**` field in block

Extract per block: checkbox line, `**Title:**`, `**Description:**`, `**Acceptance:**` (optional), `**Depends on:**` (optional), `**Task note:**` (optional).

If none: print "No unplanned agent tasks in `<slug>`." and stop.

### Step 3 — Apply limit and print work plan
If `tasks:N`, take first N. Print:
```
Found <total> unplanned task(s) in `<slug>`. Planning <N>.
Method: <agent:model-medium | <method-name>>  |  Parallel: <yes|no>

Tasks to plan:
  1. "<title>"
```

### Step 4 — Transition to planning
Single sequential pass through `PROJECT.md`: replace `status::backlog` → `status::planning` for each selected task. Upsert row in `## Tasks` table: Status → `planning`.

### Step 5 — Generate slugs
For each task, derive plan slug from `**Title:**`:
1. Lowercase
2. Remove chars not in `[a-z0-9 -]`
3. Collapse spaces → hyphens
4. Truncate at 30 chars at word boundary
5. Strip leading/trailing hyphens

Collision check: if `<vault>/meridian/<slug>/plans/<plan-slug>.md` exists, append `-2`, `-3`, etc.

### Step 6 — Spawn plan generation sub-agents

mdn-plan is an **orchestrator**. It never generates plan content inline — always delegates.

**`parallel:yes` (default):** spawn all sub-agents at once (single message, multiple Agent tool calls). Each sub-agent works independently and writes its plan note to disk. Collect all results before Step 7.

**`parallel:no`:** spawn sub-agents one at a time, wait for each before launching the next.

#### Step 6a — Per-task sub-agent

Each sub-agent has **two phases**: (1) generate a real implementation plan using a planning tool, and (2) create the Meridian index note that summarises and links to it.

The planning tool varies by `method:`:
- **No `method:` (default):** use the **native Plan Mode** of the current agent framework (Claude Code → `EnterPlanMode`, OpenCode → its plan mode, Cursor → its plan mode, etc.). The plan file is stored wherever the framework puts it — the sub-agent records the absolute path.
- **`method:<skill-name>`:** use the named skill instead of native Plan Mode. Everything else is identical.

**Sub-agent prompt (both cases):**

Spawn an Agent sub-agent with `model: <model-medium>` and `mode: "plan"` (when using default native plan mode). The prompt:

```
You have two phases for this task.

Task:
  Title: <task title>
  Description: <task description>
  Acceptance: <acceptance criteria or "not specified">

<IF task has **Task note:** field:>
This task has a detailed specification file. Read it before doing anything else:
  <vault>/meridian/<slug>/tasks/<task_note_slug>.md
Use it as the primary source of truth for architecture, acceptance criteria, and context.
<ENDIF>

Project dir: <project working directory>

─── Phase 1: Generate implementation plan ───

<IF default (no method):>
Use your native Plan Mode to create an implementation plan for this task. Explore the
codebase, understand the project structure, identify relevant files, and produce a
detailed plan. The plan file will be stored wherever your framework places it — record
its absolute path.
<ENDIF>

<IF method:<skill-name>:>
Use the skill "<skill-name>" to generate a plan for this task. The plan file will be
stored wherever that skill places it — record its absolute path. If the skill fails or
produces no file, fall back to native Plan Mode.
<ENDIF>

The plan must reflect actual knowledge of the codebase — not just restate the task
description.

─── Phase 2: Create Meridian index note ───

After the plan exists, read it and create the Meridian index note at:

  <vault>/meridian/<slug>/plans/<plan-slug>.md

Use this structure (replace Templater expressions with literal values):

---
title: "Plan: <task title>"
created: <NOW>
project: <slug>
task: "<task title>"
status: pending-review
tags:
  - plan
---
# Plan: <task title>

> <one sentence synthesizing Description + Acceptance into a statement of intent — never
  copy-paste. If description < 20 words and no Acceptance: "[TBD — clarify with task owner]">

---

## Artifacts

| Type | Document | Description |
|---|---|---|
| plan | [[<absolute-path-to-plan-file>\|<plan-file-name>.md]] | Implementation plan generated by <framework-or-skill> |

> Add rows via `/mdn-load` or manually. Types: `prd` `adr` `rfc` `spec` `dd` `research`

---

## Key Points

<3–6 bullets summarised from the plan. Focus on risks, constraints, non-obvious points,
implied dependencies found during codebase exploration. Reference concrete file paths.
Use [TBD] for genuine gaps.>

---

## Execution Order

<3–8 numbered steps summarised from the plan. Each step should be concrete enough for a
fresh agent to execute by reading the linked plan artifact. Reference file paths.>

---

## Notes

> Free-form notes added during review or execution. Agents append here when marking tasks done.

─── Return format ───

Return:
  { "task_title": "...", "plan_slug": "...", "plan_note_path": "...",
    "plan_artifact_path": "<absolute path to plan file>",
    "method": "<native-plan-mode | skill-name>",
    "success": true/false, "thin_description": true/false,
    "fallback_used": false, "error": "..." }
```

If the sub-agent fails to produce a plan file (skill error, framework issue): set `fallback_used: true` and respawn with native Plan Mode. If that also fails, report in Step 10.

### Step 7 — Sequential write phase
After **all** sub-agents have completed, apply all `PROJECT.md` changes in a single sequential pass:

**7a** — Insert after last `**...**` field in task block: `  **Artifact:** [[<plan-slug>]]`

**7b** — Replace `status::planning` → `status::review` in checkbox line.

**7c** — Upsert row in `## Plans` table (create section+header if missing):
```
| [[<plan-slug>]] | — | <task title> | pending-review | <NOW> |
```

**7d** — Upsert row in `## Tasks` table:
```
| <task title> | [[<plan-slug>]] | agent | review |
```

Failed tasks (sub-agent error, file not written): exclude from Step 7. They remain `status::planning`. Report in Step 10.

### Step 8 — Create review checkpoints
For each successfully planned task, insert below its agent task block:

```markdown
- [ ] #task owner::me status::review type::review priority::high
  **Title:** Review plan: <plan-slug>
  **Description:** Plan generated by /mdn-plan for agent task "<task title>". Open [[<plan-slug>]], check the blockquote summary, Key Points, and Execution Order. Edit if needed, then run /mdn-approve to approve and start execution.
  **Artifact:** [[<plan-slug>]]
```

Upsert row: `| Review plan: <plan-slug> | [[<plan-slug>]] | me | review |`

### Step 9 — Post-action task resolution
Scan `owner::me status::backlog` tasks. Close only if all three gates pass:

- **Gate 1 (never close):** `type::review`, tasks with `**Artifact:**`, unresolved `**Depends on:**`, review checkpoints just created
- **Gate 2 (action verb):** `plan`, `planning`, `generate plan`, `create plan`, `planificar`, `mdn-plan`
- **Gate 3 (subject overlap):** ≥2 tokens from all planned task titles + project slug appear in candidate title+description (stop words: `a de el la un una the and to for`), OR ≥1 if Gate 2 verb in candidate title

Print evidence before closing. On match: `status::done`, `- [x]`, append `**Completed by:** /mdn-plan on <NOW>`.

### Step 10 — Confirm to user

```
✓  Plans generated for `<slug>`

  ·  "<task title>"
     Plan: [[<plan-slug>]]
     Status: backlog → review
     Sub-agent: <model-medium | method:<name>>
     Review task: "Review plan: <plan-slug>" [owner::me status::review]

(!)  Low-detail tasks (TBD summary — expand before approving):  ← if applicable
  - "<task title>"

(!)  Failed tasks (remain in status::planning):                 ← if applicable
  - "<task title>" — <error>

(!)  Method fallbacks (used default agent instead):             ← if applicable
  - "<task title>" — <method-name> returned no valid plan

→  Next: review each plan. Run /mdn-approve project:<slug> to approve and execute.
```

## Meridian protocol reference

- Unplanned task: `owner::agent` + `status::backlog` + no `**Artifact:**`
- State machine: `backlog → planning → review → approved → in-progress → done`
- Plan index: `<vault>/meridian/<slug>/plans/<plan-name>.md`
- Sub-agent model: `model-medium` from config (default: `sonnet`)

---
name: mdn-plan
model: medium
description: >
  Meridian planning skill. Orchestrator: finds all owner::agent status::backlog tasks with
  no Artifact field and spawns one sub-agent per task to generate a Plan index note. By
  default spawns Claude Code Agent sub-agents (model-medium from config). If method:<name>
  is given, delegates to that framework or tool instead. All tasks are planned in parallel
  by default since plans are independent. project.md writes are always sequential after
  sub-agents complete. After planning, each task transitions to status::review and a review
  checkpoint is created. Use when the user says "plan all backlog tasks", "generate plans",
  "create plans for agent tasks", or runs /mdn-plan.
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
| `method` | no | — | External framework or tool name to delegate plan generation to. If absent: use Agent sub-agent (model-medium). |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`, `model-medium` (default: `sonnet`). Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/project.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Find unplanned agent tasks
Scan `## Tasks` for blocks matching **all**:
- `- [ ] #task`
- `owner::agent`
- `status::backlog`
- NO `**Artifact:**` field in block

Extract per block: checkbox line, `**Title:**`, `**Description:**`, `**Acceptance:**` (optional), `**Depends on:**` (optional).

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
Single sequential pass through `project.md`: replace `status::backlog` → `status::planning` for each selected task. Upsert row in `## Tasks` table: Status → `planning`.

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

**No `method:` given (default):**

Spawn an Agent sub-agent with `model: <model-medium>` and the following prompt:

```
Generate a Meridian Plan index note for this task and write it to disk.

Task:
  Title: <task title>
  Description: <task description>
  Acceptance: <acceptance criteria or "not specified">

Output path: <vault>/meridian/<slug>/plans/<plan-slug>.md

Use @~/.config/meridian/templates/Plan.md as the file structure. Replace all Templater
expressions with literal values:
  - title: "Plan: <task title>"
  - created: <NOW>
  - project: <slug>
  - task: "<task title>"
  - status: pending-review

Fill the body:
  - Blockquote summary (>): one sentence synthesizing Description + Acceptance into a
    statement of intent. Never copy-paste. If description < 20 words and no Acceptance:
    write "[TBD — clarify with task owner]".
  - ## Artifacts: leave the empty row | | | | and the hint comment unchanged. No artifacts.
  - ## Key Points: 3–6 bullets from the task text. Focus on risks, constraints,
    non-obvious points, implied dependencies. Use [TBD] for genuine gaps.
  - ## Execution Order: 3–8 numbered steps. Derive from Acceptance first (each criterion
    → ≥1 step), then add prerequisites. Steps concrete enough for a fresh agent.
  - ## Notes: copy the template blockquote verbatim. No content.

Write the complete file to the output path and return:
  { "task_title": "...", "plan_slug": "...", "plan_note_path": "...", "success": true/false,
    "thin_description": true/false, "error": "..." }
```

**`method:<framework-name>` given:**

Spawn an Agent sub-agent with `model: <model-medium>` and prompt it to use the specified framework/tool to generate the plan:

```
Use <framework-name> to generate a plan for this task and write the result as a Meridian
Plan index note to: <vault>/meridian/<slug>/plans/<plan-slug>.md

Task:
  Title: <task title>
  Description: <task description>
  Acceptance: <acceptance criteria or "not specified">

The output file must follow @~/.config/meridian/templates/Plan.md structure (replace
Templater expressions with literal values). The plan content generated by <framework-name>
should populate ## Key Points and ## Execution Order. Add to ## Notes:
  > Generated via <framework-name> by /mdn-plan on <NOW>

Return: { "task_title": "...", "plan_slug": "...", "plan_note_path": "...", "success": true/false,
  "fallback_used": false, "error": "..." }
```

If the sub-agent returns no valid plan note path or the file is not written: set `fallback_used: true`, respawn with the default prompt (no method).

### Step 7 — Sequential write phase
After **all** sub-agents have completed, apply all `project.md` changes in a single sequential pass:

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

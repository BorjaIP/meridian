---
name: mdn-add
model: low
description: >
  Meridian task creation skill. Adds a new task (human or agent) to a Meridian project.
  Optionally creates a Plan index stub if the task warrants one. Use when the user says
  "add a task", "create a task", "I need to track this", "add this to the project", or
  runs `/mdn-add`. Works for any kind of task: agent execution, human action, research,
  planning, ingestion orchestration, etc.
---

## Invocation

```
/mdn-add project:<slug> [title:"..."] [owner:me|agent] [type:feature|fix|research|chore] [priority:high|medium|low] [plan:yes] [note:yes|no] [complex:yes]
```

All arguments except `project` are optional. **Default mode is simple** — the skill infers everything from the user's input without asking questions. Use `complex:yes` to force interactive mode.

| Argument | Required | Description |
|---|---|---|
| `project` | yes | Meridian project slug |
| `title` | no | Short imperative title or free-form description |
| `owner` | no | `me` or `agent`. **Default: `agent`** |
| `type` | no | `feature` \| `fix` \| `research` \| `chore`. Inferred if omitted. |
| `priority` | no | `high` \| `medium` \| `low`. Inferred if omitted. Default: `medium` |
| `plan` | no | `plan:yes` to create a Plan index stub (forces complex mode) |
| `note` | no | `yes` force task note (forces complex mode); `no` suppress it |
| `complex` | no | `complex:yes` forces interactive collection of all fields |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 1.5 — Decide mode: simple vs complex

Evaluate in order — stop at first match:

1. **Force complex** if any of: `complex:yes` / `plan:yes` / `note:yes` → go to Step 2.
2. **Force complex** if user provided a detailed description (>120 chars of context beyond the title, multiple bullet points, or explicit acceptance criteria in their message) → go to Step 2.
3. **Default: simple** → skip Step 2, go to Step 1.6.

### Step 1.6 — Simple path (infer everything, no questions)

Infer all fields from the user's input (title + any extra context provided).
**All generated text (title, description, acceptance criteria) MUST be written in English, regardless of the language used in the input.**

1. **title** — clean the input into a short imperative phrase in English (≤80 chars).
2. **owner** — `agent` always.
3. **type** — infer from the title:
   - "fix", "corregir", "arreglar", "bug", "error" → `fix`
   - "revisar", "review", "analizar", "investigate", "research", "audit", "auditar" → `research`
   - "añadir", "add", "crear", "create", "implement", "implementar", "build" → `feature`
   - default → `chore`
4. **priority** — infer from the title:
   - "urgente", "urgent", "crítico", "critical", "asap", "blocker" → `high`
   - "cuando puedas", "eventually", "nice to have", "opcional" → `low`
   - default → `medium`
5. **description** — generate one sentence (≤120 chars) capturing what and why, using the title and project name as context.
6. **acceptance** — generate 1–3 concise, measurable acceptance criteria inferred from the title. Written as checkboxes.
7. **depends** — none.
8. **create_task_note** — `false`.
9. **plan** — `false`.

Proceed directly to Step 6.

### Step 2 — Complex path: collect fields interactively
*(Only reached when complex mode is triggered — see Step 1.5)*

For each field not already provided, ask in this order:
1. **title** — "Task title (short imperative phrase):"
2. **owner** — "`me` or `agent`? [agent]"
3. **type** — "`feature` / `fix` / `research` / `chore`?"
4. **priority** — "`high` / `medium` / `low`? [medium]"
5. **description** — "Description (what and why):"
6. **acceptance** — "Acceptance criteria?" (optional for `me`; encouraged for `agent`)
7. **depends** — "Depends on (prerequisite task title, or enter to skip):"

### Step 3 — Determine initial status
Both `owner::agent` and `owner::me` start at `status::backlog`.

### Step 4 — Ask about plan creation
If `plan:yes` in invocation: proceed to Step 5.

Otherwise ask only if `owner::agent` AND description is non-trivial:
> "Do you want to create a Plan index stub for this task now? (yes/no) [no]"

Skip for `owner::me` or one-liner chore tasks.

### Step 4.5 — Quantization: task note creation

Evaluate conditions in this exact order — stop at the first match:

1. **Simple mode** (came via Step 1.6) → `create_task_note = false`. Stop.
2. **Explicit `note:yes`** → `create_task_note = true`. Stop.
3. **Explicit `note:no`** → `create_task_note = false`. Stop.
4. **Hard exclusion:** `type::chore` or `type::review` → `create_task_note = false`. Stop.
5. **Auto-create (silent):** ANY of the following → `create_task_note = true`. Stop.
   - description > 280 chars
   - `type::feature` + `owner::agent`
   - plan stub was requested in Step 4
6. **Prompt required — default NO:** ANY of the following triggers a user prompt:
   - `type::feature` + `owner::me`
   - `type::fix` + description > 100 chars
   - `type::research` + `owner::agent`

   ⚠ **STOP. Do NOT proceed to Step 4.6 automatically.**
   Ask: "This task looks complex — create a dedicated task note? (yes/no) [no]"
   Wait for an explicit "yes". Anything else (including no response) → `create_task_note = false`.

7. **No match** → `create_task_note = false`.

Store result as `create_task_note` (bool) and, if true, `task_slug` (slugified title).

### Step 4.6 — Create task note (if `create_task_note == true`)
Path: `<vault>/meridian/<slug>/tasks/<task_slug>.md`. Use `@~/.config/meridian/templates/Task.md`. Fill: `title`, `type`, `owner`, `priority`, `project`, `task-slug`. Replace summary placeholder with first sentence of description (≤120 chars). Fill `## Context` with full description. Fill `## Acceptance Criteria` as checkboxes. Seed `## History` with `<NOW> — Created.`

### Step 5 — Create Plan index stub (if requested)
Slugify task title → plan name. Path: `<vault>/meridian/<slug>/plans/<plan-name>.md`.

Use `@~/.config/meridian/templates/Plan.md`. Fill frontmatter: `title: "Plan: <task title>"`, `created: <NOW>`, `project: <slug>`, `task: <task title>`. Replace Templater expressions with literal values. In `## Artifacts` add hint: `> No artifacts loaded yet. Use /mdn-load project:<slug> path:<path> type:<type> plan:<plan-name>`

Add row to `## Plans` table: `| [[<plan-name>]] | — | <task title> | pending-review | <NOW> |`

Set task `status::planning`. Add `**Artifact:** [[<plan-name>]]` to task block.

### Step 6 — Write the task
Append to end of `## Tasks` section:

```markdown
- [ ] #task owner::<owner> status::<status> type::<type> priority::<priority>
  **Title:** <title>
  **Description:** <description>
  **Task note:** [[<task_slug>]]    (only if create_task_note == true)
  **Acceptance:** <acceptance>      (omit if not provided)
  **Depends on:** <depends>         (omit if not provided)
  **Artifact:** [[<plan-name>]]     (only if plan stub created)
```

### Step 6.5 — Update Tasks table
Upsert: `| <title> | [[<plan>]] or — | <owner> | <status> |`

### Step 7 — Post-action task resolution
Scan `owner::me status::backlog` tasks. Close only if **all three gates** pass:

- **Gate 1 (never close):** `type::review`, tasks with `**Artifact:**`, unresolved `**Depends on:**`, the task just created
- **Gate 2 (action verb):** `add task`, `crear tarea`, `añadir tarea`, `registrar tarea`, `mdn-add`
- **Gate 3 (subject overlap):** ≥2 tokens from new task title in candidate title+description (stop words: `a de el la un una the and`), OR ≥1 if Gate 2 verb present

Print evidence, then: `status::backlog` → `status::done`, `- [x]`, append `**Completed by:** /mdn-add on <NOW>`.

### Step 8 — Confirm to user

Without plan:
```
✓  Task added to <slug>:
   "<title>" [owner::<owner> status::backlog type::<type> priority::<priority>]
✓  Task note created: [[<task_slug>]]   (if created)

→  Next:
   [if agent] Use /mdn-load to register planning artifacts, or /mdn-run to plan inline
   [if me] Run /mdn-daily to see your pending tasks
```

With plan stub:
```
✓  Task added: "<title>" [status::planning]
✓  Plan stub: [[<plan-name>]]

→  Load artifacts: /mdn-load project:<slug> path:<path> type:<type> plan:<plan-name>
```

## Meridian protocol reference

- Task note: `<vault>/meridian/<slug>/tasks/<task-slug>.md`
- State machine: `backlog → planning → review → approved → in-progress → done`

---
name: mdn-run
model: medium
description: >
  Meridian execution skill. Finds the first approved agent task in a project and executes
  it. If the task has a linked Plan index, loads all referenced artifacts and executes
  following the plan. If the task has no plan, executes it directly using its Title,
  Description, and Acceptance as the prompt. Accepts an optional `task:` argument to run
  a specific backlog agent task directly (simple flow) without requiring a plan or approve
  step. Use when the user says "run the next task", "execute the plan", "start working on
  the approved task", "run this task directly", or runs `/mdn-run project:<slug>`.
---

## Two flows

**Advanced flow** (no `task:` arg): finds first `owner::agent status::approved` task → Mode A (has Artifact) or Mode B (no Artifact) → executes → marks done.

**Simple flow** (`task:<title>` given): finds matching `owner::agent status::backlog` task → always Mode B → executes → marks done.

## Invocation

```
/mdn-run project:<slug> [task:<title>]
```

| Argument | Required | Description |
|---|---|---|
| `project` | yes | Meridian project slug |
| `task` | no | Title of backlog agent task (simple flow). Omit for advanced flow. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/project.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Find the next task

**Simple flow:** scan `## Tasks` for `- [ ]` + `owner::agent` + `status::backlog` + `**Title:**` matching `task:` value (case-insensitive). If not found: report and stop. → Mode B.

**Advanced flow:** scan `## Tasks` for first `- [ ]` + `owner::agent` + `status::approved`. If none: report "No approved agent tasks in `<slug>`." and suggest checking `status::review` tasks.

### Step 3 — Determine execution mode

**Mode A** (task has `**Artifact:** [[<plan-name>]]`): extract `<plan-name>`, read `<vault>/meridian/<slug>/plans/<plan-name>.md`. If missing: report error, suggest `/mdn-load` or `/mdn-plan`, stop.

**Mode B** (no `**Artifact:**`): Title + Description + Acceptance are the full execution context.

### Step 4 — Transition to in-progress
- Simple flow: `status::backlog` → `status::in-progress`
- Advanced flow: `status::approved` → `status::in-progress`
- Upsert row: `| <title> | [[<plan>]] or — | agent | in-progress |`

### Step 5 — Read artifacts (Mode A only)
Read `## Artifacts` table in plan index. For each row:
- Wikilink `[[path/to/doc]]` → resolve to `<vault>/path/to/doc.md`
- Absolute path → read directly
- Other → try as-is, then vault-relative

Warn on unreadable artifacts but continue. Combined artifact content + Plan Summary + Key Points + Execution Order = execution context.

### Step 6 — Execute

**Mode A:** follow Plan's Execution Order precisely. Use artifact content as context. Acceptance criteria = definition of done.

**Mode B:** Title = goal, Description = context, Acceptance = definition of done. Execute directly.

Do not mark complete until all acceptance criteria are met.

### Step 7 — Mark done
1. `- [ ]` → `- [x]`
2. `status::in-progress` → `status::done`
3. Append: `**Note:** <one-line summary of what was done>`
4. Remove row from `## Tasks` table.
5. Mode A only: update `## Plans` table row status → `done`.

### Step 7.5 — Sync plan note status (Mode A only)
Read `<vault>/meridian/<slug>/plans/<plan-name>.md`. Replace `^status:\s*.*$` in frontmatter with `status: done`. Write back. Warn if missing.

### Step 8 — Post-action task resolution
Scan `owner::me status::backlog` tasks. For each whose title/description semantically matches the completed task (signal words: completed task keywords + "run", "execute", "ejecutar", "mdn-run"):
1. `status::backlog` → `status::done`
2. `- [ ]` → `- [x]`
3. Append: `**Completed by:** /mdn-run on <YYYY-MM-DD>`

### Step 9 — Create verification checkpoint
Insert immediately below the completed task block:

**Mode A:**
```markdown
- [ ] #task owner::me status::review type::review priority::high
  **Title:** Verify: <completed task title>
  **Description:** Agent completed execution. Review the output and confirm it meets the acceptance criteria. Approve to close the loop, or add a new task if corrections are needed.
  **Artifact:** [[<plan-name>]]
```

**Mode B:**
```markdown
- [ ] #task owner::me status::review type::review priority::high
  **Title:** Verify: <completed task title>
  **Description:** Agent completed execution. Review the output and confirm it meets the acceptance criteria. Approve to close the loop, or add a new task if corrections are needed.
```

Upsert row: `| Verify: <title> | [[<plan>]] or — | me | review |`

### Step 10 — Confirm to user

**Mode A:**
```
✓  Task done: "<task title>"
✓  Plan: [[<plan-name>]]

<brief summary of what was executed and what changed>

▸  Verification task created: "Verify: <task title>" [owner::me status::review]
   Review the output and mark it done, or add a correction task.
```

**Mode B:**
```
✓  Task done: "<task title>" (planless)

<brief summary>

▸  Verification task created: "Verify: <task title>" [owner::me status::review]
```

## Meridian protocol reference

- State machine: `backlog → planning → review → approved → in-progress → done`
- Plan index: `<vault>/meridian/<slug>/plans/<plan-name>.md`
- Artifacts: vault wikilink, absolute path, or custom string (as stored by mdn-load)

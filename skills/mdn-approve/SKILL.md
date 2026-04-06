---
name: mdn-approve
model: low
description: >
  Meridian approval skill. Approves a pending review task for a plan, marks it done,
  transitions the linked agent task to approved (or creates one if none exists), and
  immediately executes /mdn-run to start execution without any further user prompt.
  Use when the user says "approve this", "apruébalo", "ya revisé el plan",
  "mark as approved", "proceed with the plan", or runs `/mdn-approve`.
---

## Invocation

```
/mdn-approve project:<slug> [plan:<plan-name>]
```

| Argument | Required | Description |
|---|---|---|
| `project` | yes | Meridian project slug |
| `plan` | no | Plan name to approve. Defaults to first `status::review` task found. |

## Execution steps

### Step 0 — Resolve config
Read `${XDG_CONFIG_HOME:-~/.config}/meridian/config.md`. Extract `vault`. Run Date generation snippet → `<NOW>`. If missing: tell user to run `/mdn-init`.

### Step 1 — Find project note
Read `<vault>/meridian/<slug>/PROJECT.md`. Verify `project: <slug>` in frontmatter. If missing: suggest `/mdn-init name:<slug>`.

### Step 2 — Find the review task
Scan `## Tasks`:
- If `plan:` given: find task whose `**Artifact:**` field contains `<plan-name>`
- Otherwise: find first task matching **all**: `owner::me`, `status::review`, `type::review`, AND has a `**Artifact:**` field

If not found: report "No pending plan review tasks in `<slug>`." and stop.
If only tasks without `**Artifact:**` exist (Verify checkpoints): report "No plan review tasks found — only verification checkpoints pending. Mark them done manually." and stop.

Read `**Artifact:**` field — this is the Plan index wikilink (`[[<plan-name>]]`).

### Step 3 — Mark review task done
1. Check the checkbox: `- [ ]` → `- [x]`
2. Replace `status::review` → `status::done`
3. Append: `**Approved on:** <NOW>`
4. Remove its row from `## Tasks` table.

### Step 4 — Update Plans table
Find the plan row, update status: `pending-review` → `approved`.

### Step 4.5 — Sync plan note status
Resolve `<vault>/meridian/<slug>/plans/<plan-name>.md`. Find `^status:\s*.*$` in YAML frontmatter, replace with `status: approved`. If file/line missing: warn and continue.

### Step 5 — Ensure agent task exists

**Case A — agent task exists** (`owner::agent` with matching `**Artifact:**`, `status` in `{planning, review, backlog}`):
- (If the matched task is `status::done` or `status::in-progress`: print "Plan already executed or in progress — nothing to approve." and stop.)
- Replace its status with `status::approved`
- Upsert row: `| <agent task title> | [[<plan-name>]] | agent | approved |`

**Case B — no agent task:**
- Read plan note, extract the blockquote summary line (first line starting with `> ` after the H1 title). Strip the leading `> ` and any trailing whitespace.
- Append to `## Tasks`:
```markdown
- [ ] #task owner::agent status::approved type::feature priority::high
  **Title:** Execute plan: <plan-name>
  **Description:** <Summary line>
  **Artifact:** [[<plan-name>]]
```
- Upsert row: `| Execute plan: <plan-name> | [[<plan-name>]] | agent | approved |`

### Step 6 — Execute mdn-run
Immediately invoke `/mdn-run project:<slug> task:"<agent task title>"` — pass the title of the agent task that was just approved (Case A) or created (Case B) so `mdn-run` executes exactly that task. Do not print confirmation first. mdn-run output is the final output of this skill.

## Meridian protocol reference

- State machine: `backlog → planning → review → approved → in-progress → done`
- Plan index: `<vault>/meridian/<slug>/plans/<plan-name>.md`

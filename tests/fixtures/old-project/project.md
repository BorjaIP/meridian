---
title: Sample Legacy
created: Friday 3rd April 2026 17:02
project: sample-legacy
status: active
tags:
  - project
---
# Sample Legacy

> Sample project used to test the migrator.

---

## Sources

> Directories scanned by `/mdn-sync`.

- /home/user/.claude/plans/

---

## Plans

| Plan          | Type | Task | Status | Loaded |
| ------------- | ---- | ---- | ------ | ------ |
| [[old-plan]]  | spec | —    | done   | today  |

---

## Tasks

| Task                               | Plan   | Owner | Status   |
| ---------------------------------- | ------ | ----- | -------- |
| Verify: Research: token cost       | —      | me    | review   |
| Fix login redirect                 | —      | agent | backlog  |

- [ ] #task owner::me status::review type::review priority::high
  **Title:** Verify: Research: token cost
  **Description:** Agent completed execution. Review the output.

- [ ] #task owner::me status::review type::review priority::high
  **Title:** Verify: Docs: update docs
  **Description:** Agent completed execution. Review the output.
  **Artifact:** [[old-plan]]

- [ ] #task owner::agent status::backlog type::fix priority::high
  **Title:** Fix login redirect
  **Description:** Redirect loops after logout.
  **Acceptance:** No loop after logout; covered by a test.

- [ ] #task  owner::agent status::planning type::feature priority::high
  **Title:** Integrate memory layer
  **Description:** Design a persistent memory layer. Details TBD during planning.
  **Task note:** [[integrate-memory]]
  **Artifact:** [[integrate-memory]]

- [ ] #task owner::agent status::backlog type::fix priority::low
  **Title:** Fix login redirect
  **Description:** Same title as another task, to force a slug collision.

- [ ] #task owner::agent status::backlog type::research priority::medium
  **Title:** Review: simplify the template for agent and human readability today
  **Description:** A long title that must be truncated at a word boundary.

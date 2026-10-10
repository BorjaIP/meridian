---
title: Sample Legacy
project: sample-legacy
status: active
repo: /home/user/sample
tags:
  - project
---
# Sample Legacy

> Sample project used to test the migrator.

---

## Tasks

- [ ] #task owner::me status::review priority::high type::review slug::research-token-cost
  **Title:** Verify: Research: token cost
  **Description:** Agent completed execution. Review the output.

- [ ] #task owner::me status::review priority::high type::review slug::docs-update-docs
  **Title:** Verify: Docs: update docs
  **Description:** Agent completed execution. Review the output.
  **Note:** Legacy links: artifact [[old-plan]]

- [ ] #task owner::agent status::backlog priority::high type::fix slug::fix-login-redirect
  **Title:** Fix login redirect
  **Description:** Redirect loops after logout.
  **Acceptance:** No loop after logout; covered by a test.

- [ ] #task owner::agent status::backlog priority::high type::feature slug::integrate-memory-layer
  **Title:** Integrate memory layer
  **Description:** Design a persistent memory layer. Details TBD during planning.
  **Note:** Legacy links: artifact [[integrate-memory]]; task note [[integrate-memory]]; was in planning before migration

- [ ] #task owner::agent status::backlog priority::low type::fix slug::fix-login-redirect-2
  **Title:** Fix login redirect
  **Description:** Same title as another task, to force a slug collision.

- [ ] #task owner::agent status::backlog priority::medium type::research slug::simplify-the-template-for-agent-and-human
  **Title:** Review: simplify the template for agent and human readability today
  **Description:** A long title that must be truncated at a word boundary.

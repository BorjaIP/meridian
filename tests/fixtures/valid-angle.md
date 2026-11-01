---
title: Fix <x> in frontmatter
project: angle
status: active
---
# Angle

## Tasks

- [ ] #task owner::agent status::backlog priority::low type::chore slug::safe-tags
  **Title:** Safe tags
  **Description:** Inline code `<branch-name>` and an autolink <https://example.com>
  and a mail <user@example.com> plus a < b and x <3 are fine.
  **Acceptance:** A fence is ignored:
```
<branch-name> inside a fenced block
```

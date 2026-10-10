---
title: Sample
project: sample
status: active
repo: /home/user/projects/sample
tags:
  - project
---
# Sample

## Tasks

- [ ] #task owner::agent status::backlog priority::medium type::chore slug::tidy-readme
  **Title:** Tidy the README
  **Description:** Fix typos and broken links.

- [ ] #task owner::agent status::in-progress priority::high type::feature slug::add-export
  **Title:** Add export command
  **Description:** Export tasks as CSV.
  **Acceptance:** `export` writes a valid CSV file.
  **Run:** started 2026-10-10 14:10 · ended · repo /home/user/projects/sample · branch feat/add-export

- [ ] #task owner::agent status::review priority::high type::fix slug::fix-login
  **Title:** Fix login redirect
  **Description:** Redirect loops after logout.
  **Run:** started 2026-10-10 09:00 · ended 2026-10-10 09:42 · repo /home/user/projects/sample · branch fix/login
  **Trace:** [odd/tasks/fix-login.md](\\wsl.localhost\Arch\home\user\projects\sample\odd\tasks\fix-login.md) · engram odd/fix-login/tasks · commits a1b2c3d, d4e5f6a · PR #12

- [x] #task owner::agent status::done priority::low type::research slug::compare-parsers
  **Title:** Compare parsers
  **Description:** Pick a parser.
  **Run:** started 2026-10-09 10:00 · ended 2026-10-09 11:00 · repo /home/user/projects/sample · branch main
  **Trace:** [notes](\\wsl.localhost\Arch\home\user\notes.md) · commits abc1234

- [ ] #task owner::me status::review priority::medium type::review slug::read-the-report
  **Title:** Read the report
  **Description:** Human check, no commits.
  **Trace:** [report](\\wsl.localhost\Arch\home\user\report.md) · commits

- [ ] #task owner::me status::blocked priority::low type::chore slug::wait-for-access
  **Title:** Wait for access
  **Description:** Blocked on a third party.

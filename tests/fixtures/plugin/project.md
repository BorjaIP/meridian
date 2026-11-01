---
title: Atlas Notes
project: atlas            # kebab-case
status: active
repo: /demo/atlas
tags:
  - project
---
# Atlas Notes

> Synthetic project for the Meridian demo canvas. Everything here is invented.

---

## Tasks

- [ ] #task owner::agent status::review priority::high type::feature slug::sync-engine-rewrite
  **Title:** Rewrite the sync engine around an append-only change log
  **Description:** Replace the polling loop with a change log.
  Keep the old protocol readable for one release.
  **Run:** started 2026-10-10 08:10 · ended 2026-10-10 11:45 · repo /demo/atlas · branch feat/change-log
  **Trace:** [odd/tasks/sync-engine-rewrite.md](\\wsl.localhost\Demo\demo\atlas\odd\tasks\sync-engine-rewrite.md) · commits abc1234, def5678

- [ ] #task owner::agent status::review priority::high type::fix slug::fix-offline-merge
  **Title:** Fix lost edits when two devices merge after being offline
  **Run:** started 2026-10-09 13:00 · ended 2026-10-09 15:20 · repo /demo/atlas · branch fix/offline-merge
  **Trace:** [odd/tasks/fix-offline-merge.md](\\wsl.localhost\Demo\demo\atlas\odd\tasks\fix-offline-merge.md) · commits 9a8b7c6

- [ ] #task owner::agent status::review priority::medium type::feature slug::tag-autocomplete
  **Title:** Autocomplete tags while typing a note
  **Run:** started 2026-10-10 09:00 · ended 2026-10-10 10:30 · repo /demo/atlas · branch feat/tags
  **Trace:** commits abc123

- [ ] #task owner::agent status::review priority::low type::research slug::export-pdf-spike
  **Title:** Spike: can we export a notebook to PDF without a headless browser?
  **Run:** started 2026-10-09 09:00 · ended 2026-10-09 12:00 · repo /demo/atlas · branch spike/pdf
  **Trace:** [odd/tasks/export-pdf-spike.md](\\wsl.localhost\Demo\demo\atlas\odd\tasks\export-pdf-spike.md) · commits 1f2e3d4

- [ ] #task owner::agent status::blocked priority::high type::feature slug::attachment-quota
  **Title:** Enforce the attachment quota per workspace
  **Note:** Waiting for the billing team to confirm the quota numbers.

- [ ] #task owner::agent status::blocked priority::medium type::fix slug::search-ranking
  **Title:** Search ranks archived notes above recent ones
  **Note:** Needs a decision: drop archived notes or only down-rank them?

- [ ] #task owner::me status::blocked priority::low type::chore slug::ios-share-sheet
  **Title:** Update the iOS share sheet icon set
  **Note:** The design files have not been delivered yet.

- [ ] #task owner::agent status::in-progress priority::high type::feature slug::conflict-ui
  **Title:** Show a side by side diff when two edits conflict
  **Run:** started 2026-10-11 09:00 · ended · repo /demo/atlas · branch feat/conflict-ui

- [ ] #task owner::agent status::in-progress priority::medium type::chore slug::migrate-tags-table
  **Title:** Migrate the legacy tags table to the new schema
  **Run:** started 2026-10-10 15:30 · ended · repo /demo/atlas · branch chore/tags-table

- [ ] #task owner::agent status::in-progress priority::medium type::fix slug::stuck-importer
  **Title:** Importer hangs on notebooks with more than 5000 notes
  **Run:** started 2026-10-08 10:00 · ended · repo /demo/atlas · branch fix/importer

- [ ] #task owner::me status::in-progress priority::low type::chore slug::dark-mode-polish
  **Title:** Polish the dark mode contrast of the sidebar
  **Run:** started 2026-10-11 09:00 · ended · repo /demo/atlas · branch main

- [ ] #task owner::agent status::backlog priority::high type::feature slug::reminders
  **Title:** Add reminders with a due date to any note
  **Description:** Reminders appear in a daily digest.
  Each reminder can repeat: daily, weekly or monthly.
  The digest is sent by email and shown in the app.
  Out of scope: shared reminders between users.

- [x] #task owner::agent status::done priority::low type::chore slug::rename-assets
  **Title:** Rename the asset folder to match the new naming scheme
  **Trace:** [odd/tasks/rename-assets.md](\\wsl.localhost\Demo\demo\atlas\odd\tasks\rename-assets.md) · commits 0a0b0c0

- [x] #task owner::agent status::done priority::medium type::fix slug::login-timeout
  **Title:** Raise the login timeout on slow networks
  **Trace:** [odd/tasks/login-timeout.md](\\wsl.localhost\Demo\demo\atlas\odd\tasks\login-timeout.md) · commits 1d2c3b4

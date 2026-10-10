# simplify-meridian-on-odd

Branch: feat/odd-simplification
Plan source: ~/.claude/plan/meridian/simplify-meridian-on-odd.md
Backups: ~/.claude/meridian-backups/ (installed mdn skills, vault project)
Checks mode: no test runner exists (markdown + bash project). Test-first exception recorded: use a format-lint script (T1.2) and dry runs as functional checks.
Delivery: single PR on the feature branch, user decides push/PR; size:exception is a maintainer-owned label, not applicable (own repo).

## Specs

- S1: `/mdn-run "<description>"` is the single trigger: it writes the task into the vault project note BEFORE executing, then runs gentle-ai ODD in the main thread, then completes metadata and sets `review`.
- S2: Task states are `backlog -> in-progress -> review -> done`, plus `blocked`. No `planning`/`approved`.
- S3: One file per project (`project.md`) with inline `#task` lines; each task may carry a `**Run:**` and a `**Trace:**` block. `plans/`, REVIEW.md, GOAL.md, PROGRESS.md, checkpoints/ are retired.
- S4: Trace metadata (branch, commits, diff stat, PR, changed `odd/tasks/*.md`) comes from git/gh commands, never from model self-report.
- S5: `odd/` always lives in the repo; the vault links to it with a Markdown link to the Windows UNC path plus relative path, branch and commits as text.
- S6: Meridian never toggles RDD (`gentle-ai review mode`), and never runs gentle-ai as a subagent.
- S7: Commands kept: init, add, run, done, daily, status, archive. Retired: plan, approve, reviewer, checkpoint, generator, loop (decision in T4.4), old load/sync.
- S8: Vault project migration is dry-run first, applied only after user review, keeping legacy files under `archive-legacy/`.

## Tasks

- [x] T0.1 (S8) Back up installed mdn skills and vault project | route: inline | evidence: ~/.claude/meridian-backups/*.tar.gz
- [x] T1.1 (S2,S3) Define new task/Run/Trace format in docs/protocol.md; slim templates/Project.md; drop Plan.md/Task.md | route: delegated writer | commit 523e67c
- [x] T1.2 (S2,S3) Add format-lint script (scripts/mdn-lint.sh) + sample fixtures | route: delegated writer | commit c36efec | evidence: RED 11 fails (no linter) -> GREEN `bash tests/run.sh` all 11 ok (re-run by parent); gawk 5.3.1; shellcheck not installed
- [x] T2.1 (S1,S4,S5,S6) Rewrite skills/mdn-run for the single-trigger flow (slug, in-progress first, ODD handoff, git/gh metadata, odd doc detection, UNC link, interrupted-run recovery) | route: delegated writer | commits ecd15f8, db6eff0 | evidence: RED 23 fails -> GREEN trace-test + run.sh all pass (re-run by parent); live smoke on this repo returned correct UNC link. NOT verified: skill end to end (needs real session, see T4.3); gh pr list vs real remote
- [ ] T3.1 (S2,S3,S7) Update add, done (new), daily, status, archive, init to the new format/states | route: delegated writer
- [ ] T3.2 (S7) Remove retired skills (plan, approve, reviewer, checkpoint, generator, loop, load, sync) from repo | route: delegated writer
- [ ] T4.1 (S8) Dry-run converter for the vault project onto a copy; show diff to user | route: delegated writer
- [ ] T4.2 (S8) Apply migration to the vault after user review (single revertable change); legacy kept in archive-legacy/ | route: inline, needs user OK
- [ ] T4.3 (S1) Dogfood: run the next real Meridian task through /mdn-run end to end | route: inline
- [ ] T4.4 (S7) Decide fate of mdn-loop from T2/T4.3 evidence | route: inline
- [ ] T5.1 (S7) Rewrite README/docs for the ODD flow; fix placeholder URLs; update install.sh | route: delegated writer
- [ ] T6.1 (deferred) /mdn-sync only if drift proves real

## Log

- L1 (2026-10-10, user): "empieza con todo directamente para ir iterando" — execute the plan in ~/.claude/plan/meridian/simplify-meridian-on-odd.md; simplify Meridian to fit ODD; later test it against the existing Meridian project in the vault (old format) and migrate it to the new format.
- L2 (user, earlier in the conversation): doc/vault link is a pointer to the repo path; traceability is the key requirement. Prompt text itself is not stored in Meridian.
- L3: Phase 0 done on 2026-10-10 14:42. Vault repo (E:\Documents\pkm\pkm) is git with a periodic "vault backup" commit; untracked engram/ folder there comes from the earlier obsidian-export test.
- L4: T1.1/T1.2 done. Parent re-ran tests and smoke-tested the linter on the real vault project: it flags missing slug and retired state `planning`, as expected for the old format.
- L5: T2.1 done. mdn-run SKILL.md mentions /mdn-done, which is created in T3.1. mdn-trace.sh emits repeated key=value lines (odd_doc=, unc_link=, commits= comma-separated).
- Progress: 4/12 tasks. Next step: T3.1 + T3.2 via one delegated writer.

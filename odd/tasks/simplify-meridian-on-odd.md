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
- S9: `/mdn-init` fills the one-line project description itself by reading the repo and its context (README, manifests, CLAUDE.md/AGENTS.md); it never invents: with insufficient evidence it keeps the placeholder and says so. Re-running init on an existing project only fills a placeholder description, nothing else.
- S10: Init guard: every command other than init first checks (config with vault, project resolved, project.md exists). If something is missing it states that Meridian must be initialized and runs the init steps inline in auto mode (no questions except the vault path when the config is missing), then continues the original command, as other frameworks do.

## Tasks

- [x] T0.1 (S8) Back up installed mdn skills and vault project | route: inline | evidence: ~/.claude/meridian-backups/*.tar.gz
- [x] T1.1 (S2,S3) Define new task/Run/Trace format in docs/protocol.md; slim templates/Project.md; drop Plan.md/Task.md | route: delegated writer | commit 523e67c
- [x] T1.2 (S2,S3) Add format-lint script (scripts/mdn-lint.sh) + sample fixtures | route: delegated writer | commit c36efec | evidence: RED 11 fails (no linter) -> GREEN `bash tests/run.sh` all 11 ok (re-run by parent); gawk 5.3.1; shellcheck not installed
- [x] T2.1 (S1,S4,S5,S6) Rewrite skills/mdn-run for the single-trigger flow (slug, in-progress first, ODD handoff, git/gh metadata, odd doc detection, UNC link, interrupted-run recovery) | route: delegated writer | commits ecd15f8, db6eff0 | evidence: RED 23 fails -> GREEN trace-test + run.sh all pass (re-run by parent); live smoke on this repo returned correct UNC link. NOT verified: skill end to end (needs real session, see T4.3); gh pr list vs real remote
- [x] T3.1 (S2,S3,S7) Update add, done (new), daily, status, archive, init to the new format/states | route: delegated writer | commit 8b43444 | evidence: tests/run.sh pass (re-run by parent); mdn-done/mdn-archive file edits hand-simulated with awk and lint-clean; skills themselves not run (markdown, no unit tests)
- [x] T3.2 (S7) Remove retired skills (plan, approve, reviewer, checkpoint, generator, loop, load, sync) from repo | route: delegated writer | commit 2885490 | evidence: ls skills = add archive daily done init run status; grep of retired terms = 0 hits (re-run by parent); skills 1940 -> 480 lines
- [x] T4.1 (S8) Dry-run converter for the vault project onto a copy; show diff to user | route: delegated writer | commit 5f4769c | evidence: RED 16 fails -> GREEN migrate-test 25 checks + run.sh all pass (re-run by parent); real dry run exit 0, 7 tasks, lint OK on output; vault git status clean after (re-checked by parent); --apply NOT run on real vault
- [x] T4.2 (S8) Apply migration to the vault after user review; legacy kept in archive-legacy/ | route: inline | user OK given 2026-10-10 | evidence: --apply exit 0, 7 tasks, 13 files to archive-legacy/, lint OK on the real vault project.md; pre-apply backup ~/.claude/meridian-backups/vault-meridian-project-pre-apply-*.tar.gz. NOTE: vault meridian/ is git-ignored (.gitignore:25), so the tarballs are the only undo, not git
- [x] T4.6 (S9) mdn-init derives and writes the one-line description from repo context; idempotent re-run fills a placeholder only | route: delegated writer | commit 4512a7e | evidence: skills-test RED 11 -> GREEN (structure only); README tagline extraction simulated; re-run/idempotence and evidence order reasoned only, not run
- [x] T4.7 (S10) Init guard block in add/run/done/daily/status/archive + tests/skills-test.sh asserting each skill carries the guard and init has the derivation steps | route: delegated writer | commit 005f35f | evidence: 6 identical guard blocks (grep, re-run by parent); tests/run.sh all pass; guard BEHAVIOR unverified until T4.3
- [x] T4.5 (S8) Make mdn-migrate.sh warn/refuse --apply when the project dir is git-ignored (its dirty-tree guard passes vacuously then) | route: delegated writer | commit ab1e8df | evidence: migrate-test RED 3 fails -> GREEN; manual refusal check exit 1
- [x] T4.3 (S1) Dogfood: /mdn-run end to end | route: inline | evidence: headless `claude -p` failed (OAuth expired in child process, nothing ran). Instead ran the INSTALLED skill via the Skill tool in this session against a sandbox (temp repo, vault, XDG config): init guard fired and auto-init created the project with a README-derived description; task recorded before work; RED->GREEN->commit; mdn-trace finish; Trace written; status review; lint OK at every write. Found+fixed 2 gaps (commit d950d28): work branch not recorded; .atl/odd false dirty-tree note. NOT covered: ODD document path (substantial task), resume, blocked, and e2e of done/daily/status/archive; run was by the same model that wrote the skills, with this session's context
- [x] T4.4 (S7) Decide fate of mdn-loop | route: inline | decision: removed in T3.2 (commit 2885490); revisit only if dogfood shows a need for sequential backlog runs
- [x] T5.1 (S7) Rewrite README/docs for the ODD flow; fix placeholder URLs; update install.sh | route: delegated writer | commits a4ff93a, 432d682 | evidence: install-test RED 16/21 fails -> GREEN 22 checks (temp HOME); tests/run.sh all pass; github.com/user grep = 0 (re-run by parent). Parent then ran install.sh for real (dry-run first): 7 skills in ~/.claude/skills, scripts+template in ~/.config/meridian, 8 retired skills moved to ~/.config/meridian/retired-skills-20261010-1629. NOT verified: real git clone path, codex loading, curl|bash one-liner. Gap: stale templates/Plan.md and Task.md remain in ~/.config/meridian/templates
- [ ] T6.1 (deferred) /mdn-sync only if drift proves real

## Log

- L1 (2026-10-10, user): "empieza con todo directamente para ir iterando" — execute the plan in ~/.claude/plan/meridian/simplify-meridian-on-odd.md; simplify Meridian to fit ODD; later test it against the existing Meridian project in the vault (old format) and migrate it to the new format.
- L2 (user, earlier in the conversation): doc/vault link is a pointer to the repo path; traceability is the key requirement. Prompt text itself is not stored in Meridian.
- L3: Phase 0 done on 2026-10-10 14:42. Vault repo (E:\Documents\pkm\pkm) is git with a periodic "vault backup" commit; untracked engram/ folder there comes from the earlier obsidian-export test.
- L4: T1.1/T1.2 done. Parent re-ran tests and smoke-tested the linter on the real vault project: it flags missing slug and retired state `planning`, as expected for the old format.
- L5: T2.1 done. mdn-run SKILL.md mentions /mdn-done, which is created in T3.1. mdn-trace.sh emits repeated key=value lines (odd_doc=, unc_link=, commits= comma-separated).
- L6: T3.1/T3.2 done. Vault project (old format) has 3 duplicated task representations: Plans table, Tasks summary table and 7 inline #task blocks (4 backlog, 1 planning, 2 review owner::me). Plus plans/ (10 notes), tasks/integrate-memory-kb.md, tasks/history.md (196 lines). Some open tasks look superseded by gentle-ai+engram (memory KB, memory partitioning, Plan.md simplification): flag to user at migration review, do not auto-drop.
- L7: T4.1 done. Dry-run output kept at a temp dir (see session); awaiting user review before T4.2 (--apply). Known quirks: 'Verify:' tasks lose the verify- prefix in their slug; description stays a TODO placeholder; CRLF input untested.
- L8: T4.2 applied with user approval. Correction recorded: I told the user the change was revertable via git, but the vault's meridian/ folder is git-ignored; undo = restore the tarball. Follow-up T4.5 added.
- L9 (user): "el one line description deberia de rellenarlo el mdn-init al crear el proyecto y leer el repo y el contexto, ademas de que cuando ejecutas cualquier otro comando indique que hay que ejecutar el init antes y lo ejecutes como el resto de frameworks hace" -> S9, S10, T4.6, T4.7.
- L10: T4.5-T4.7 done. Parent applied the init description rule to the real vault project.md (README tagline, 120 chars, lint OK; pre-edit copy in ~/.claude/meridian-backups/project.md.pre-description-*). Note: init was not executed as a skill, the rule was applied by hand.
- L11: T5.1 done and installed for real. T4.3 started as a sandboxed headless run (temp repo, temp vault, temp XDG config) of /mdn-run via `claude -p`; results pending.
- L12: structure/scaling review requested by user. Facts: real note avg 706 chars/task; Dataview, Tasks plugin and Bases are enabled in the vault; installer leaves stale templates/Plan.md and Task.md in ~/.config/meridian/templates.
- Progress: 14/15 tasks (T6.1 deferred by user). Open follow-ups: stale template cleanup in install.sh, scale improvements (digest script, monthly history, description length lint, Dataview dashboard), untested e2e paths.

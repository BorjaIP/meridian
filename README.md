<p align="center">
  <img src="docs/images/icon-rounded.png" width="540" />
</p>

# Meridian

> A human traceability ledger for agent work: what was asked, when it ran, and where the evidence is.

Meridian keeps one Markdown note per project in your Obsidian vault. Each task in it records the request, the run (dates, repository, branch) and a trace that points to the evidence: the task document that the [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai) ODD workflow wrote in the repository, the commits, and the pull request.

Meridian does not plan or orchestrate. In a Claude Code session with gentle-ai v4, ODD (Organic Driven Development) runs by default on every request. Meridian wraps that run: it records the task before work starts, lets ODD do the work, then fills the metadata from git and moves the task to `review` for you.

```
 you ──> /mdn-run "fix the login redirect"
           │ 1. write the task in the vault note (in-progress + Run)
           │ 2. ODD does the work in the repo (odd/tasks/<slug>.md, commits)
           │ 3. metadata from git/gh -> Trace, status -> review
           ▼
 you <── review the result, then /mdn-done <slug>
```

→ [Concepts](docs/concepts.md) · [Workflow](docs/workflow.md)

## Requirements

- An Obsidian vault (any folder of Markdown works; Obsidian is only the viewer).
- [Claude Code](https://claude.com/claude-code) with gentle-ai v4 for `/mdn-run` (it relies on ODD). Codex gets the skills installed, but the ODD flow is only designed and exercised for Claude Code with gentle-ai.
- `git` (required by `/mdn-run`); `gh` optional, for the pull request field.
- bash, awk, sed, grep and coreutils for the helper scripts (the lint script was tested with gawk). Links to repository documents are Windows UNC paths and are meant for WSL; elsewhere they are plain text pointers.

## Install

```bash
# Claude Code (default)
bash <(curl -fsSL https://raw.githubusercontent.com/BorjaIP/meridian/main/install.sh)

# Codex
bash <(curl -fsSL https://raw.githubusercontent.com/BorjaIP/meridian/main/install.sh) --tool codex

# From a local checkout (no network), previewing first
git clone https://github.com/BorjaIP/meridian && cd meridian
bash install.sh --source . --dry-run
bash install.sh --source .
```

Options: `--tool claude|codex|all`, `--source <dir>`, `--dry-run`. The installer is idempotent. It writes:

| What | Where |
|---|---|
| Skills | `~/.claude/skills/mdn-*/` (and `~/.codex/skills/` for Codex) |
| Helper scripts (`mdn-lint.sh`, `mdn-trace.sh`, `mdn-migrate.sh`) | `~/.config/meridian/scripts/` |
| Templates | `~/.config/meridian/templates/` |

Skills from older Meridian versions that no longer exist are moved (not deleted) to `~/.config/meridian/retired-skills-<date>/`, together with a backup of any installed skill it overwrites.

## Quick start

```
/mdn-init name:my-app            # first run asks for your vault path
/mdn-run "add rate limiting to the login endpoint"
/mdn-daily                       # what needs you today
/mdn-done add-login-rate-limit   # accept the result after reviewing it
```

Every command other than `/mdn-init` checks that Meridian is initialized and, if not, runs init for you first.

## Commands

| Command | What it does |
|---|---|
| `/mdn-init` | Create the vault project note; fills the description from the repo. |
| `/mdn-add` | Queue a task (agent or human) without running it. |
| `/mdn-run` | Record a task, run it through ODD, complete Run and Trace, set `review`. |
| `/mdn-done` | Accept a task in `review` (or send it back with a reason). |
| `/mdn-daily` | Everything that needs your attention today. |
| `/mdn-status` | Counts by status and owner across projects. |
| `/mdn-archive` | Move done tasks to `TASK_HISTORY.md`. |

→ [Skills reference](docs/skills.md)

## States

`backlog -> in-progress -> review -> done`, plus `blocked`. `review` means "look at the result", not "it is correct"; only you move a task to `done`. The exact file format, the Run and Trace blocks and the state machine are specified in [docs/protocol.md](docs/protocol.md), and `scripts/mdn-lint.sh <project.md>` validates a note.

## Limits

- The Markdown protocol is agent-agnostic; the installers are not. Only Claude Code and Codex installers exist.
- Skills are instructions for a model. How faithfully they are followed depends on the model; the scripts and `mdn-lint.sh` exist to check the parts that can be checked mechanically.
- Metadata comes from git and `gh`, not from the model's account of itself, but `/mdn-run` end-to-end behavior is validated by use, not by automated tests.
- The vault and the repository are separate: the vault holds pointers, the `odd/` documents live in the repository.

## Migrating from the old format

Earlier versions used plans, approvals and several files per project. See section 7 of [docs/protocol.md](docs/protocol.md) and run `scripts/mdn-migrate.sh` (dry run first, `--apply` after reviewing).

## Documentation

| Document | Contents |
|---|---|
| [concepts.md](docs/concepts.md) | What Meridian is, how it relates to ODD and Engram |
| [workflow.md](docs/workflow.md) | A task from request to done |
| [skills.md](docs/skills.md) | One section per command |
| [configuration.md](docs/configuration.md) | Config file, vault layout, installed files |
| [protocol.md](docs/protocol.md) | File format and state machine specification |

## Tests

```bash
bash tests/run.sh
```

# Configuration

## Config file

```
${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md
```

Created by `/mdn-init` on first run (it asks for the vault path). Only the YAML frontmatter is read:

```markdown
---
vault: /absolute/path/to/obsidian/vault
delivery:
---
```

| Field | Required | Meaning |
|---|---|---|
| `vault` | yes | Absolute path of the vault root. Projects live in `<vault>/meridian/<slug>/project.md`. |
| `delivery` | no | Free-text sentence that `/mdn-run` passes verbatim to ODD, for example `single PR; I accept size:exception`. Empty means ODD defaults. |

## Vault layout

```
<vault>/meridian/<slug>/
  project.md          the project note, with all tasks
  logs/YYYY-MM.md     append-only events and archived tasks, created on first write
<vault>/meridian/dashboard.md   Dataview dashboard, created once by /mdn-init, never overwritten
```

Project frontmatter: `title`, `project` (slug), `status` (`active|paused|done|archived`), optional `repo` (absolute path of the code repository, used to match the current directory to a project), `tags`. Only `active` projects appear in `/mdn-daily` and `/mdn-status`. The task line, blocks and rules are specified in [protocol.md](protocol.md); validate with `scripts/mdn-lint.sh <project.md>`.

## Installed files

`install.sh` places files under your home directory:

| Path | Content |
|---|---|
| `~/.claude/skills/mdn-*/SKILL.md` | The seven skills (Claude Code). |
| `~/.codex/skills/mdn-*/SKILL.md` | The same skills, when installed with `--tool codex` or `all`. |
| `~/.config/meridian/scripts/` | `mdn-lint.sh`, `mdn-trace.sh`, `mdn-migrate.sh`, `mdn-log.sh`, `mdn-index.sh` (executable). |
| `~/.config/meridian/templates/Project.md`, `Dashboard.md` | Templates used by `/mdn-init`. Stale `Plan.md` and `Task.md` are moved to `retired-skills-<timestamp>/templates/` by the installer. |
| `~/.config/meridian/retired-skills-<date>/` | Only when needed: skills from older versions and backups of overwritten skills. |

Skills look for helper scripts in `~/.config/meridian/scripts/` first, then in the `scripts/` folder of the Meridian repository, and skip the check (saying so) if neither exists.

## Model hints

Each skill has a `model: low|medium` frontmatter hint. The installer rewrites it per tool: defaults `haiku`/`sonnet` for Claude, `gpt-4o-mini`/`gpt-4o` for Codex. Override at install time:

```bash
MERIDIAN_CLAUDE_LOW=haiku MERIDIAN_CLAUDE_MEDIUM=sonnet \
MERIDIAN_CODEX_LOW=<model> MERIDIAN_CODEX_MEDIUM=<model> \
  bash install.sh --source .
```

The Codex defaults are not verified against current Codex model names; set them to what your account offers. Whether a tool honors the hint is up to the tool.

## Installer options

`--tool claude|codex|all` (default `claude`), `--source <dir>` (install from a local checkout, no network), `--dry-run` (print actions, change nothing). The installer is idempotent: a second run changes nothing.

## Migrating from the old format

Old projects (plans, approvals, several files) can be converted with `scripts/mdn-migrate.sh <project-dir> --dest <dir>` (dry run on a copy) and `--apply` once reviewed. Legacy files go to `archive-legacy/`. The mapping is in section 7 of [protocol.md](protocol.md). Take a backup first if the vault folder is git-ignored; the script refuses `--apply` there unless `--force-ignored` is given.

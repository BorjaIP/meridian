# Skills

Seven commands. All of them except `/mdn-init` first check that Meridian is initialized (config with a vault, project resolved, `project.md` exists); if not, they say so, run init in auto mode (asking only for the vault path when the config is missing) and then continue. The project is the `project:` argument, otherwise the one whose `repo:` matches the current git repository.

Skills are instructions for a model: they are structurally tested (`tests/skills-test.sh`) but their behavior depends on the model that follows them. Notes written to the vault are in English. File format: [protocol.md](protocol.md).

## /mdn-init

```
/mdn-init [name:<slug>] [title:"..."] [description:"..."] [repo:<path>]
```

Creates `<vault>/meridian/<slug>/project.md` from the template. First run asks for the vault path and writes the config. The one-line description comes from the `description` argument or is derived from the repository (README, manifests, `CLAUDE.md`/`AGENTS.md`); if the evidence is insufficient it keeps a `TODO` placeholder and says why. Re-running only fills a placeholder description and changes nothing else.

## /mdn-add

```
/mdn-add "<title or description>" [project:<slug>] [owner:me|agent] [type:...] [priority:...] [acceptance:"..."]
/mdn-add "Update the deploy docs" priority:low
```

Records a `backlog` task and nothing else. Defaults: `owner::agent`, `priority::medium`, type inferred. Generates a unique kebab-case slug.

## /mdn-run

```
/mdn-run "<description>" [project:<slug>] [priority:...] [type:...]
/mdn-run task:<slug>
/mdn-run next
```

The single trigger of the flow. Writes the task as `in-progress` with a `**Run:**` block first, runs the work through ODD in the main thread (slug as the ODD feature name, `delivery` from the config), then fills the Run end and the `**Trace:**` block from git and `gh` via `mdn-trace.sh` and sets `review`. `task:<slug>` starts a backlog task or resumes an interrupted `in-progress` one (keeping the original start and base); `next` takes the first agent task in `backlog`. It never sets `done`, never toggles receipt-driven development, and does not push. Needs git and, for the work itself, Claude Code with gentle-ai ODD.

## /mdn-done

```
/mdn-done <slug> [note:"review comment"]
/mdn-done <slug> reopen:"reason"
```

Your decision after reviewing. Moves a `review` task to `done` (agent tasks need a Trace block) and adds your note if given. `reopen` sends it back to `in-progress` with the reason, keeping Run and Trace so `/mdn-run task:<slug>` resumes it.

## /mdn-daily

```
/mdn-daily
```

Read-only. Across active projects: tasks in `review`, your own `backlog`/`in-progress` tasks, and `blocked` tasks, with the trace link of each review item and the command to act on it.

## /mdn-status

```
/mdn-status [project:<slug>]
```

Read-only. A table of counts by status and owner per active project plus totals. Flags `in-progress` tasks started more than 24 hours ago as possibly stale (interrupted session).

## /mdn-archive

```
/mdn-archive [project:<slug>]
```

For every `done` task runs `mdn-log.sh archive`, which moves the block verbatim into the project's `logs/YYYY-MM.md` under a timestamped heading and removes it from `project.md` in one step. Problems (task missing, not done, already archived) are reported and that task is skipped. Nothing is deleted.

## Logs, digest and dashboard

`/mdn-add`, `/mdn-run`, `/mdn-done` and `/mdn-init` append one-line lifecycle events through `mdn-log.sh`; a missing or failing script only prints a warning. `/mdn-daily` and `/mdn-status` build their report from `mdn-index.sh` output instead of reading whole notes and never read `logs/`; `/mdn-status` suggests `/mdn-archive` past about 20 done tasks. `/mdn-init` creates `<vault>/meridian/dashboard.md` (Dataview queries) from `templates/Dashboard.md` only if it does not exist.

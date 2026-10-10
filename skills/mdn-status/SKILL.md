---
name: mdn-status
model: low
description: >
  Meridian dashboard skill. Read-only. Prints task counts by status and owner for every
  active project plus a total, and flags in-progress tasks whose run started more than 24
  hours ago as possibly stale. Use when the user says "show project status", "what's the
  state of my projects", "meridian dashboard", or runs `/mdn-status`.
---

## Invocation

```
/mdn-status [project:<slug>]
```

| Argument | Required | Description |
|---|---|---|
| `project` | no | Limit the output to one slug. Omit for all active projects. |

Format reference: `docs/protocol.md`. Primitives used: READ, GREP. This skill never writes anything.

## Init guard

Before the steps below, check that Meridian is initialized:

1. The config file `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md` exists and has a `vault:` value.
2. The project resolves (the `project:` argument; otherwise the project whose `repo:` frontmatter matches the current git toplevel; otherwise the kebab-case basename of the git toplevel) and `<vault>/meridian/<project>/project.md` exists.

If anything is missing, say in one line "Meridian is not initialized for this project; running /mdn-init first", run the `/mdn-init` steps inline in auto mode (no questions except the vault path when the config is missing), then continue the original command without making the user retype it.

Cross-project commands (`/mdn-daily`, `/mdn-status`) only require the config and at least one project. If there is none, apply this guard to the current repository; if the current directory is not a repository, say there is nothing to show and stop.

## Steps

1. READ `${XDG_CONFIG_HOME:-$HOME/.config}/meridian/config.md`; take `vault:`. (The init guard guarantees it exists.)
2. READ each `<vault>/meridian/*/project.md`; keep those with `status: active` (and the given slug, if any). If none, report that and stop.
3. For each project GREP the task lines (`/^- \[.\] #task/`) and count by `status::` (backlog, in-progress, review, done, blocked) and `owner::` (agent, me).
4. Staleness: for each `status::in-progress` task read `started <YYYY-MM-DD HH:MM>` from its `**Run:**` block and compare it with the current time (`date "+%Y-%m-%d %H:%M"`). If it is more than 24 hours older, or the task has no Run block, mark it `possibly stale` (a stale mark means the session may have been interrupted; resume with `/mdn-run task:<slug>`).
5. Print one block per project and a total:

```
## <title> (<slug>)

| Status      | Agent | Me |
|-------------|-------|----|
| backlog     |   N   |  N |
| in-progress |   N   |  N |
| review      |   N   |  N |
| blocked     |   N   |  N |
| done        |   N   |  N |

possibly stale: <slug> (started <YYYY-MM-DD HH:MM>)

-----------------------------------------
Total: <P> active project(s) · <B> backlog · <I> in-progress · <R> review · <K> blocked · <D> done
```

Omit zero rows and omit the stale line when there is nothing to flag.

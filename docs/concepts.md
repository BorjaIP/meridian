# Concepts

## What Meridian is

Meridian is a **human traceability ledger** over agent work. It answers three questions about every task: what was asked, when did it run, and where is the evidence.

It deliberately does not plan, schedule or execute. Those jobs belong to other tools:

| Concern | Owner |
|---|---|
| Planning, task breakdown, TDD, commits | gentle-ai ODD, which runs by default on every request in Claude Code |
| Agent memory | Engram |
| Human record: request, run, evidence, review | **Meridian** (a Markdown note in your vault) |

There are no gentle-ai workflow commands to learn. You describe the work; ODD handles it; Meridian records it. What each side produces is in the README section [How Meridian uses gentle-ai](../README.md#how-meridian-uses-gentle-ai), and the flow is drawn in [workflow.md](workflow.md).

## The vault and the repository

- The **vault** holds one note per project: `<vault>/meridian/<slug>/project.md`, with inline `#task` lines.
- The **repository** holds the work, including ODD's task documents under `odd/tasks/`. They always stay in the repository.
- The `**Trace:**` block of a task links the two: a Markdown link to the `odd/` document (a Windows UNC path, for WSL), plus branch, commits and pull request as text.

## Metadata comes from git

Dates, branch, commits, diff stat, pull request and the changed `odd/tasks/*.md` files are collected by `scripts/mdn-trace.sh` from `git` and `gh`. They are not taken from the model's own summary.

## Task states

```
backlog -> in-progress -> review -> done        (+ blocked)
```

| State | Meaning |
|---|---|
| `backlog` | Recorded, not started. |
| `in-progress` | A run started; the task has a `**Run:**` block. |
| `review` | The run ended; the human should look at the result. |
| `done` | The human accepted it (`/mdn-done`). |
| `blocked` | Cannot continue; a `**Note:**` says why. |

There is no approval gate before execution. The human checkpoint is `review`, after the work. The full transition table is in [protocol.md](protocol.md).

## Owners

`owner::agent` tasks are run with `/mdn-run`. `owner::me` tasks are yours; `/mdn-daily` lists them and `/mdn-done` closes them.

## Agent-agnostic scope

The note format and its state machine are plain Markdown and can be read or written by any tool; [protocol.md](protocol.md) is the contract. The skills and installers are not agent-agnostic: they exist for Claude Code and Codex, `/mdn-run` assumes the gentle-ai ODD workflow, and skills are instructions whose behavior depends on the model that follows them.

## Why "Meridian"

The Prime Meridian is a shared reference line. The vault note plays that role for humans: a fixed place where the request, the run and the evidence can be found, whichever agent did the work.

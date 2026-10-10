# Workflow

One task, from request to done. Format details are in [protocol.md](protocol.md).

## 1. Initialize (once per project)

```
/mdn-init name:my-app
```

The first run asks for the vault path and writes `~/.config/meridian/config.md`. It then creates `<vault>/meridian/my-app/project.md`, fills the one-line description from the repository (README, manifests, `CLAUDE.md`/`AGENTS.md`; it keeps a placeholder rather than invent one) and links the repository path in `repo:`. You can skip this step: any other command runs init automatically when needed.

## 2. Request

Either run immediately:

```
/mdn-run "add rate limiting to the login endpoint"
```

or queue it and run later:

```
/mdn-add "add rate limiting to the login endpoint" priority:high
/mdn-run task:add-login-rate-limit      # or: /mdn-run next
```

## 3. What `/mdn-run` does

1. Starts `mdn-trace.sh` to snapshot the branch and base commit.
2. Writes the task to `project.md` as `in-progress` with a `**Run:**` block, before any work.
3. Hands the request to ODD in the same session. ODD explores, writes `odd/tasks/<slug>.md` when the work is substantial, and makes work-unit commits.
4. Runs `mdn-trace.sh finish` to collect the end time, commits, diff stat, pull request and the changed `odd/` documents from git/gh.
5. Writes the `**Trace:**` block and sets `review`.

If the session is interrupted, the task stays `in-progress`; `/mdn-run task:<slug>` resumes it and keeps the original start and base. If ODD cannot continue, the task becomes `blocked` with a note.

## 4. Review and close

```
/mdn-daily                          # lists tasks in review, yours, and blocked
/mdn-done add-login-rate-limit      # accept, optionally note:"looks good"
/mdn-done add-login-rate-limit reopen:"also cover the API route"
```

`review` is your look at the result, not a verification. `/mdn-done` only records your decision.

## 5. Housekeeping

```
/mdn-status      # counts by status and owner; flags runs possibly interrupted
/mdn-archive     # move done tasks to TASK_HISTORY.md (verbatim, never deleted)
```

## Requirements recap

`/mdn-run` needs a git repository and, for real execution, Claude Code with gentle-ai v4 (ODD). Links to `odd/` documents are UNC paths for WSL.

#!/usr/bin/env bash
# mdn-lint.sh - validate Meridian project files against docs/protocol.md.
#
# Usage: mdn-lint.sh <project.md> [<project.md> ...]
#
# Prints one `file:line: message` diagnostic per problem and exits non-zero
# if any file has a problem. Silent and exit 0 when every file is valid.
# Requires only bash and awk.

set -u

if [ "$#" -eq 0 ]; then
  echo "usage: ${0##*/} <project.md> [<project.md> ...]" >&2
  exit 2
fi

status=0
for f in "$@"; do
  if [ ! -r "$f" ]; then
    echo "$f:0: cannot read file"
    status=1
    continue
  fi
  awk -v file="$f" '
    function err(line, msg) { printf "%s:%d: %s\n", file, line, msg; bad = 1 }

    # Return 1 when value v is one of the |-separated words in list.
    function oneof(v, list,    n, a, i) {
      n = split(list, a, "|")
      for (i = 1; i <= n; i++) if (a[i] == v) return 1
      return 0
    }

    # Validate the task collected so far, then reset the task state.
    function finish_task(    box_done) {
      if (!in_task) return
      in_task = 0

      # Required fields and allowed values.
      if (!("owner" in f_))    err(t_line, "missing field \"owner\"")
      else if (!oneof(f_["owner"], "me|agent"))
        err(t_line, "invalid owner \"" f_["owner"] "\" (me|agent)")
      if (!("priority" in f_)) err(t_line, "missing field \"priority\"")
      else if (!oneof(f_["priority"], "high|medium|low"))
        err(t_line, "invalid priority \"" f_["priority"] "\" (high|medium|low)")
      if (!("type" in f_))     err(t_line, "missing field \"type\"")
      else if (!oneof(f_["type"], "feature|fix|research|review|chore"))
        err(t_line, "invalid type \"" f_["type"] "\" (feature|fix|research|review|chore)")

      if (!("slug" in f_)) err(t_line, "missing field \"slug\"")
      else {
        s = f_["slug"]
        if (s !~ /^[a-z0-9]+(-[a-z0-9]+)*$/) err(t_line, "slug \"" s "\" is not kebab-case")
        if (s in seen) err(t_line, "duplicate slug \"" s "\" (first used on line " seen[s] ")")
        else seen[s] = t_line
      }

      if (!("status" in f_)) err(t_line, "missing field \"status\"")
      else {
        st = f_["status"]
        if (oneof(st, "planning|approved"))
          err(t_line, "retired state \"" st "\" (use backlog|in-progress|review|done|blocked)")
        else if (!oneof(st, "backlog|in-progress|review|done|blocked"))
          err(t_line, "invalid status \"" st "\" (backlog|in-progress|review|done|blocked)")
        else {
          # The checkbox mirrors the status: [x] if and only if done.
          if (st == "done" && !t_checked) err(t_line, "checkbox must be [x] when status is done")
          if (st != "done" && t_checked)  err(t_line, "checkbox must be [ ] when status is " st)
          if (st == "in-progress" && !has_run)
            err(t_line, "status in-progress requires **Run:**")
          if ((st == "review" || st == "done") && !has_trace && f_["owner"] != "me")
            err(t_line, "status " st " requires **Trace:**")
        }
      }
      delete f_
      has_run = has_trace = 0
    }

    BEGIN { bad = 0; in_task = 0; fm = 0 }

    # Frontmatter: must open on line 1 and close before the body.
    NR == 1 {
      if ($0 == "---") fm = 1
      else { err(1, "missing frontmatter (file must start with ---)"); fm = -1 }
      next
    }
    fm == 1 {
      if ($0 == "---") { fm = 2
        if (!has_project) err(NR, "frontmatter missing \"project\"")
        if (!has_status)  err(NR, "frontmatter missing \"status\"")
        next }
      if ($0 ~ /^project:[ ]*[^ ]/) has_project = 1
      if ($0 ~ /^status:/) {
        has_status = 1
        v = $0; sub(/^status:[ ]*/, "", v)
        if (!oneof(v, "active|paused|done|archived"))
          err(NR, "invalid project status \"" v "\" (active|paused|done|archived)")
      }
      next
    }

    # Ignore fenced code blocks (examples in documentation).
    /^```/ { fence = !fence; next }
    fence { next }

    # A task line starts a new task block and ends the previous one.
    /^- \[[ xX]\] #task([ ]|$)/ {
      finish_task()
      in_task = 1; t_line = NR
      t_checked = ($0 ~ /^- \[[xX]\]/)
      n = split($0, tok, /[ ]+/)
      for (i = 1; i <= n; i++)
        if (index(tok[i], "::") > 0) {
          k = substr(tok[i], 1, index(tok[i], "::") - 1)
          f_[k] = substr(tok[i], index(tok[i], "::") + 2)
        }
      next
    }

    # Indented lines belong to the current task; any other text ends it.
    in_task && /^[ \t]+\*\*Run:\*\*/   { has_run = 1;   next }
    in_task && /^[ \t]+\*\*Trace:\*\*/ { has_trace = 1; next }
    in_task && /^[ \t]/ { next }
    /^[ \t]*$/ { next }
    { finish_task() }

    END {
      if (fm == 1) err(NR, "frontmatter is not closed")
      finish_task()
      exit bad
    }
  ' "$f" || status=1
done
exit "$status"

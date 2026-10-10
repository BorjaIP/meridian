#!/usr/bin/env bash
# mdn-log.sh - append-only monthly logs for a Meridian project (docs/protocol.md, "Logs").
#
# Usage:
#   mdn-log.sh event   <project-dir> <event> <slug> [text...]
#   mdn-log.sh archive <project-dir> <project.md> <slug>
#
# event    appends `- <YYYY-MM-DD HH:MM> · <event> · <slug>[ · <text>]` to
#          <project-dir>/logs/<YYYY-MM>.md, creating the directory and the file
#          (header `# Log <YYYY-MM>`) when missing. `slug` may be `-` for
#          project-level events. Allowed events: init, created, run-started,
#          run-finished, blocked, review, done, reopened, archived, migrated.
# archive  moves the complete block of a done task from project.md to the month
#          log under `## <timestamp> · archived · <slug>`, verbatim, and removes
#          it (and one trailing blank line) from project.md. Both files are
#          written to temp files first and moved into place only on success.
#
# MDN_NOW="YYYY-MM-DD HH:MM" overrides the clock (tests).
# Exit status: 0 ok, 2 usage/argument error, 3 task missing or not done,
#              4 already archived in that month.
# Requires bash, awk, date, mv, mktemp.

set -u

die() { echo "${0##*/}: $*" >&2; exit "${2:-2}"; }

usage() {
  echo "usage: ${0##*/} event <project-dir> <event> <slug> [text...]" >&2
  echo "       ${0##*/} archive <project-dir> <project.md> <slug>" >&2
  exit 2
}

EVENTS=" init created run-started run-finished blocked review done reopened archived migrated "

now="${MDN_NOW:-$(date '+%Y-%m-%d %H:%M')}"
case "$now" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]) ;;
  *) die "invalid timestamp \"$now\" (expected YYYY-MM-DD HH:MM)" ;;
esac
month="${now:0:7}"

valid_slug() { [ "$1" = "-" ] || printf '%s' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; }

[ "$#" -ge 1 ] || usage
cmd="$1"; shift

case "$cmd" in
  event)
    [ "$#" -ge 3 ] || usage
    dir="$1"; ev="$2"; slug="$3"; shift 3
    [ -d "$dir" ] || die "not a directory: $dir"
    case "$EVENTS" in *" $ev "*) ;; *) die "invalid event \"$ev\"" ;; esac
    valid_slug "$slug" || die "invalid slug \"$slug\""
    line="- $now · $ev · $slug"
    [ "$#" -gt 0 ] && line="$line · $*"
    mkdir -p "$dir/logs" || die "cannot create $dir/logs"
    f="$dir/logs/$month.md"
    [ -e "$f" ] || printf '# Log %s\n\n' "$month" > "$f" || die "cannot write $f"
    printf '%s\n' "$line" >> "$f" || die "cannot write $f"
    ;;

  archive)
    [ "$#" -eq 3 ] || usage
    dir="$1"; proj="$2"; slug="$3"
    [ -d "$dir" ] || die "not a directory: $dir"
    [ -r "$proj" ] || die "cannot read $proj"
    valid_slug "$slug" && [ "$slug" != "-" ] || die "invalid slug \"$slug\""
    f="$dir/logs/$month.md"
    heading="## $now · archived · $slug"
    # Same slug already archived this month (any day/time).
    if [ -e "$f" ] && grep -qE "^## .* · archived · $slug\$" "$f"; then
      die "already archived in $month: $slug" 4
    fi

    tb="$(mktemp "$dir/.mdn-block.XXXXXX")" || die "cannot create temp file"
    tr_="$(mktemp "$dir/.mdn-rest.XXXXXX")" || { rm -f "$tb"; die "cannot create temp file"; }
    tl="$(mktemp "$dir/.mdn-log.XXXXXX")" || { rm -f "$tb" "$tr_"; die "cannot create temp file"; }
    cleanup() { rm -f "$tb" "$tr_" "$tl"; }

    # Split project.md into the task block and the rest.
    awk -v slug="$slug" -v blk="$tb" -v rest="$tr_" '
      function drop_one_blank(   i) {
        for (i = 2; i <= np; i++) print pend[i] > rest
        np = 0
      }
      mode == 0 && /^- \[[ xX]\] #task([ ]|$)/ {
        n = split($0, tok, /[ ]+/); hit = 0; isdone = 0
        for (i = 1; i <= n; i++) {
          if (tok[i] == "slug::" slug) hit = 1
          if (tok[i] == "status::done") isdone = 1
        }
        if (hit) {
          found = 1
          if (!($0 ~ /^- \[[xX]\]/ && isdone)) notdone = 1
          mode = 1; np = 0; print > blk; next
        }
      }
      mode == 1 {
        if ($0 ~ /^[ \t]+[^ \t]/) {
          for (i = 1; i <= np; i++) print pend[i] > blk
          np = 0; print > blk; next
        }
        if ($0 ~ /^[ \t]*$/) { pend[++np] = $0; next }
        drop_one_blank(); mode = 2
      }
      { print > rest }
      END {
        if (mode == 1) drop_one_blank()
        if (!found) exit 10
        if (notdone) exit 11
      }
    ' "$proj"
    rc=$?
    if [ "$rc" -eq 10 ] || [ "$rc" -eq 11 ]; then
      cleanup
      [ "$rc" -eq 10 ] && die "task not found: $slug" 3
      die "task is not done: $slug" 3
    elif [ "$rc" -ne 0 ]; then
      cleanup; die "cannot parse $proj" 3
    fi

    # Build the new month log: existing content (or header) + section.
    if [ -s "$f" ]; then cat "$f" > "$tl"; else printf '# Log %s\n\n' "$month" > "$tl"; fi
    if [ -n "$(tail -n 1 "$tl")" ]; then printf '\n' >> "$tl"; fi
    { printf '%s\n' "$heading"; cat "$tb"; printf '\n'; } >> "$tl"

    mkdir -p "$dir/logs" || { cleanup; die "cannot create $dir/logs"; }
    mv "$tl" "$f" || { cleanup; die "cannot write $f"; }
    mv "$tr_" "$proj" || { rm -f "$tb"; die "log written but cannot update $proj (task is now in both)" 3; }
    rm -f "$tb"
    ;;

  *) usage ;;
esac

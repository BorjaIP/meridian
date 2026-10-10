#!/usr/bin/env bash
# mdn-index.sh - deterministic digest of a Meridian project note.
#
# Usage: mdn-index.sh <project.md> [--now "YYYY-MM-DD HH:MM"] [--stale-hours 24] [--done-hint 20]
#
# Prints key=value lines (repeated keys carry one item per line, tab-separated
# fields), in this order:
#   project=<slug>
#   total=<n>
#   counts <status>=<n>          one line per status
#   owner_counts <owner>=<n>     me, agent
#   review=<slug> TAB <owner> TAB <priority> TAB <title> TAB trace=<link text>
#   blocked=<slug> TAB <owner> TAB <priority> TAB <title> TAB <note>
#   mine=<slug> TAB <status> TAB <priority> TAB <title>     owner::me, backlog|in-progress
#   stale=<slug> TAB <started | no-run>   in-progress agent tasks older than the threshold
#   done_count=<n>
#   archive_hint=yes             only when done_count > --done-hint
# It reads only the given file, never logs/. Requires bash and awk.
# Exit status: 0 ok, 2 usage error or unreadable file.

set -u

die() { echo "${0##*/}: $*" >&2; exit 2; }
usage() {
  echo "usage: ${0##*/} <project.md> [--now \"YYYY-MM-DD HH:MM\"] [--stale-hours N] [--done-hint N]" >&2
  exit 2
}

file=""; now=""; stale=24; hint=20
while [ "$#" -gt 0 ]; do
  case "$1" in
    --now)         [ "$#" -ge 2 ] || usage; now="$2"; shift 2 ;;
    --stale-hours) [ "$#" -ge 2 ] || usage; stale="$2"; shift 2 ;;
    --done-hint)   [ "$#" -ge 2 ] || usage; hint="$2"; shift 2 ;;
    --*) usage ;;
    *) [ -z "$file" ] || usage; file="$1"; shift ;;
  esac
done
[ -n "$file" ] || usage
[ -r "$file" ] || die "cannot read $file"
[ -n "$now" ] || now="$(date '+%Y-%m-%d %H:%M')"
case "$stale$hint" in ''|*[!0-9]*) die "--stale-hours and --done-hint must be integers" ;; esac

awk -v now="$now" -v stale="$stale" -v hint="$hint" '
  # Minutes since an epoch for "YYYY-MM-DD HH:MM", or -1 when malformed.
  function mins(ts,    p, n, y, m, d, era, yoe, doy, doe) {
    n = split(ts, p, /[- :]/)
    if (n != 5 || ts !~ /^[0-9]+-[0-9]+-[0-9]+ [0-9]+:[0-9]+$/) return -1
    y = p[1] + 0; m = p[2] + 0; d = p[3] + 0
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return ((era * 146097 + doe) * 24 + p[4]) * 60 + p[5]
  }

  function finish_task(    k, line, age) {
    if (!in_task) return
    in_task = 0
    st = f_["status"]; ow = f_["owner"]; sl = f_["slug"]; pr = f_["priority"]
    total++; cnt[st]++; own[ow]++
    if (st == "review")  rev[++nrev] = sl "\t" ow "\t" pr "\t" title "\ttrace=" trace
    if (st == "blocked") blk[++nblk] = sl "\t" ow "\t" pr "\t" title "\t" note
    if (ow == "me" && (st == "backlog" || st == "in-progress"))
      mine[++nmine] = sl "\t" st "\t" pr "\t" title
    if (st == "in-progress" && ow == "agent") {
      s = (has_run ? mins(started) : -1)
      if (s < 0) stl[++nstale] = sl "\tno-run"
      else if (nowm - s > stale * 60) stl[++nstale] = sl "\t" started
    }
    delete f_
    title = note = trace = started = ""; has_run = 0
  }

  BEGIN {
    nowm = mins(now)
    if (nowm < 0) { print "invalid --now (expected YYYY-MM-DD HH:MM)" > "/dev/stderr"; bad = 1; exit 2 }
    nst = split("backlog in-progress review done blocked", sts, " ")
  }
  NR == 1 { if ($0 == "---") fm = 1; next }
  fm == 1 {
    if ($0 == "---") { fm = 2; next }
    if ($0 ~ /^project:/) { v = $0; sub(/^project:[ ]*/, "", v); sub(/[ ]+#.*$/, "", v); sub(/[ ]+$/, "", v); proj = v }
    next
  }
  /^```/ { fence = !fence; next }
  fence { next }

  /^- \[[ xX]\] #task([ ]|$)/ {
    finish_task()
    in_task = 1
    n = split($0, tok, /[ ]+/)
    for (i = 1; i <= n; i++)
      if (index(tok[i], "::") > 0)
        f_[substr(tok[i], 1, index(tok[i], "::") - 1)] = substr(tok[i], index(tok[i], "::") + 2)
    next
  }
  in_task && /^[ \t]+\*\*Title:\*\*/ { v = $0; sub(/^[ \t]+\*\*Title:\*\*[ ]*/, "", v); title = v; next }
  in_task && /^[ \t]+\*\*Note:\*\*/  { v = $0; sub(/^[ \t]+\*\*Note:\*\*[ ]*/, "", v);  note = v; next }
  in_task && /^[ \t]+\*\*Run:\*\*/ {
    has_run = 1
    v = $0; sub(/^[ \t]+\*\*Run:\*\*[ ]*started[ ]+/, "", v)
    started = substr(v, 1, 16)
    next
  }
  in_task && /^[ \t]+\*\*Trace:\*\*/ {
    v = $0
    if (match(v, /\[[^]]*\]\(/)) trace = substr(v, RSTART + 1, RLENGTH - 3)
    next
  }
  in_task && /^[ \t]/ { next }
  /^[ \t]*$/ { next }
  { finish_task() }

  END {
    if (bad) exit 2
    finish_task()
    print "project=" proj
    print "total=" total + 0
    for (i = 1; i <= nst; i++) print "counts " sts[i] "=" cnt[sts[i]] + 0
    print "owner_counts me=" own["me"] + 0
    print "owner_counts agent=" own["agent"] + 0
    for (i = 1; i <= nrev; i++)   print "review=" rev[i]
    for (i = 1; i <= nblk; i++)   print "blocked=" blk[i]
    for (i = 1; i <= nmine; i++)  print "mine=" mine[i]
    for (i = 1; i <= nstale; i++) print "stale=" stl[i]
    print "done_count=" cnt["done"] + 0
    if (cnt["done"] + 0 > hint) print "archive_hint=yes"
  }
' "$file"

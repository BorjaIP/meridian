#!/usr/bin/env bash
# mdn-migrate.sh - convert an OLD Meridian project layout to the single-file layout.
#
# Usage:
#   mdn-migrate.sh <project-dir> --dest <dir> [--repo <path>]   dry run on a copy
#   mdn-migrate.sh <project-dir> --apply [--repo <path>]        in place
#
# Dry run copies <project-dir> into <dir> (must not exist or be empty) and migrates
# the copy; the source is never modified. --apply requires a clean git tree for
# <project-dir> (when it is inside a repository). Legacy files are moved to
# <project-dir>/archive-legacy/, never deleted. See docs/protocol.md section 7.
# Requires only bash, awk, sed, grep and coreutils.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lint="$here/mdn-lint.sh"

usage() {
  echo "usage: ${0##*/} <project-dir> --dest <dir> [--repo <path>]" >&2
  echo "       ${0##*/} <project-dir> --apply [--repo <path>]" >&2
  exit 2
}
die() { echo "error: $*" >&2; exit 1; }

src=""; dest=""; apply=0; repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)  [ "$#" -ge 2 ] || usage; dest="$2"; shift 2 ;;
    --repo)  [ "$#" -ge 2 ] || usage; repo="$2"; shift 2 ;;
    --apply) apply=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$src" ] || usage; src="$1"; shift ;;
  esac
done
[ -n "$src" ] || usage
if [ "$apply" -eq 1 ] && [ -n "$dest" ]; then usage; fi
if [ "$apply" -eq 0 ] && [ -z "$dest" ]; then usage; fi

[ -d "$src" ] || die "not a directory: $src"
src="$(cd "$src" && pwd)"
[ -f "$src/project.md" ] || die "no project.md in $src"

# Already migrated: archive-legacy/ exists and every task line has a slug.
if [ -d "$src/archive-legacy" ] \
   && ! grep -E '^- \[[ xX]\] #task' "$src/project.md" | grep -qv 'slug::'; then
  echo "nothing to migrate: $src is already in the new layout"
  exit 0
fi

work="$src"
if [ "$apply" -eq 1 ]; then
  if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git -C "$src" status --porcelain -- . 2>/dev/null)" ]; then
      die "uncommitted changes in $src; commit or stash them before --apply"
    fi
  fi
  echo "Applying in place: $src"
  echo "  will rewrite project.md and move legacy files into archive-legacy/"
else
  if [ -e "$dest" ]; then
    [ -d "$dest" ] || die "--dest exists and is not a directory: $dest"
    [ -z "$(ls -A "$dest")" ] || die "--dest is not empty: $dest"
  fi
  mkdir -p "$dest" || die "cannot create $dest"
  dest="$(cd "$dest" && pwd)"
  case "$dest/" in "$src"/*) die "--dest must not be inside the source" ;; esac
  cp -a "$src"/. "$dest"/ || die "copy failed"
  work="$dest"
  echo "Dry run: migrated copy at $dest (source untouched)"
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
newmd="$scratch/new.md"; rep="$scratch/report.tsv"

# Convert project.md -> new.md; report lines go to rep (tab separated).
awk -v repo="$repo" -v outfile="$newmd" -v repfile="$rep" '
  function warn(m) { printf "WARN\t%s\n", m > repfile }
  function slugify(t,    s, cut, i, p) {
    s = t
    if (match(s, /^(Verify|Review):[ ]*/)) s = substr(s, RLENGTH + 1)
    s = tolower(s)
    gsub(/[^a-z0-9]+/, "-", s); sub(/^-+/, "", s); sub(/-+$/, "", s)
    if (length(s) > 50) {
      cut = substr(s, 1, 50)
      if (substr(s, 51, 1) != "-") {
        p = 0
        for (i = 50; i >= 1; i--) if (substr(cut, i, 1) == "-") { p = i; break }
        if (p >= 20) cut = substr(cut, 1, p - 1)
      }
      sub(/-+$/, "", cut); s = cut
    }
    if (s == "") s = "task"
    return s
  }
  function finish_task(    st, sl, base, n, line, note) {
    if (!in_task) return
    in_task = 0
    ntasks++
    base = slugify(ttitle); sl = base; n = 2
    while (sl in used) sl = base "-" n++
    used[sl] = 1
    if (ttitle == "") warn("task #" ntasks " has no Title; slug set to " sl)
    printf "SLUG\t%s\t%s\n", ttitle, sl > repfile
    st = f_status
    if (st == "planning" || st == "approved") {
      printf "STATUS\t%s\t%s\tbacklog\n", sl, st > repfile
      st = "backlog"
    } else if (st == "") warn("task " sl " has no status")
    if (f_priority == "") { f_priority = "medium"; warn("task " sl " had no priority; set to medium") }
    line = "- [" (st == "done" ? "x" : " ") "] #task"
    if (f_owner != "")    line = line " owner::" f_owner
    if (st != "")         line = line " status::" st
    line = line " priority::" f_priority
    if (f_type != "")     line = line " type::" f_type
    line = line " slug::" sl f_extra
    body = line "\n" tbody
    note = ""
    if (t_art != "")  note = "artifact " t_art
    if (t_tnote != "") note = note (note != "" ? "; " : "") "task note " t_tnote
    if (note != "") note = "Legacy links: " note
    if (f_status == "planning") note = note (note != "" ? "; " : "") "was in planning before migration"
    if (note != "") body = body "  **Note:** " note "\n"
    tasks_out = tasks_out (tasks_out != "" ? "\n" : "") body
  }
  function start_task(l,    rest, n, tok, i, k, v) {
    in_task = 1; tbody = ""; ttitle = ""; t_art = ""; t_tnote = ""
    f_owner = f_status = f_priority = f_type = f_extra = ""
    rest = l; sub(/^- \[[ xX]\] #task/, "", rest)
    n = split(rest, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      if (tok[i] == "") continue
      if (index(tok[i], "::") == 0) { f_extra = f_extra " " tok[i]; continue }
      k = substr(tok[i], 1, index(tok[i], "::") - 1)
      v = substr(tok[i], index(tok[i], "::") + 2)
      if (k == "owner") f_owner = v
      else if (k == "status") f_status = v
      else if (k == "priority") f_priority = v
      else if (k == "type") f_type = v
      else if (k == "slug") { }
      else f_extra = f_extra " " tok[i]
    }
  }
  BEGIN { fm = 0 }
  NR == 1 && $0 == "---" { fm = 1; next }
  fm == 1 {
    if ($0 == "---") { fm = 2; next }
    if ($0 ~ /^created:/) next
    fl[++nfl] = $0
    if ($0 ~ /^repo:/) has_repo = 1
    next
  }
  /^```/ { fence = !fence }
  fence { next }
  /^- \[[ xX]\] #task([ \t]|$)/ { finish_task(); start_task($0); next }
  in_task && /^[ \t]/ {
    t = $0; sub(/^[ \t]+/, "", t)
    if (t ~ /^\*\*Title:\*\*/) { ttitle = t; sub(/^\*\*Title:\*\*[ ]*/, "", ttitle); tbody = tbody $0 "\n" }
    else if (t ~ /^\*\*Artifact:\*\*/)  { t_art = t;  sub(/^\*\*Artifact:\*\*[ ]*/, "", t_art) }
    else if (t ~ /^\*\*Task note:\*\*/) { t_tnote = t; sub(/^\*\*Task note:\*\*[ ]*/, "", t_tnote) }
    else tbody = tbody $0 "\n"
    next
  }
  /^[ \t]*$/ { next }
  {
    finish_task()
    if ($0 ~ /^## /) seen_h2 = 1
    else if ($0 ~ /^# / && h1 == "" && !seen_h2) { h1 = $0; sub(/^# /, "", h1) }
    else if ($0 ~ /^> / && !seen_h2 && desc == "") desc = $0
  }
  END {
    finish_task()
    if (desc == "" || desc ~ /^> TODO/) {
      if (desc == "") warn("no description found; added a TODO placeholder")
      else warn("description is still a TODO placeholder; fill it in")
      desc = "> TODO: add a one-line description of this project."
    }
    printf "COUNT\t%d\n", ntasks > repfile
    print "---" > outfile
    for (i = 1; i <= nfl; i++) {
      print fl[i] > outfile
      if (fl[i] ~ /^status:/ && repo != "" && !has_repo) print "repo: " repo > outfile
    }
    print "---" > outfile
    print "# " h1 "\n\n" desc "\n\n---\n\n## Tasks\n" > outfile
    printf "%s", tasks_out > outfile
  }
' "$work/project.md" || die "conversion failed"
[ -s "$newmd" ] || die "conversion produced no output"

al="$work/archive-legacy"
[ ! -e "$al/project.legacy.md" ] || die "$al/project.legacy.md already exists; refusing to overwrite"
mkdir -p "$al"
cp "$work/project.md" "$al/project.legacy.md"
cat "$newmd" > "$work/project.md"

# Move legacy files (never delete).
moved=0; movelist=""
shopt -s nullglob dotglob
movefile() { # movefile <relative source> <relative target under archive-legacy>
  mkdir -p "$(dirname "$al/$2")"
  mv "$work/$1" "$al/$2" && { moved=$((moved + 1)); movelist="$movelist  $1 -> archive-legacy/$2"$'\n'; }
}
for p in "$work"/plans/*; do movefile "plans/${p##*/}" "plans/${p##*/}"; done
for p in "$work"/tasks/*; do
  b="${p##*/}"
  if [ "$b" = "history.md" ]; then movefile "tasks/$b" "tasks-history.md"
  else movefile "tasks/$b" "tasks/$b"; fi
done
for b in REVIEW.md GOAL.md PROGRESS.md checkpoints; do
  [ -e "$work/$b" ] && movefile "$b" "$b"
done
shopt -u nullglob dotglob

# Report.
count="$(awk -F'\t' '$1=="COUNT"{print $2}' "$rep")"
echo
echo "== Migration report =="
echo "Tasks converted: $count"
echo "Slugs assigned (old title -> slug):"
awk -F'\t' '$1=="SLUG"{printf "  %s -> %s\n", $2, $3}' "$rep"
echo "Status changes:"
if grep -q '^STATUS' "$rep"; then
  awk -F'\t' '$1=="STATUS"{printf "  %s: %s -> %s\n", $2, $3, $4}' "$rep"
else echo "  (none)"; fi
echo "Files moved to archive-legacy/: $moved"
printf '%s' "$movelist"
echo "  project.md -> archive-legacy/project.legacy.md (copy; new project.md written)"
echo "Warnings:"
if grep -q '^WARN' "$rep"; then
  awk -F'\t' '$1=="WARN"{printf "  warning: %s\n", $2}' "$rep"
else echo "  (none)"; fi

echo
if bash "$lint" "$work/project.md"; then
  echo "Lint: ok ($work/project.md)"
else
  echo "Lint: FAILED for $work/project.md" >&2
  exit 1
fi

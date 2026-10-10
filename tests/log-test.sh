#!/usr/bin/env bash
# Tests scripts/mdn-log.sh against throwaway project directories.
# Usage: bash tests/log-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log="$root/scripts/mdn-log.sh"
lint="bash $root/scripts/mdn-lint.sh"
fx="$root/tests/fixtures"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$2" = 0 ]; then pass "$1"; else bad "$1"; fi; }
# same <file> <expected text>: file content equals the text exactly.
same() { [ "$(cat "$1"; printf x)" = "$(printf '%s' "$2"; printf x)" ]; }

SEP=' · '

# 1. First event creates logs/, the month file and the header.
p="$tmp/proj"; mkdir -p "$p"
MDN_NOW="2026-10-10 14:05" "$log" event "$p" created fix-login "Created by me"; rc=$?
check "event: exit 0" "$rc"
same "$p/logs/2026-10.md" "# Log 2026-10

- 2026-10-10 14:05${SEP}created${SEP}fix-login${SEP}Created by me
"; check "event: creates dir, file, header and line" "$?"

# 2. Second event appends; text is optional and joined from many args.
MDN_NOW="2026-10-10 15:00" "$log" event "$p" run-started fix-login
MDN_NOW="2026-10-11 09:30" "$log" event "$p" blocked fix-login waiting for access
same "$p/logs/2026-10.md" "# Log 2026-10

- 2026-10-10 14:05${SEP}created${SEP}fix-login${SEP}Created by me
- 2026-10-10 15:00${SEP}run-started${SEP}fix-login
- 2026-10-11 09:30${SEP}blocked${SEP}fix-login${SEP}waiting for access
"; check "event: second and third event append" "$?"

# 3. Month rollover creates a new file and leaves the old one alone.
before="$(cksum < "$p/logs/2026-10.md")"
MDN_NOW="2026-11-01 00:01" "$log" event "$p" done fix-login
same "$p/logs/2026-11.md" "# Log 2026-11

- 2026-11-01 00:01${SEP}done${SEP}fix-login
"; check "rollover: new month file" "$?"
[ "$before" = "$(cksum < "$p/logs/2026-10.md")" ]; check "rollover: old month untouched" "$?"

# 4. Project-level events use '-' as slug; every allowed event works.
for e in init created run-started run-finished blocked review done reopened archived migrated; do
  MDN_NOW="2026-12-01 10:00" "$log" event "$p" "$e" - >/dev/null 2>&1 || { bad "event: $e rejected"; }
done
[ "$(grep -c "^- 2026-12-01 10:00${SEP}" "$p/logs/2026-12.md")" = 10 ]; check "event: all ten allowed events" "$?"
grep -qxF -- "- 2026-12-01 10:00${SEP}init${SEP}-" "$p/logs/2026-12.md"; check "event: '-' slug kept" "$?"

# 5. Invalid event: exit 2 and nothing created.
q="$tmp/invalid"; mkdir -p "$q"
MDN_NOW="2026-10-10 14:05" "$log" event "$q" exploded fix-login >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && [ ! -e "$q/logs" ]; check "event: invalid event exits 2, creates nothing" "$?"
"$log" event >/dev/null 2>&1; [ $? = 2 ]; check "event: missing args exit 2" "$?"
"$log" bogus >/dev/null 2>&1; [ $? = 2 ]; check "unknown subcommand exits 2" "$?"
MDN_NOW="2026-10-10 14:05" "$log" event "$tmp/nope" created x >/dev/null 2>&1; [ $? = 2 ]; check "event: missing project dir exits 2" "$?"
MDN_NOW="nonsense" "$log" event "$q" created x >/dev/null 2>&1; [ $? = 2 ]; check "event: bad MDN_NOW exits 2" "$?"

# 6. Real clock when MDN_NOW is unset.
r="$tmp/clock"; mkdir -p "$r"
env -u MDN_NOW "$log" event "$r" init - 
grep -qE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}${SEP}init${SEP}-$" "$r"/logs/*.md; check "event: real clock timestamp format" "$?"

# 7. Archive moves the block and removes it from project.md.
a="$tmp/arch"; mkdir -p "$a"; cp "$fx/valid.md" "$a/project.md"
MDN_NOW="2026-10-12 08:15" "$log" archive "$a" "$a/project.md" compare-parsers; rc=$?
check "archive: exit 0" "$rc"
same "$a/logs/2026-10.md" "# Log 2026-10

## 2026-10-12 08:15${SEP}archived${SEP}compare-parsers
- [x] #task owner::agent status::done priority::low type::research slug::compare-parsers
  **Title:** Compare parsers
  **Description:** Pick a parser.
  **Run:** started 2026-10-09 10:00${SEP}ended 2026-10-09 11:00${SEP}repo /home/user/projects/sample${SEP}branch main
  **Trace:** [notes](\\\\wsl.localhost\\Arch\\home\\user\\notes.md)${SEP}commits abc1234

"; check "archive: verbatim block under dated heading" "$?"
! grep -q 'compare-parsers' "$a/project.md"; check "archive: block removed from project.md" "$?"
diff <(grep -v -e '^$' "$fx/valid.md" | grep -v -e 'compare-parsers' -e 'Compare parsers' -e 'Pick a parser' -e 'started 2026-10-09 10:00' -e '\[notes\]') <(grep -v '^$' "$a/project.md") >/dev/null; check "archive: other tasks untouched" "$?"
out="$($lint "$a/project.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ]; check "archive: lint still OK on project.md" "$?"
# One trailing blank line removed, so tasks stay separated by exactly one.
! grep -Pzq '\n\n\n' "$a/project.md"; check "archive: no double blank lines" "$?"

# 8. Archiving a task that is not done (or missing) exits 3 and changes nothing.
cp "$fx/valid.md" "$a/project.md"; rm -rf "$a/logs"
sum="$(cksum < "$a/project.md")"
MDN_NOW="2026-10-12 08:15" "$log" archive "$a" "$a/project.md" fix-login >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && [ "$sum" = "$(cksum < "$a/project.md")" ] && [ ! -e "$a/logs" ]; check "archive: non-done task exits 3, unchanged" "$?"
MDN_NOW="2026-10-12 08:15" "$log" archive "$a" "$a/project.md" ghost >/dev/null 2>&1; rc=$?
[ "$rc" = 3 ] && [ "$sum" = "$(cksum < "$a/project.md")" ] && [ ! -e "$a/logs" ]; check "archive: missing slug exits 3, unchanged" "$?"

# 9. Duplicate archive in the same month exits 4 and changes nothing.
MDN_NOW="2026-10-12 08:15" "$log" archive "$a" "$a/project.md" compare-parsers
cp "$fx/valid.md" "$a/project.md"
sum="$(cksum < "$a/project.md")"; lsum="$(cksum < "$a/logs/2026-10.md")"
MDN_NOW="2026-10-20 09:00" "$log" archive "$a" "$a/project.md" compare-parsers >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && [ "$sum" = "$(cksum < "$a/project.md")" ] && [ "$lsum" = "$(cksum < "$a/logs/2026-10.md")" ]; check "archive: duplicate slug exits 4, unchanged" "$?"

# 10. Archive after events: sections separated by a blank line; last task in file.
b="$tmp/mixed"; mkdir -p "$b"
cat > "$b/project.md" <<'MD'
---
title: T
project: t
status: active
---
# T

## Tasks

- [ ] #task owner::me status::backlog priority::low type::chore slug::keep-me
  **Title:** Keep me

- [x] #task owner::me status::done priority::low type::chore slug::last-one
  **Title:** Last one
  **Description:** At the end of the file.
MD
MDN_NOW="2026-10-12 08:00" "$log" event "$b" created keep-me
MDN_NOW="2026-10-12 08:15" "$log" archive "$b" "$b/project.md" last-one; rc=$?
check "archive: last task in file" "$rc"
grep -qxF "## 2026-10-12 08:15${SEP}archived${SEP}last-one" "$b/logs/2026-10.md" && [ "$(sed -n '3p' "$b/logs/2026-10.md")" = "- 2026-10-12 08:00${SEP}created${SEP}keep-me" ] && [ -z "$(sed -n '4p' "$b/logs/2026-10.md")" ]; check "archive: blank line between events and section" "$?"
out="$($lint "$b/project.md" 2>&1)"; [ -z "$out" ]; check "archive: lint OK when last task removed" "$?"
grep -q 'keep-me' "$b/project.md"; check "archive: neighbour kept" "$?"

# 11. Paths with spaces.
s="$tmp/with space/my project"; mkdir -p "$s"; cp "$fx/valid.md" "$s/project.md"
MDN_NOW="2026-10-12 08:15" "$log" event "$s" init - ; rc=$?
check "spaces: event" "$rc"
MDN_NOW="2026-10-12 08:15" "$log" archive "$s" "$s/project.md" compare-parsers; rc=$?
check "spaces: archive" "$rc"
grep -q 'archived' "$s/logs/2026-10.md" && ! grep -q compare-parsers "$s/project.md"; check "spaces: results correct" "$?"
ls "$s" | grep -qv -e '^logs$' -e '^project.md$' && bad "spaces: stray temp files left" || pass "spaces: no stray temp files"

if [ "$fail" -eq 0 ]; then echo "all tests passed"; else echo "$fail test(s) failed"; exit 1; fi

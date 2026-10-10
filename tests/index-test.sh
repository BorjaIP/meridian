#!/usr/bin/env bash
# Tests scripts/mdn-index.sh.
# Usage: bash tests/index-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
idx="$root/scripts/mdn-index.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$2" = 0 ]; then pass "$1"; else bad "$1"; fi; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
T="$(printf '\t')"
D=' · '

cat > "$tmp/project.md" <<MD
---
title: Digest
project: digest            # kebab-case
status: active
tags:
  - project
---
# Digest

## Tasks

- [ ] #task owner::me status::backlog priority::high type::chore slug::mine-backlog
  **Title:** Mine backlog
  **Description:** Mine.

- [ ] #task owner::me status::in-progress priority::medium type::chore slug::mine-wip
  **Title:** Mine WIP
  **Run:** started 2026-10-01 08:00${D}ended${D}repo /r${D}branch main

- [ ] #task owner::agent status::in-progress priority::high type::feature slug::boundary
  **Title:** Exactly 24h
  **Run:** started 2026-10-09 15:00${D}ended${D}repo /r${D}branch main

- [ ] #task owner::agent status::in-progress priority::high type::feature slug::stale-one
  **Title:** One minute over
  **Run:** started 2026-10-09 14:59${D}ended${D}repo /r${D}branch main

- [ ] #task owner::agent status::in-progress priority::low type::fix slug::no-run
  **Title:** No run block

- [ ] #task owner::agent status::review priority::high type::fix slug::fix-login
  **Title:** Fix login
  **Run:** started 2026-10-09 09:00${D}ended 2026-10-09 09:42${D}repo /r${D}branch main
  **Trace:** [odd/tasks/fix-login.md](\\\\wsl.localhost\\x\\fix-login.md)${D}commits a1b2c3d

- [ ] #task owner::me status::review priority::medium type::review slug::read-report
  **Title:** Read report

- [ ] #task owner::agent status::blocked priority::medium type::feature slug::pick-parser
  **Title:** Pick a parser
  **Note:** waiting for the user

- [ ] #task owner::me status::blocked priority::low type::chore slug::no-note
  **Title:** Blocked without note

- [x] #task owner::agent status::done priority::low type::chore slug::done-one
  **Title:** Done one

- [x] #task owner::agent status::done priority::low type::chore slug::done-two
  **Title:** Done two
MD

NOW="2026-10-10 15:00"
out="$("$idx" "$tmp/project.md" --now "$NOW")"; rc=$?
check "digest: exit 0" "$rc"

has "$out" "project=digest"; check "project slug (comment stripped)" "$?"
has "$out" "total=11"; check "total" "$?"
for c in backlog=1 in-progress=4 review=2 done=2 blocked=2; do
  has "$out" "counts $c"; check "counts $c" "$?"
done
has "$out" "owner_counts me=4" && has "$out" "owner_counts agent=7"; check "owner counts" "$?"
[ "$(printf '%s\n' "$out" | grep -c '^review=')" = 2 ]; check "two review lines" "$?"
has "$out" "review=fix-login${T}agent${T}high${T}Fix login${T}trace=odd/tasks/fix-login.md"; check "review line with trace" "$?"
has "$out" "review=read-report${T}me${T}medium${T}Read report${T}trace="; check "review line without trace" "$?"
has "$out" "blocked=pick-parser${T}agent${T}medium${T}Pick a parser${T}waiting for the user"; check "blocked with note" "$?"
has "$out" "blocked=no-note${T}me${T}low${T}Blocked without note${T}"; check "blocked without note" "$?"
has "$out" "mine=mine-backlog${T}backlog${T}high${T}Mine backlog"; check "mine backlog" "$?"
has "$out" "mine=mine-wip${T}in-progress${T}medium${T}Mine WIP"; check "mine in-progress" "$?"
[ "$(printf '%s\n' "$out" | grep -c '^mine=')" = 2 ]; check "mine only backlog/in-progress owner me" "$?"
has "$out" "stale=stale-one${T}2026-10-09 14:59"; check "stale one minute over" "$?"
! printf '%s\n' "$out" | grep -q '^stale=boundary'; check "exactly 24h is not stale" "$?"
has "$out" "stale=no-run${T}no-run"; check "no Run block is stale" "$?"
! printf '%s\n' "$out" | grep -q '^stale=mine-wip'; check "owner::me never stale" "$?"
[ "$(printf '%s\n' "$out" | grep -c '^stale=')" = 2 ]; check "exactly two stale lines" "$?"
has "$out" "done_count=2"; check "done_count" "$?"
! printf '%s\n' "$out" | grep -q '^archive_hint'; check "no archive hint under threshold" "$?"

# Determinism.
[ "$out" = "$("$idx" "$tmp/project.md" --now "$NOW")" ]; check "deterministic output" "$?"

# Stale threshold option: 100h makes mine-wip irrelevant and no stale agent runs but no-run.
o2="$("$idx" "$tmp/project.md" --now "$NOW" --stale-hours 100)"
[ "$(printf '%s\n' "$o2" | grep -c '^stale=')" = 1 ] && has "$o2" "stale=no-run${T}no-run"; check "--stale-hours changes threshold" "$?"
o3="$("$idx" "$tmp/project.md" --now "2026-10-10 14:59")"
! printf '%s\n' "$o3" | grep -q '^stale=stale-one'; check "now earlier: boundary moves" "$?"
o4="$("$idx" "$tmp/project.md" --now "2026-10-10 15:01")"
has "$o4" "stale=boundary${T}2026-10-09 15:00"; check "one minute past 24h becomes stale" "$?"

# Archive hint: strictly greater than the hint.
o="$("$idx" "$tmp/project.md" --now "$NOW" --done-hint 2)"
! printf '%s\n' "$o" | grep -q '^archive_hint'; check "done_count == hint: no hint" "$?"
o="$("$idx" "$tmp/project.md" --now "$NOW" --done-hint 1)"
has "$o" "archive_hint=yes"; check "done_count > hint: hint yes" "$?"

# Logs are never read: add a logs dir with task-like garbage, output must not change.
mkdir -p "$tmp/logs"
printf -- '- [x] #task owner::me status::done priority::low type::chore slug::ghost\n' > "$tmp/logs/2026-10.md"
chmod 000 "$tmp/logs/2026-10.md" 2>/dev/null
[ "$out" = "$("$idx" "$tmp/project.md" --now "$NOW")" ]; check "logs/ ignored" "$?"
chmod 600 "$tmp/logs/2026-10.md" 2>/dev/null

# Errors.
"$idx" "$tmp/missing.md" >/dev/null 2>&1; [ $? = 2 ]; check "missing file exits 2" "$?"
"$idx" >/dev/null 2>&1; [ $? = 2 ]; check "no args exits 2" "$?"
"$idx" "$tmp/project.md" --bogus >/dev/null 2>&1; [ $? = 2 ]; check "unknown option exits 2" "$?"
"$idx" "$tmp/project.md" --now garbage >/dev/null 2>&1; [ $? = 2 ]; check "bad --now exits 2" "$?"

# Real clock default and paths with spaces.
mkdir -p "$tmp/with space"; cp "$tmp/project.md" "$tmp/with space/project.md"
o="$("$idx" "$tmp/with space/project.md")"; rc=$?
check "spaces: works with real clock" "$rc"
has "$o" "project=digest"; check "spaces: output ok" "$?"

# Empty task list.
printf -- '---\nproject: empty\nstatus: active\n---\n# E\n\n## Tasks\n' > "$tmp/empty.md"
o="$("$idx" "$tmp/empty.md" --now "$NOW")"
has "$o" "total=0" && has "$o" "counts backlog=0" && has "$o" "done_count=0"; check "empty project: zero counts" "$?"

if [ "$fail" -eq 0 ]; then echo "all tests passed"; else echo "$fail test(s) failed"; exit 1; fi

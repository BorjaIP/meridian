#!/usr/bin/env bash
# Tests install.sh against a temporary HOME using the local checkout as source.
# Never touches the real HOME and never uses the network.
# Usage: bash tests/install-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inst="$root/install.sh"
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# run_install <home> [args...] -> sets $out and $rc
run_install() {
  local h="$1"; shift
  out="$(HOME="$h" XDG_CONFIG_HOME= bash "$inst" --source "$root" "$@" 2>&1)"; rc=$?
}
newhome() { local h; h="$(mktemp -d "$work/home.XXXXXX")"; echo "$h"; }
sum() { (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | xargs -r md5sum; find . | LC_ALL=C sort) | md5sum; }

skills=(mdn-add mdn-archive mdn-daily mdn-done mdn-init mdn-run mdn-status)

# 1. Fresh claude install.
h="$(newhome)"; run_install "$h"
if [ "$rc" -eq 0 ]; then pass "fresh install exits 0"; else bad "fresh install exit $rc: $out"; fi
ok=1; for s in "${skills[@]}"; do [ -s "$h/.claude/skills/$s/SKILL.md" ] || ok=0; done
[ "$ok" -eq 1 ] && pass "7 skills installed for claude" || bad "missing skills under .claude/skills"
ok=1; for s in mdn-lint.sh mdn-trace.sh mdn-migrate.sh; do [ -x "$h/.config/meridian/scripts/$s" ] || ok=0; done
[ "$ok" -eq 1 ] && pass "scripts installed and executable" || bad "scripts missing or not executable"
[ -s "$h/.config/meridian/templates/Project.md" ] && pass "template installed" || bad "template missing"
[ ! -e "$h/.codex" ] && pass "claude install does not touch .codex" || bad ".codex created by claude install"
if grep -q '^model: haiku' "$h/.claude/skills/mdn-add/SKILL.md" \
   && grep -q '^model: sonnet' "$h/.claude/skills/mdn-run/SKILL.md"; then
  pass "model hints rewritten for claude"
else bad "model hints not rewritten"; fi

# 2. Installed lint works from the installed path.
if bash "$h/.config/meridian/scripts/mdn-lint.sh" "$root/tests/fixtures/valid.md" >/dev/null 2>&1; then
  pass "installed mdn-lint.sh validates valid.md"
else bad "installed mdn-lint.sh failed on valid.md"; fi

# 3. Idempotent second run.
before="$(sum "$h")"; run_install "$h"; after="$(sum "$h")"
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; then pass "second run is idempotent"
else bad "second run changed the tree or failed (rc=$rc)"; fi

# 4. Retired skills moved, differing skill backed up.
h="$(newhome)"
for r in mdn-plan mdn-approve mdn-reviewer mdn-checkpoint mdn-generator mdn-loop mdn-load mdn-sync; do
  mkdir -p "$h/.claude/skills/$r"; echo "old $r" > "$h/.claude/skills/$r/SKILL.md"
done
mkdir -p "$h/.claude/skills/other-skill"; echo keep > "$h/.claude/skills/other-skill/SKILL.md"
mkdir -p "$h/.claude/skills/mdn-add"; echo "custom edit" > "$h/.claude/skills/mdn-add/SKILL.md"
run_install "$h"
ok=1; for r in mdn-plan mdn-approve mdn-reviewer mdn-checkpoint mdn-generator mdn-loop mdn-load mdn-sync; do
  [ ! -e "$h/.claude/skills/$r" ] || ok=0
done
[ "$ok" -eq 1 ] && pass "retired skills absent from skills dir" || bad "retired skills still installed"
retired="$(ls -d "$h"/.config/meridian/retired-skills-* 2>/dev/null | head -1)"
if [ -n "$retired" ] && [ -f "$retired/mdn-plan/SKILL.md" ] && [ -f "$retired/mdn-sync/SKILL.md" ]; then
  pass "retired skills moved to retired dir"
else bad "retired dir missing moved skills"; fi
[ -n "$retired" ] && grep -q "custom edit" "$retired/mdn-add-backup-claude/SKILL.md" 2>/dev/null \
  && pass "differing existing skill backed up" || bad "differing skill not backed up"
grep -q keep "$h/.claude/skills/other-skill/SKILL.md" && pass "unrelated skill untouched" || bad "unrelated skill touched"
printf '%s' "$out" | grep -q "mdn-plan" && pass "output lists moved skills" || bad "output does not list moved skills"
grep -q "^name: mdn-add" "$h/.claude/skills/mdn-add/SKILL.md" && pass "differing skill overwritten with new" || bad "skill not overwritten"

# 5. Dry run changes nothing.
h="$(newhome)"; mkdir -p "$h/.claude/skills/mdn-plan"; echo old > "$h/.claude/skills/mdn-plan/SKILL.md"
before="$(sum "$h")"; run_install "$h" --dry-run; after="$(sum "$h")"
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; then pass "--dry-run changes nothing"
else bad "--dry-run modified HOME or failed (rc=$rc)"; fi
printf '%s' "$out" | grep -qi "dry" && pass "--dry-run says so" || bad "--dry-run output unclear"

# 6. codex and all.
h="$(newhome)"; run_install "$h" --tool codex
ok=1; for s in "${skills[@]}"; do [ -s "$h/.codex/skills/$s/SKILL.md" ] || ok=0; done
[ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && [ ! -e "$h/.claude" ] && pass "--tool codex writes only ~/.codex/skills" || bad "--tool codex wrong (rc=$rc)"
h="$(newhome)"; run_install "$h" --tool all
[ "$rc" -eq 0 ] && [ -s "$h/.claude/skills/mdn-run/SKILL.md" ] && [ -s "$h/.codex/skills/mdn-run/SKILL.md" ] \
  && pass "--tool all installs both" || bad "--tool all wrong (rc=$rc)"

# 7. Errors.
h="$(newhome)"; run_install "$h" --bogus
[ "$rc" -ne 0 ] && pass "unknown option fails" || bad "unknown option accepted"
run_install "$h" --tool nope
[ "$rc" -ne 0 ] && pass "unknown tool fails" || bad "unknown tool accepted"
run_install "$h" --source "$work/does-not-exist"
[ "$rc" -ne 0 ] && pass "missing source fails" || bad "missing source accepted"

if [ "$fail" -eq 0 ]; then echo "all install tests passed"; else echo "$fail install test(s) failed"; exit 1; fi

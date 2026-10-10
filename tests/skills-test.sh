#!/usr/bin/env bash
# Structural checks on skills/*/SKILL.md (pure bash/grep).
# NOTE: skills are markdown instructions for a model. This test checks that the
# required sections and phrases are present and consistent; it does NOT check
# how a model behaves when it follows them.
# Usage: bash tests/skills-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sk="$root/skills"
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
has()  { grep -qF -- "$2" "$1"; }

skills=()
for d in "$sk"/*/; do skills+=("$(basename "$d")"); done
[ "${#skills[@]}" -gt 0 ] || { echo "no skills found in $sk"; exit 1; }

# Every skill has name/description frontmatter, and name matches the folder.
for s in "${skills[@]}"; do
  f="$sk/$s/SKILL.md"
  if [ -f "$f" ] && [ "$(sed -n 1p "$f")" = "---" ] \
     && awk 'NR>1 && /^---$/ {exit} NR>1' "$f" | grep -q "^name: $s\$" \
     && awk 'NR>1 && /^---$/ {exit} NR>1' "$f" | grep -q '^description:'; then
    pass "$s: frontmatter has name and description"
  else
    bad "$s: frontmatter must have name: $s and description:"
  fi
done

# Every skill except mdn-init carries the identical init guard.
guard_ref=""
for s in "${skills[@]}"; do
  [ "$s" = "mdn-init" ] && continue
  f="$sk/$s/SKILL.md"
  if has "$f" '## Init guard' && has "$f" 'running /mdn-init first'; then
    pass "$s: has Init guard"
  else
    bad "$s: missing '## Init guard' section or 'running /mdn-init first'"
    continue
  fi
  # The block (heading to next heading) must be identical across skills.
  block="$(awk '/^## Init guard$/ {p=1; print; next} p && /^## / {exit} p' "$f")"
  if [ -z "$guard_ref" ]; then guard_ref="$block"
  elif [ "$block" = "$guard_ref" ]; then pass "$s: Init guard text identical to the others"
  else bad "$s: Init guard text differs from the other skills"; fi
done

# mdn-init: description derivation, 140 limit, auto mode, never invent.
f="$sk/mdn-init/SKILL.md"
has "$f" '## Description derivation' && pass "mdn-init: description derivation section" || bad "mdn-init: missing '## Description derivation'"
has "$f" '140' && pass "mdn-init: 140 character limit" || bad "mdn-init: missing 140 limit"
has "$f" '## Auto mode' && pass "mdn-init: auto mode section" || bad "mdn-init: missing '## Auto mode'"
has "$f" 'never invent' && pass "mdn-init: never invent rule" || bad "mdn-init: missing 'never invent'"
has "$f" 'already initialized' && pass "mdn-init: idempotent re-run message" || bad "mdn-init: missing 'already initialized'"

# No skill references retired terms.
for s in "${skills[@]}"; do
  if grep -nEi 'planning|approved|mdn-plan|mdn-approve|mdn-reviewer|mdn-checkpoint|mdn-generator|mdn-loop|mdn-load|mdn-sync' "$sk/$s/SKILL.md" >/dev/null; then
    bad "$s: references a retired term: $(grep -noEi 'planning|approved|mdn-plan|mdn-approve|mdn-reviewer|mdn-checkpoint|mdn-generator|mdn-loop|mdn-load|mdn-sync' "$sk/$s/SKILL.md" | head -3 | tr '\n' ' ')"
  else
    pass "$s: no retired terms"
  fi
done

# Logs and digest wiring (structure only: checks phrases, not model behavior).
has "$sk/mdn-archive/SKILL.md" 'mdn-log.sh archive' && pass "mdn-archive: uses mdn-log.sh archive" || bad "mdn-archive: missing 'mdn-log.sh archive'"
for s in mdn-add mdn-run mdn-done mdn-init; do
  has "$sk/$s/SKILL.md" 'mdn-log.sh event' && pass "$s: logs with mdn-log.sh event" || bad "$s: missing 'mdn-log.sh event'"
  has "$sk/$s/SKILL.md" 'never fail or block' && pass "$s: logging never blocks" || bad "$s: missing 'never fail or block' logging rule"
done
for ev in 'created' ; do has "$sk/mdn-add/SKILL.md" "$ev <slug>" && pass "mdn-add: logs created" || bad "mdn-add: missing created event"; done
for ev in run-started run-finished blocked; do
  has "$sk/mdn-run/SKILL.md" "$ev" && pass "mdn-run: logs $ev" || bad "mdn-run: missing $ev event"
done
has "$sk/mdn-done/SKILL.md" 'reopened' && has "$sk/mdn-done/SKILL.md" 'done <slug>' && pass "mdn-done: logs done and reopened" || bad "mdn-done: missing done/reopened events"
has "$sk/mdn-init/SKILL.md" 'init - ' && pass "mdn-init: logs init" || bad "mdn-init: missing init event"
has "$sk/mdn-init/SKILL.md" 'dashboard.md' && pass "mdn-init: mentions dashboard.md" || bad "mdn-init: missing dashboard.md"
has "$sk/mdn-init/SKILL.md" 'never overwrite' && pass "mdn-init: never overwrite dashboard" || bad "mdn-init: missing 'never overwrite'"
for s in mdn-daily mdn-status; do
  has "$sk/$s/SKILL.md" 'mdn-index.sh' && pass "$s: uses mdn-index.sh" || bad "$s: missing mdn-index.sh"
  has "$sk/$s/SKILL.md" 'Never read `logs/`' && pass "$s: never reads logs" || bad "$s: missing 'Never read logs/' rule"
done
has "$sk/mdn-status/SKILL.md" '/mdn-archive' && has "$sk/mdn-status/SKILL.md" 'archive_hint' && pass "mdn-status: archive hint" || bad "mdn-status: missing archive_hint"
[ -f "$root/templates/Dashboard.md" ] && [ "$(grep -c '^```dataview' "$root/templates/Dashboard.md")" -eq 4 ] \
  && pass "Dashboard template has 4 dataview blocks" || bad "templates/Dashboard.md missing or not 4 dataview blocks"

# TASK_HISTORY is gone from skills, README and docs (protocol.md may keep a labeled historical row).
if grep -rl 'TASK_HISTORY' "$sk" "$root/README.md" "$root/docs" --exclude=protocol.md 2>/dev/null | grep -q .; then
  bad "TASK_HISTORY still referenced: $(grep -rl 'TASK_HISTORY' "$sk" "$root/README.md" "$root/docs" --exclude=protocol.md | tr '\n' ' ')"
else pass "no TASK_HISTORY outside protocol.md"; fi

if [ "$fail" -eq 0 ]; then echo "all skills tests passed"; else echo "$fail skills test(s) failed"; exit 1; fi

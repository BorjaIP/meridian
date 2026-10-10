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

if [ "$fail" -eq 0 ]; then echo "all skills tests passed"; else echo "$fail skills test(s) failed"; exit 1; fi

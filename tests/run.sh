#!/usr/bin/env bash
# Runs mdn-lint.sh against the fixtures and asserts the expected outcome.
# Usage: bash tests/run.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lint="$root/scripts/mdn-lint.sh"
fx="$root/tests/fixtures"
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

# The valid fixture must exit 0 with no output.
if out="$(bash "$lint" "$fx/valid.md" 2>&1)" && [ -z "$out" ]; then
  pass "valid.md passes"
else
  bad "valid.md should pass; got: $out"
fi

# Each invalid fixture must exit non-zero and print its expected message,
# prefixed with a file:line: location.
# Format: fixture|expected message fragment
cases=(
  'invalid-no-frontmatter.md|missing frontmatter'
  'invalid-old-state.md|retired state "planning"'
  'invalid-missing-field.md|missing field "slug"'
  'invalid-bad-slug.md|not kebab-case'
  'invalid-duplicate-slug.md|duplicate slug "same-slug"'
  'invalid-checkbox.md|checkbox must be [x]'
  'invalid-no-run.md|requires **Run:**'
  'invalid-no-trace.md|requires **Trace:**'
  'invalid-bad-value.md|invalid owner "robot"'
  'invalid-bad-value.md|invalid priority "urgent"'
)
for c in "${cases[@]}"; do
  file="${c%%|*}"; msg="${c#*|}"
  if out="$(bash "$lint" "$fx/$file" 2>&1)"; then
    bad "$file should fail but exited 0"
  elif printf '%s\n' "$out" | grep -qE "^[^:]+:[0-9]+: .*$(printf '%s' "$msg" | sed 's/[][\*.^$]/\\&/g')"; then
    pass "$file -> $msg"
  else
    bad "$file: expected '$msg' with file:line prefix; got: $out"
  fi
done

# The skill-style run fixture must also pass.
if out="$(bash "$lint" "$fx/valid-run.md" 2>&1)" && [ -z "$out" ]; then
  pass "valid-run.md passes"
else
  bad "valid-run.md should pass; got: $out"
fi

# Trace collector tests.
if bash "$root/tests/trace-test.sh" >/dev/null 2>&1; then
  pass "trace-test.sh passes"
else
  bad "trace-test.sh failed (run it directly for details)"
fi

# Migration converter tests.
if bash "$root/tests/migrate-test.sh" >/dev/null 2>&1; then
  pass "migrate-test.sh passes"
else
  bad "migrate-test.sh failed (run it directly for details)"
fi

# Skill structure tests (structure only, not model behavior).
if bash "$root/tests/skills-test.sh" >/dev/null 2>&1; then
  pass "skills-test.sh passes"
else
  bad "skills-test.sh failed (run it directly for details)"
fi

# Installer tests (temp HOME, local source).
if bash "$root/tests/install-test.sh" >/dev/null 2>&1; then
  pass "install-test.sh passes"
else
  bad "install-test.sh failed (run it directly for details)"
fi

if [ "$fail" -eq 0 ]; then echo "all tests passed"; else echo "$fail test(s) failed"; exit 1; fi

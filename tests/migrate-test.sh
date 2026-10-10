#!/usr/bin/env bash
# Tests scripts/mdn-migrate.sh against the synthetic old-format fixture.
# Usage: bash tests/migrate-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mig="$root/scripts/mdn-migrate.sh"
fx="$root/tests/fixtures/old-project"
golden="$root/tests/fixtures/old-project.expected.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$2" = 0 ]; then pass "$1"; else bad "$1"; fi; }
# sum <dir>: checksum of every file's path and content.
sum() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs -d '\n' sha256sum | sha256sum); }

before="$(sum "$fx")"

# 1. Dry run: exit 0, expected project.md, report, lint.
dest="$tmp/dry/proj"
out="$(bash "$mig" "$fx" --dest "$dest" --repo /home/user/sample 2>&1)"; rc=$?
check "dry-run exits 0" "$rc"
diff -u "$golden" "$dest/project.md" >"$tmp/diff.txt" 2>&1
check "dry-run project.md matches golden" "$?"
[ "$(sum "$fx")" = "$before" ]; check "dry-run leaves source untouched (checksum)" "$?"
bash "$root/scripts/mdn-lint.sh" "$dest/project.md" >/dev/null 2>&1
check "migrated project.md passes lint" "$?"
printf '%s\n' "$out" | grep -q 'Tasks converted: 6'; check "report counts tasks" "$?"
printf '%s\n' "$out" | grep -q 'fix-login-redirect-2'; check "report lists collision slug" "$?"
printf '%s\n' "$out" | grep -q 'planning -> backlog'; check "report lists status change" "$?"
grep -q 'slug::fix-login-redirect-2$' "$dest/project.md"; check "collision slug gets -2 suffix" "$?"
! grep -q 'status::planning' "$dest/project.md"; check "planning mapped to backlog" "$?"
grep -q 'was in planning before migration' "$dest/project.md"; check "planning task noted" "$?"
! grep -qE 'Artifact:|Task note:|## Plans|## Sources' "$dest/project.md"; check "legacy fields and sections dropped" "$?"
! grep -q '^created:' "$dest/project.md"; check "created dropped" "$?"
al="$dest/archive-legacy"
[ -f "$al/plans/old-plan.md" ] && [ -f "$al/tasks/integrate-memory.md" ] \
  && [ -f "$al/tasks-history.md" ] && [ -f "$al/project.legacy.md" ]
check "legacy files archived" "$?"
[ -z "$(ls -A "$dest/plans")$(ls -A "$dest/tasks")" ]; check "old plans/ and tasks/ emptied" "$?"
grep -q 'Sources' "$al/project.legacy.md"; check "project.legacy.md is the old project.md" "$?"

# 2. Dry run refuses a non-empty destination.
mkdir -p "$tmp/full"; echo keep > "$tmp/full/x"
bash "$mig" "$fx" --dest "$tmp/full" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ "$(ls -A "$tmp/full")" = "x" ]; check "non-empty --dest refused" "$?"

# 3. Dry run on an already migrated project is a no-op.
out="$(bash "$mig" "$dest" --dest "$tmp/dry2/proj" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'nothing to migrate' && [ ! -e "$tmp/dry2" ]
check "already migrated: nothing to migrate" "$?"

# 4. Placeholder description keeps a TODO and warns.
mkdir -p "$tmp/ph"; cp -a "$fx/." "$tmp/ph/"
sed -i 's/^> Sample project used.*/> TODO: add a one-line description of this project./' "$tmp/ph/project.md"
out="$(bash "$mig" "$tmp/ph" --dest "$tmp/ph-out/proj" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^> TODO:' "$tmp/ph-out/proj/project.md" && printf '%s\n' "$out" | grep -qi 'warning.*description'
check "placeholder description warns" "$?"

# 5. --apply in a temp git repo.
repo="$tmp/repo"; mkdir -p "$repo/vault"
git -C "$repo" init -q; git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
cp -a "$fx" "$repo/vault/proj"
git -C "$repo" add -A; git -C "$repo" commit -qm init
bash "$mig" "$repo/vault/proj" --apply --repo /home/user/sample >"$tmp/apply.out" 2>&1; rc=$?
check "--apply exits 0" "$rc"
diff -q "$golden" "$repo/vault/proj/project.md" >/dev/null; check "--apply writes expected project.md" "$?"
[ -f "$repo/vault/proj/archive-legacy/project.legacy.md" ] && [ ! -e "$repo/vault/proj/plans/old-plan.md" ]
check "--apply archives legacy files" "$?"
out="$(bash "$mig" "$repo/vault/proj" --apply 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'nothing to migrate'; check "second --apply is idempotent" "$?"

# 6. --apply refuses a dirty tree and changes nothing.
rm -rf "$repo"; mkdir -p "$repo/vault"
git -C "$repo" init -q; git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
cp -a "$fx" "$repo/vault/proj"
git -C "$repo" add -A; git -C "$repo" commit -qm init
echo dirty >> "$repo/vault/proj/project.md"
b2="$(sum "$repo/vault/proj")"
bash "$mig" "$repo/vault/proj" --apply >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ "$(sum "$repo/vault/proj")" = "$b2" ]; check "--apply refuses a dirty tree" "$?"

# 7. Usage errors.
bash "$mig" "$fx" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ]; check "no mode given is an error" "$?"
[ "$(sum "$fx")" = "$before" ]; check "fixture unchanged at the end" "$?"

if [ "$fail" -eq 0 ]; then echo "all migrate tests passed"; else echo "$fail migrate test(s) failed"; exit 1; fi

#!/usr/bin/env bash
# Tests scripts/mdn-trace.sh against throwaway git repositories.
# Usage: bash tests/trace-test.sh
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace="$root/scripts/mdn-trace.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

pass() { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

# val <output> <key>: first value of key (key=value lines).
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1; }
# has <output> <line>: exact line present.
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
# check <name> <condition result>
check() { if [ "$2" = 0 ]; then pass "$1"; else bad "$1"; fi; }

mkrepo() { # mkrepo <dir>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
}
commit() { # commit <dir> <file> <content>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -q -m "c $2"
}

# 1. Repo without commits: start has empty base, finish works.
r="$tmp/nocommit"; mkrepo "$r"
out="$("$trace" start "$r" 2>&1)"; rc=$?
check "no commits: start succeeds" "$rc"
[ -z "$(val "$out" base)" ] && [ "$(val "$out" repo)" = "$r" ]; check "no commits: base empty, repo absolute" "$?"
printf '%s\n' "$out" | grep -q '^started=[0-9-]\{10\} [0-9:]\{5\}$'; check "no commits: started format" "$?"
printf '%s\n' "$out" > "$tmp/snap1"
commit "$r" a.txt one
fin="$("$trace" finish "$r" "" "$tmp/snap1" 2>&1)"; rc=$?
check "no commits: finish with empty base succeeds" "$rc"
[ "$(printf '%s' "$(val "$fin" commits)" | tr ',' '\n' | grep -c .)" = 1 ]; check "no commits: one commit after empty base" "$?"

# 2. Commits after base.
r="$tmp/commits"; mkrepo "$r"; commit "$r" a.txt one
out="$("$trace" start "$r")"; base="$(val "$out" base)"
printf '%s\n' "$out" > "$tmp/snap2"
[ -n "$base" ]; check "commits: base is HEAD sha" "$?"
commit "$r" b.txt two; commit "$r" c.txt three
fin="$("$trace" finish "$r" "$base" "$tmp/snap2")"
[ "$(printf '%s' "$(val "$fin" commits)" | tr ',' '\n' | grep -c .)" = 2 ]; check "commits: two commits listed" "$?"
val "$fin" diffstat_committed | grep -q '2 files changed'; check "commits: committed diffstat" "$?"
[ -z "$(val "$fin" odd_doc)" ]; check "commits: no odd docs" "$?"
[ -n "$(val "$fin" ended)" ] && [ -n "$(val "$fin" branch)" ]; check "commits: ended and branch present" "$?"
echo dirty >> "$r/a.txt"
fin="$("$trace" finish "$r" "$base" "$tmp/snap2")"
val "$fin" diffstat_uncommitted | grep -q '1 file changed'; check "commits: uncommitted diffstat" "$?"
git -C "$r" checkout -q -- a.txt

# 3. No commits since base.
fin="$("$trace" finish "$r" "$(git -C "$r" rev-parse --short HEAD)" "$tmp/snap2")"
[ -z "$(val "$fin" commits)" ]; check "no new commits: commits empty" "$?"

# 4. New odd doc and 5. changed odd doc.
r="$tmp/odd"; mkrepo "$r"; commit "$r" odd/tasks/old.md "v1"; commit "$r" odd/tasks/keep.md "k"
out="$("$trace" start "$r")"; base="$(val "$out" base)"
printf '%s\n' "$out" > "$tmp/snap3"
printf '%s\n' "$out" | grep -q '^odd_snapshot=odd/tasks/keep.md'; check "odd: snapshot lists docs" "$?"
echo "v2" > "$r/odd/tasks/old.md"            # changed, uncommitted
echo "new" > "$r/odd/tasks/fresh.md"         # new, untracked
fin="$("$trace" finish "$r" "$base" "$tmp/snap3")"
has "$fin" "odd_doc=odd/tasks/old.md" && has "$fin" "odd_doc=odd/tasks/fresh.md"; check "odd: new and changed detected" "$?"
! has "$fin" "odd_doc=odd/tasks/keep.md"; check "odd: unchanged doc ignored" "$?"

# 6. Slug match goes first.
fin="$("$trace" finish "$r" "$base" "$tmp/snap3" --slug fresh)"
[ "$(val "$fin" odd_doc)" = "odd/tasks/fresh.md" ]; check "slug: matching doc listed first" "$?"
echo "keep2" > "$r/odd/tasks/keep.md"
fin="$("$trace" finish "$r" "$base" "$tmp/snap3" --slug keep)"
[ "$(val "$fin" odd_doc)" = "odd/tasks/keep.md" ]; check "slug: unchanged slug doc still listed first" "$?"

# 7. Paths with spaces.
r="$tmp/with space/repo dir"; mkrepo "$r"; commit "$r" a.txt one
out="$("$trace" start "$r")"; base="$(val "$out" base)"
printf '%s\n' "$out" > "$tmp/snap4"
[ "$(val "$out" repo)" = "$r" ]; check "spaces: repo path preserved" "$?"
mkdir -p "$r/odd/tasks"; echo x > "$r/odd/tasks/my feat.md"
fin="$("$trace" finish "$r" "$base" "$tmp/snap4")"
has "$fin" "odd_doc=odd/tasks/my feat.md"; check "spaces: doc with space detected" "$?"
val "$fin" unc_link | grep -q 'my feat.md'; check "spaces: unc link keeps name" "$?"

# 8. UNC link: wslpath when available, plain path fallback via PATH without it.
if command -v wslpath >/dev/null 2>&1; then
  expect="$(wslpath -w "$r/odd/tasks/my feat.md")"
  [ "$(val "$fin" unc_link)" = "$expect" ]; check "unc: wslpath used when present" "$?"
fi
nowsl="$tmp/nowsl"; mkdir -p "$nowsl"
for t in bash git sed awk grep sort date mkdir dirname basename cat head tr find cksum wc ls readlink mktemp rm cut env paste timeout; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$nowsl/$t"
done
fin2="$(PATH="$nowsl" "$trace" finish "$r" "$base" "$tmp/snap4")"; rc=$?
check "unc: finish works without wslpath" "$rc"
[ "$(val "$fin2" unc_link)" = "$r/odd/tasks/my feat.md" ]; check "unc: plain path fallback" "$?"

# 9. No odd dir, detached HEAD.
r="$tmp/detached"; mkrepo "$r"; commit "$r" a.txt one; commit "$r" b.txt two
git -C "$r" checkout -q --detach HEAD~1
out="$("$trace" start "$r")"; base="$(val "$out" base)"
printf '%s\n' "$out" > "$tmp/snap5"
[ -n "$(val "$out" branch)" ]; check "detached: branch non-empty" "$?"
[ -z "$(printf '%s\n' "$out" | sed -n 's/^odd_snapshot=//p')" ]; check "no odd dir: empty snapshot" "$?"

# 10. --pr never fails without gh/network.
fin="$(PATH="$nowsl" "$trace" finish "$r" "$base" "$tmp/snap5" --pr)"; rc=$?
check "pr: finish --pr succeeds without gh" "$rc"
[ -z "$(val "$fin" pr)" ]; check "pr: empty without gh" "$?"

# 11. Errors: non-git dir, missing args.
mkdir -p "$tmp/plain"
msg="$("$trace" start "$tmp/plain" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -qi 'not a git'; check "error: non-git dir" "$?"
"$trace" start >/dev/null 2>&1; [ $? -ne 0 ]; check "error: start without args" "$?"
"$trace" finish "$r" >/dev/null 2>&1; [ $? -ne 0 ]; check "error: finish missing args" "$?"
"$trace" bogus >/dev/null 2>&1; [ $? -ne 0 ]; check "error: unknown subcommand" "$?"

if [ "$fail" -eq 0 ]; then echo "all tests passed"; else echo "$fail test(s) failed"; exit 1; fi

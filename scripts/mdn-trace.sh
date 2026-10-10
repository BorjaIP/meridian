#!/usr/bin/env bash
# mdn-trace.sh - deterministic metadata collector for /mdn-run.
#
# Usage:
#   mdn-trace.sh start  <repo>
#   mdn-trace.sh finish <repo> <base-sha> <start-output-file> [--slug <slug>] [--pr]
#
# Prints key=value lines. Repeated keys (odd_snapshot, odd_doc, unc_link)
# carry one item per line, so paths with spaces stay intact.
#
# start  prints repo, branch, base, started, odd_snapshot=<path><TAB><hash>.
#        Save its whole output to a file and pass it back to finish.
# finish prints ended, branch, commits, diffstat_committed,
#        diffstat_uncommitted, odd_doc, unc_link and (with --pr) pr.
#
# Requires bash and git. gh is used only with --pr and only when installed;
# its absence or failure never fails the command.
# Exit status: non-zero only for a missing argument or a non-git directory.

set -u

die() { echo "${0##*/}: $*" >&2; exit 2; }

usage() {
  echo "usage: ${0##*/} start <repo>" >&2
  echo "       ${0##*/} finish <repo> <base-sha> <start-output-file> [--slug <slug>] [--pr]" >&2
  exit 2
}

# Resolve the repo to an absolute top-level path or die.
resolve_repo() {
  local top
  [ -d "$1" ] || die "not a directory: $1"
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $1"
  printf '%s' "$top"
}

branch_of() {
  local b
  b="$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # Unborn branch prints an error and "HEAD"; detached HEAD prints "HEAD".
  if [ -z "$b" ] || [ "$b" = "HEAD" ]; then
    b="$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null)"
    [ -n "$b" ] || b="detached@$(git -C "$1" rev-parse --short HEAD 2>/dev/null)"
    [ "$b" != "detached@" ] || b="(no commits)"
  fi
  printf '%s' "$b"
}

# Print "<relative path><TAB><blob hash>" for every odd/tasks/*.md, sorted.
snapshot() {
  local f
  [ -d "$1/odd/tasks" ] || return 0
  find "$1/odd/tasks" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null |
    while IFS= read -r -d '' f; do
      printf '%s\t%s\n' "odd/tasks/${f##*/}" "$(git -C "$1" hash-object -- "$f")"
    done | LC_ALL=C sort
}

# "N files changed, X insertions(+), Y deletions(-)" or empty.
shortstat() { sed 's/^ *//'; }

cmd_start() {
  [ "$#" -eq 1 ] || usage
  local repo; repo="$(resolve_repo "$1")" || exit 2
  printf 'repo=%s\n' "$repo"
  printf 'branch=%s\n' "$(branch_of "$repo")"
  printf 'base=%s\n' "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)"
  printf 'started=%s\n' "$(date '+%Y-%m-%d %H:%M')"
  snapshot "$repo" | while IFS= read -r line; do printf 'odd_snapshot=%s\n' "$line"; done
  return 0
}

cmd_finish() {
  [ "$#" -ge 3 ] || usage
  local repo base snapfile slug="" want_pr=0
  repo="$(resolve_repo "$1")" || exit 2
  base="$2"; snapfile="$3"; shift 3
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --slug) [ "$#" -ge 2 ] || usage; slug="$2"; shift 2 ;;
      --pr) want_pr=1; shift ;;
      *) usage ;;
    esac
  done
  [ -r "$snapfile" ] || die "cannot read snapshot file: $snapfile"

  local branch range empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbf2158"
  branch="$(branch_of "$repo")"
  printf 'ended=%s\n' "$(date '+%Y-%m-%d %H:%M')"
  printf 'branch=%s\n' "$branch"

  # Commits and committed diffstat of base..HEAD (base may be empty: no commits at start).
  local commits="" stat_c="" stat_u=""
  if git -C "$repo" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    if [ -n "$base" ]; then range="$base..HEAD"; else range="HEAD"; fi
    commits="$(git -C "$repo" rev-list --reverse --abbrev-commit "$range" 2>/dev/null | paste -sd, -)"
    stat_c="$(git -C "$repo" diff --shortstat "${base:-$empty_tree}" HEAD 2>/dev/null | shortstat)"
    stat_u="$(git -C "$repo" diff --shortstat HEAD 2>/dev/null | shortstat)"
  fi
  printf 'commits=%s\n' "$commits"
  printf 'diffstat_committed=%s\n' "$stat_c"
  printf 'diffstat_uncommitted=%s\n' "$stat_u"

  # Odd docs that are new or changed since the start snapshot.
  local old cur docs=() line p h
  old="$(sed -n 's/^odd_snapshot=//p' "$snapfile")"
  cur="$(snapshot "$repo")"
  while IFS=$'\t' read -r p h; do
    [ -n "$p" ] || continue
    if ! printf '%s\n' "$old" | grep -qxF -- "$p"$'\t'"$h"; then docs+=("$p"); fi
  done <<< "$cur"

  # Slug match first, even when unchanged.
  local ordered=()
  if [ -n "$slug" ] && [ -f "$repo/odd/tasks/$slug.md" ]; then
    ordered+=("odd/tasks/$slug.md")
  fi
  for p in "${docs[@]+"${docs[@]}"}"; do
    [ "$p" = "odd/tasks/$slug.md" ] && continue
    ordered+=("$p")
  done
  for p in "${ordered[@]+"${ordered[@]}"}"; do
    printf 'odd_doc=%s\n' "$p"
  done
  for p in "${ordered[@]+"${ordered[@]}"}"; do
    if command -v wslpath >/dev/null 2>&1; then
      line="$(wslpath -w "$repo/$p" 2>/dev/null)" || line=""
      [ -n "$line" ] || line="$repo/$p"
    else
      line="$repo/$p"
    fi
    printf 'unc_link=%s\n' "$line"
  done

  if [ "$want_pr" -eq 1 ]; then
    local pr=""
    if command -v gh >/dev/null 2>&1 && [ "${branch#detached@}" = "$branch" ] && [ "$branch" != "(no commits)" ]; then
      pr="$(cd "$repo" && timeout 15 gh pr list --head "$branch" --json number,url \
            --jq '.[0] | select(.) | "#\(.number) \(.url)"' 2>/dev/null)" || pr=""
    fi
    printf 'pr=%s\n' "$pr"
  fi
  return 0
}

[ "$#" -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
  start)  cmd_start "$@" ;;
  finish) cmd_finish "$@" ;;
  *) usage ;;
esac

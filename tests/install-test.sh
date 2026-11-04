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

unset PI_CODING_AGENT_DIR HERMES_HOME
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
ok=1; for s in mdn-lint.sh mdn-trace.sh mdn-migrate.sh mdn-log.sh mdn-index.sh; do [ -x "$h/.config/meridian/scripts/$s" ] || ok=0; done
[ "$ok" -eq 1 ] && [ "$(ls "$h/.config/meridian/scripts" | wc -l)" -eq 5 ] && pass "5 scripts installed and executable" || bad "scripts missing or not executable"
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

# 4b. Stale templates are moved into the retired dir, never deleted.
h="$(newhome)"; mkdir -p "$h/.config/meridian/templates"
echo "old plan" > "$h/.config/meridian/templates/Plan.md"; echo "old task" > "$h/.config/meridian/templates/Task.md"
run_install "$h"
retired="$(ls -d "$h"/.config/meridian/retired-skills-* 2>/dev/null | head -1)"
if [ ! -e "$h/.config/meridian/templates/Plan.md" ] && [ ! -e "$h/.config/meridian/templates/Task.md" ] \
   && [ -n "$retired" ] && grep -q "old plan" "$retired/templates/Plan.md" && grep -q "old task" "$retired/templates/Task.md"; then
  pass "stale Plan.md and Task.md moved to retired dir"
else bad "stale templates not moved"; fi
printf '%s' "$out" | grep -q "Plan.md" && pass "output lists moved templates" || bad "output does not list moved templates"
before="$(sum "$h")"; run_install "$h"; after="$(sum "$h")"
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] && pass "second run after template retirement is idempotent" || bad "second run changed the tree"
h="$(newhome)"; mkdir -p "$h/.config/meridian/templates"; echo "old plan" > "$h/.config/meridian/templates/Plan.md"
before="$(sum "$h")"; run_install "$h" --dry-run; after="$(sum "$h")"
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] && pass "--dry-run leaves stale templates in place" || bad "--dry-run touched stale templates"

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

h="$(newhome)"; run_install "$h" --tool pi
ok=1; for s in "${skills[@]}"; do [ -s "$h/.pi/agent/skills/$s/SKILL.md" ] || ok=0; done
[ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && [ ! -e "$h/.claude" ] && [ ! -e "$h/.hermes" ] && pass "--tool pi writes only ~/.pi/agent/skills" || bad "--tool pi wrong (rc=$rc)"
! grep -q '^model:' "$h/.pi/agent/skills/mdn-run/SKILL.md" && grep -q '^name: mdn-run$' "$h/.pi/agent/skills/mdn-run/SKILL.md" \
  && pass "pi skills drop the model hint and keep the frontmatter" || bad "pi skill still has a model hint"
diff <(grep -v '^model: ' "$root/skills/mdn-run/SKILL.md") "$h/.pi/agent/skills/mdn-run/SKILL.md" >/dev/null \
  && pass "pi skill body is the source minus the model hint" || bad "pi skill body differs from the source"
h="$(newhome)"; PI_CODING_AGENT_DIR="$work/pi-custom" run_install "$h" --tool pi
[ -s "$work/pi-custom/skills/mdn-run/SKILL.md" ] && [ ! -e "$h/.pi" ] && pass "--tool pi honors PI_CODING_AGENT_DIR" || bad "PI_CODING_AGENT_DIR ignored"
h="$(newhome)"; run_install "$h" --tool hermes
ok=1; for s in "${skills[@]}"; do [ -s "$h/.hermes/skills/$s/SKILL.md" ] || ok=0; done
[ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && [ ! -e "$h/.claude" ] && [ ! -e "$h/.pi" ] && pass "--tool hermes writes only ~/.hermes/skills" || bad "--tool hermes wrong (rc=$rc)"
! grep -q '^model:' "$h/.hermes/skills/mdn-run/SKILL.md" && pass "hermes skills drop the model hint" || bad "hermes skill still has a model hint"
h="$(newhome)"; HERMES_HOME="$work/hermes-custom" run_install "$h" --tool hermes
[ -s "$work/hermes-custom/skills/mdn-run/SKILL.md" ] && [ ! -e "$h/.hermes" ] && pass "--tool hermes honors HERMES_HOME" || bad "HERMES_HOME ignored"
h="$(newhome)"; run_install "$h" --tool all
[ ! -e "$h/.pi" ] && [ ! -e "$h/.hermes" ] && pass "--tool all leaves pi and hermes alone" || bad "--tool all touched pi or hermes"

# 7. Errors.
h="$(newhome)"; run_install "$h" --bogus
[ "$rc" -ne 0 ] && pass "unknown option fails" || bad "unknown option accepted"
run_install "$h" --tool nope
[ "$rc" -ne 0 ] && pass "unknown tool fails" || bad "unknown tool accepted"
run_install "$h" --source "$work/does-not-exist"
[ "$rc" -ne 0 ] && pass "missing source fails" || bad "missing source accepted"

# 8. Obsidian plugin.
h="$(newhome)"; run_install "$h"
[ "$rc" -eq 0 ] && [ ! -e "$h/.obsidian" ] && printf '%s' "$out" | grep -q "Obsidian plugin skipped: no vault" \
  && pass "plain install without a vault skips the plugin" || bad "plain install without a vault wrong (rc=$rc): $out"
v="$work/vault"; mkdir -p "$v/.obsidian"
h="$(newhome)"; run_install "$h" --obsidian "$v"
ok=1; for f in manifest.json main.js styles.css; do [ -s "$v/.obsidian/plugins/meridian/$f" ] || ok=0; done
[ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && pass "--obsidian <vault> installs the plugin files" || bad "--obsidian <vault> wrong (rc=$rc): $out"
cmp -s "$root/plugin/main.js" "$v/.obsidian/plugins/meridian/main.js" && pass "installed main.js matches the checkout" || bad "installed main.js differs"
[ ! -e "$v/.obsidian/community-plugins.json" ] && pass "plugin is not enabled behind your back" || bad "community-plugins.json was written"
h="$(newhome)"; mkdir -p "$h/.config/meridian"
v2="$work/vault2"; mkdir -p "$v2/.obsidian"; printf -- '---\nvault: %s\n---\n' "$v2" > "$h/.config/meridian/config.md"
run_install "$h" --obsidian
[ "$rc" -eq 0 ] && [ -s "$v2/.obsidian/plugins/meridian/manifest.json" ] && pass "--obsidian without a path uses the config vault" || bad "--obsidian from config wrong (rc=$rc): $out"
h="$(newhome)"; run_install "$h" --obsidian "$work/not-a-vault"
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "not an Obsidian vault" && pass "--obsidian refuses a folder without .obsidian" || bad "--obsidian accepted a non-vault"
h="$(newhome)"; run_install "$h" --obsidian
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "needs a vault path" && pass "--obsidian without any vault fails clearly" || bad "--obsidian without vault wrong (rc=$rc)"
v3="$work/vault3"; mkdir -p "$v3/.obsidian"
h="$(newhome)"; run_install "$h" --obsidian "$v3" --dry-run
[ ! -e "$v3/.obsidian/plugins" ] && pass "--obsidian --dry-run writes nothing" || bad "--obsidian --dry-run wrote files"

v4="$work/vault4"; mkdir -p "$v4/.obsidian"
h="$(newhome)"; mkdir -p "$h/.config/meridian"
printf -- '---\nvault: "%s"\n---\n' "$v4" > "$h/.config/meridian/config.md"
run_install "$h"
ok=1; for f in manifest.json main.js styles.css; do [ -s "$v4/.obsidian/plugins/meridian/$f" ] || ok=0; done
[ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && pass "plain install uses the config vault" || bad "plain install did not use the config vault (rc=$rc): $out"
cmp -s "$root/plugin/main.js" "$v4/.obsidian/plugins/meridian/main.js" && pass "config-vault main.js matches the checkout" || bad "config-vault main.js differs"
[ ! -e "$v4/.obsidian/community-plugins.json" ] && pass "config-vault install does not enable the plugin" || bad "config-vault install wrote community-plugins.json"
printf 'keep' > "$v4/.obsidian/plugins/meridian/data.json"
before="$(sum "$v4")"; run_install "$h"; after="$(sum "$v4")"
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] && grep -q keep "$v4/.obsidian/plugins/meridian/data.json" \
  && pass "second install leaves the plugin and data.json unchanged" || bad "second install changed the plugin tree"

h="$(newhome)"; mkdir -p "$h/.config/meridian"
v5="$work/not-obsidian"; mkdir -p "$v5"
printf -- '---\nvault: %s\n---\n' "$v5" > "$h/.config/meridian/config.md"
run_install "$h"
[ "$rc" -eq 0 ] && [ ! -e "$v5/.obsidian" ] && printf '%s' "$out" | grep -q "has no .obsidian folder" \
  && pass "plain install skips a vault without .obsidian" || bad "plain install did not skip a non-vault (rc=$rc): $out"

v6="$work/vault6"; mkdir -p "$v6/.obsidian"
h="$(newhome)"; mkdir -p "$h/.config/meridian"
printf -- '---\nvault: %s\n---\n' "$v6" > "$h/.config/meridian/config.md"
run_install "$h" --dry-run
[ "$rc" -eq 0 ] && [ ! -e "$v6/.obsidian/plugins" ] && pass "plain install --dry-run writes no plugin" || bad "plain install --dry-run wrote the plugin"

v7="$work/vault7"; other="$work/vault7-other"; mkdir -p "$v7/.obsidian" "$other/.obsidian"
h="$(newhome)"; mkdir -p "$h/.config/meridian"
printf -- '---\nvault: %s\n---\n' "$other" > "$h/.config/meridian/config.md"
run_install "$h" --obsidian "$v7"
[ "$rc" -eq 0 ] && [ -s "$v7/.obsidian/plugins/meridian/manifest.json" ] && [ ! -e "$other/.obsidian/plugins" ] \
  && pass "--obsidian path wins over the config vault" || bad "--obsidian path did not win (rc=$rc): $out"

if [ "$fail" -eq 0 ]; then echo "all install tests passed"; else echo "$fail install test(s) failed"; exit 1; fi

#!/usr/bin/env bash
# Meridian installer
# Installs skills, scripts and templates from a git clone (default) or a local checkout.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/BorjaIP/meridian/main/install.sh)
#   bash install.sh [--tool claude|codex|all] [--source <dir>] [--dry-run]
#
# Options:
#   --tool <t>     claude (default), codex or all
#   --source <dir> install from a local checkout; no network is used
#   --dry-run      print what would happen, change nothing
#
# Environment (optional model names written into the `model:` frontmatter hints):
#   MERIDIAN_CLAUDE_LOW, MERIDIAN_CLAUDE_MEDIUM, MERIDIAN_CODEX_LOW, MERIDIAN_CODEX_MEDIUM

set -euo pipefail

REPO_URL="https://github.com/BorjaIP/meridian"
TOOL="claude"
SOURCE=""
DRY=0

usage() { echo "Usage: $0 [--tool claude|codex|all] [--source <dir>] [--dry-run]"; }
die()   { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)    [[ $# -ge 2 ]] || { usage >&2; exit 1; }; TOOL="$2"; shift 2 ;;
    --source)  [[ $# -ge 2 ]] || { usage >&2; exit 1; }; SOURCE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$TOOL" in
  claude|codex|all) ;;
  *) die "unknown tool: $TOOL (valid: claude, codex, all)" ;;
esac

# Model hints: skills carry `model: low|medium`; map them per tool.
claude_low="${MERIDIAN_CLAUDE_LOW:-haiku}"
claude_medium="${MERIDIAN_CLAUDE_MEDIUM:-sonnet}"
codex_low="${MERIDIAN_CODEX_LOW:-gpt-4o-mini}"
codex_medium="${MERIDIAN_CODEX_MEDIUM:-gpt-4o}"

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/meridian"
RETIRED_SKILLS=(mdn-plan mdn-approve mdn-reviewer mdn-checkpoint mdn-generator mdn-loop mdn-load mdn-sync)
STAMP="$(date +%Y%m%d-%H%M)"
RETIRED_DIR="${CONFIG_DIR}/retired-skills-${STAMP}"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

[[ $DRY -eq 1 ]] && echo "[dry-run] no files will be changed"

# Run a mutating command, or only print it in dry-run mode.
act() { if [[ $DRY -eq 1 ]]; then echo "  [dry-run] $*"; else "$@"; fi; }

# ── Source ───────────────────────────────────────────────────────────────────

if [[ -n "$SOURCE" ]]; then
  [[ -d "$SOURCE" ]] || die "source directory not found: $SOURCE"
  SRC="$(cd "$SOURCE" && pwd)"
  echo "Using local source: ${SRC}"
else
  command -v git >/dev/null || die "git is required to clone ${REPO_URL}"
  SRC="${SCRATCH}/meridian"
  echo "Cloning ${REPO_URL}..."
  git clone --depth 1 --quiet "$REPO_URL" "$SRC"
fi

for d in skills scripts templates; do
  [[ -d "${SRC}/${d}" ]] || die "not a Meridian checkout (missing ${d}/): ${SRC}"
done

# ── Retired skills cleanup ───────────────────────────────────────────────────

retired_made=0
ensure_retired_dir() {
  if [[ $retired_made -eq 0 ]]; then act mkdir -p "$RETIRED_DIR"; retired_made=1; fi
}

# Move a directory into the retired dir under the given name (no overwrite).
retire() {
  local src="$1" name="$2" dst
  ensure_retired_dir
  dst="${RETIRED_DIR}/${name}"
  [[ -e "$dst" ]] && dst="${dst}-$$"
  act mv "$src" "$dst"
}

cleanup_retired() {
  local skills_dst="$1" r
  for r in "${RETIRED_SKILLS[@]}"; do
    if [[ -d "${skills_dst}/${r}" ]]; then
      retire "${skills_dst}/${r}" "$r"
      echo "  moved retired skill ${r} -> ${RETIRED_DIR}/"
    fi
  done
}

# ── Install skills ───────────────────────────────────────────────────────────

install_for() {
  local tool="$1" model_low="$2" model_medium="$3" skills_dst skill_dir name dst tmp

  case "$tool" in
    claude) skills_dst="${HOME}/.claude/skills" ;;
    codex)  skills_dst="${HOME}/.codex/skills" ;;
  esac

  echo "Installing skills for ${tool} -> ${skills_dst}"
  act mkdir -p "$skills_dst"
  cleanup_retired "$skills_dst"

  for skill_dir in "${SRC}"/skills/*/; do
    name="$(basename "$skill_dir")"
    dst="${skills_dst}/${name}"
    tmp="${SCRATCH}/${tool}-${name}.md"
    sed \
      -e "s/^model: low$/model: ${model_low}/" \
      -e "s/^model: medium$/model: ${model_medium}/" \
      "${skill_dir}SKILL.md" > "$tmp"

    if [[ -f "${dst}/SKILL.md" ]] && cmp -s "$tmp" "${dst}/SKILL.md"; then
      echo "  = ${name} (unchanged)"
      continue
    fi
    if [[ -d "$dst" ]]; then
      ensure_retired_dir
      act cp -a "$dst" "${RETIRED_DIR}/${name}-backup-${tool}"
      echo "  backed up previous ${name} -> ${RETIRED_DIR}/${name}-backup-${tool}"
    fi
    act mkdir -p "$dst"
    act cp "$tmp" "${dst}/SKILL.md"
    echo "  + ${name}"
  done
}

case "$TOOL" in
  claude) install_for claude "$claude_low" "$claude_medium" ;;
  codex)  install_for codex  "$codex_low"  "$codex_medium" ;;
  all)
    install_for claude "$claude_low" "$claude_medium"
    install_for codex  "$codex_low"  "$codex_medium"
    ;;
esac

# ── Install scripts and templates ────────────────────────────────────────────

echo "Installing scripts -> ${CONFIG_DIR}/scripts"
act mkdir -p "${CONFIG_DIR}/scripts"
for f in "${SRC}"/scripts/*.sh; do
  act install -m 0755 "$f" "${CONFIG_DIR}/scripts/$(basename "$f")"
  echo "  + $(basename "$f")"
done

echo "Installing templates -> ${CONFIG_DIR}/templates"
act mkdir -p "${CONFIG_DIR}/templates"
for f in "${SRC}"/templates/*.md; do
  act install -m 0644 "$f" "${CONFIG_DIR}/templates/$(basename "$f")"
  echo "  + $(basename "$f")"
done

# Templates of the retired plan/task format: move aside, never delete.
for t in Plan.md Task.md; do
  if [[ -f "${CONFIG_DIR}/templates/${t}" && ! -f "${SRC}/templates/${t}" ]]; then
    ensure_retired_dir
    act mkdir -p "${RETIRED_DIR}/templates"
    act mv "${CONFIG_DIR}/templates/${t}" "${RETIRED_DIR}/templates/${t}"
    echo "  moved stale template ${t} -> ${RETIRED_DIR}/templates/"
  fi
done

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
if [[ $DRY -eq 1 ]]; then
  echo "Dry run finished. Nothing was changed."
else
  echo "Meridian installed."
  echo ""
  echo "Next step: open a Claude Code session and run:"
  echo "  /mdn-init name:<your-project-slug>"
  echo ""
  echo "On first run, mdn-init asks for your Obsidian vault path"
  echo "and writes it to ${CONFIG_DIR}/config.md."
fi

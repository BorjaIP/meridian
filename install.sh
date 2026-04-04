#!/usr/bin/env bash
# Meridian installer
# Clones the repo, installs skills and templates, then removes the clone.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/BorjaIP/meridian/main/install.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/BorjaIP/meridian/main/install.sh) --tool codex

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

REPO_URL="https://github.com/BorjaIP/meridian"
TOOL="claude"   # default

# ── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) TOOL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; echo "Usage: $0 [--tool claude|codex|all]"; exit 1 ;;
  esac
done

case "$TOOL" in
  claude|codex|all) ;;
  *) echo "Unknown tool: $TOOL. Valid options: claude, codex, all"; exit 1 ;;
esac

# ── Model maps ───────────────────────────────────────────────────────────────

claude_low="claude-haiku-4-5"
claude_medium="claude-sonnet-4-6"

codex_low="gpt-4o-mini"
codex_medium="gpt-4o"

# ── Dirs ─────────────────────────────────────────────────────────────────────

TMPDIR="/tmp/meridian-install-$$"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/meridian"

# ── Clone ────────────────────────────────────────────────────────────────────

echo "Cloning Meridian..."
git clone --depth 1 "$REPO_URL" "$TMPDIR"

SKILLS_SRC="${TMPDIR}/skills"
TEMPLATES_SRC="${TMPDIR}/templates"

# ── Install skills ───────────────────────────────────────────────────────────

install_for() {
  local tool="$1"
  local model_low="$2"
  local model_medium="$3"
  local skills_dst

  case "$tool" in
    claude) skills_dst="${HOME}/.claude/skills" ;;
    codex)  skills_dst="${HOME}/.codex/skills" ;;
  esac

  echo "Installing skills for ${tool} → ${skills_dst}..."
  mkdir -p "${skills_dst}"

  for skill_dir in "${SKILLS_SRC}"/*/; do
    skill_name="$(basename "${skill_dir}")"
    dst="${skills_dst}/${skill_name}"
    mkdir -p "${dst}"
    sed \
      -e "s/^model: low$/model: ${model_low}/" \
      -e "s/^model: medium$/model: ${model_medium}/" \
      "${skill_dir}/SKILL.md" > "${dst}/SKILL.md"
    echo "  ✓ ${skill_name}"
  done
}

case "$TOOL" in
  claude) install_for claude "$claude_low" "$claude_medium" ;;
  codex)  install_for codex  "$codex_low"  "$codex_medium"  ;;
  all)
    install_for claude "$claude_low" "$claude_medium"
    install_for codex  "$codex_low"  "$codex_medium"
    ;;
esac

# ── Install templates ────────────────────────────────────────────────────────

echo "Installing templates → ${CONFIG_DIR}/templates..."
mkdir -p "${CONFIG_DIR}/templates"
cp "${TEMPLATES_SRC}"/*.md "${CONFIG_DIR}/templates/"
echo "  ✓ templates"

# ── Config dir ───────────────────────────────────────────────────────────────

mkdir -p "${CONFIG_DIR}"
echo "  ✓ config dir: ${CONFIG_DIR}"

# ── Cleanup ──────────────────────────────────────────────────────────────────

rm -rf "$TMPDIR"
echo "  ✓ cleaned up temp files"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Meridian installed."
echo ""
echo "Next step: open a Claude Code session and run:"
echo "  /mdn-init name:<your-project-slug>"
echo ""
echo "On first run, mdn-init will ask for your Obsidian vault path"
echo "and write it to ${CONFIG_DIR}/config.md."

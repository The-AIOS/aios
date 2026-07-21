#!/bin/bash
# Skill registration — symlinks AIOS-origin skills into ~/.claude/skills so
# Claude Code auto-loads them (the "skills-dir" mechanism, same way the
# superpowers/anthropic skills load). Run once after cloning, or after
# /aios:update adds a new skill. Idempotent. Usage: bash skills/setup.sh
#
# Registers skills/<source>/<skill>/ for every source EXCEPT `anthropic/` and
# `superpowers/` — those are provided via Claude Code marketplaces
# (`claude plugin install …`), so linking the vendored mirrors would double
# them. Also skips any name already present in ~/.claude/skills (re-run safe;
# never clobbers a marketplace- or hand-installed skill).
#
# Skills register as standalone skills-dir entries — they do NOT touch the
# `aios` commands plugin. Restart Claude Code sessions to pick up new links.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"
mkdir -p "$DEST"
echo "Registering AIOS skills into $DEST ..."
echo ""

linked=0
skipped=0
for skill_md in "$SCRIPT_DIR"/*/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  skill_dir="$(dirname "$skill_md")"
  source_dir="$(basename "$(dirname "$skill_dir")")"
  name="$(basename "$skill_dir")"

  # Marketplace-provided sources — skip (avoid duplicating installed skills).
  case "$source_dir" in
    anthropic | superpowers) continue ;;
  esac

  target="$DEST/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "  • skip (already registered): $name"
    skipped=$((skipped + 1))
    continue
  fi

  if ln -s "$skill_dir" "$target"; then
    echo "  ✓ linked: $name  ($source_dir)"
    linked=$((linked + 1))
  else
    echo "  ✗ failed: $name"
  fi
done

echo ""
echo "Done — linked $linked, skipped $skipped."
echo "Restart Claude Code sessions to load newly-registered skills."

# ─────────────────────────────────────────────────────────────────────────────
# Wiring convention (for skill authors) — a bundled skill earns its keep by being
# NAMED at the judgment moment it serves: inline in a command step, or in an
# agent's `## Skills` section, in the greppable backtick form (e.g. "consult the
# `team-archetypes` skill"). Name it where the call is made — never as a generic
# "skills available" preamble (that's noise; named-where-needed, it's a checklist).
# The CI skill-resolution job (.github/workflows/validate.yml) verifies every
# agent `## Skills` reference resolves to a shipped SKILL.md; an orphan skill
# (shipped but named by nobody) is a candidate for skills/custom/.
# ─────────────────────────────────────────────────────────────────────────────

#!/bin/bash
# Skill registration — symlinks AIOS-origin skills into ~/.claude/skills so
# Claude Code auto-loads them (the "skills-dir" mechanism, same way the
# superpowers/anthropic skills load). Run once after cloning, or after
# /aios:update adds a new skill. Idempotent. Usage: bash skills/setup.sh
#
# Registers skills/<source>/<skill>/ for every source EXCEPT `superpowers/`,
# which IS reliably provided via a Claude Code marketplace, so linking the
# vendored mirror would double it. Skips any name already present in
# ~/.claude/skills (re-run safe; never clobbers a marketplace- or hand-installed
# skill).
#
# `anthropic/` USED TO BE EXCLUDED HERE ON THE SAME PREMISE, AND THE PREMISE WAS
# FALSE. One sentence — "those are provided via Claude Code marketplaces" —
# covered two sources, and it happened to be true of only one. Measured on two
# independent vaults: superpowers 14 sources, 0 missing; anthropic 11 sources,
# 10 and 11 missing respectively. Excluding them together is exactly what hid it,
# because superpowers kept proving the rule while anthropic quietly broke it.
#
# The consequence was not an error. It was silence: eight bundled agents declare
# one of those skills in their `## Skills` block and received nothing —
# content-writer, sales-proposal-writer, protocol-steward (doc-coauthoring),
# email-drafter, report-drafter (internal-comms), deck-builder (theme-factory),
# aios-builder (mcp-builder, skill-creator). An agent that silently lacks the
# skill it declares still answers; it just answers worse, and nothing anywhere
# says why. That is a defect for every operator who installs this framework, on
# any day — the kind of thing you only find by measuring rather than by hitting
# an error.
#
# The presence check below is what would have caught it without anyone noticing an
# agent underperform, and it stays regardless of which sources are excluded: it
# asserts the assumption instead of trusting it, so if superpowers' premise ever
# stops holding, this script says so on the next run.
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
skipped_sources=""
for skill_md in "$SCRIPT_DIR"/*/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  skill_dir="$(dirname "$skill_md")"
  source_dir="$(basename "$(dirname "$skill_dir")")"
  name="$(basename "$skill_dir")"

  # Marketplace-provided sources — skip (avoid duplicating installed skills).
  # ONLY superpowers: its premise is measured true. See the header for why
  # anthropic was removed from this list.
  case "$source_dir" in
    superpowers) skipped_sources="$skipped_sources $name"; continue ;;
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

# ─────────────────────────────────────────────────────────────────────────────
# Presence check — assert the exclusion premise instead of trusting it.
#
# Every source skipped above is skipped because it is *believed* to arrive from a
# marketplace. That belief is a claim about the operator's machine, and it was
# wrong once, silently, for months. So verify it: for each skipped skill, is the
# name actually in ~/.claude/skills? If not, the skill this script declined to
# register is not there by any other route either, and anything declaring it gets
# nothing.
#
# This check is deliberately independent of WHICH sources are excluded. It costs
# one stat per skipped name and it is the only thing standing between a false
# premise and an agent that quietly underperforms.
# ─────────────────────────────────────────────────────────────────────────────
absent=""
for name in $skipped_sources; do
  [ -e "$DEST/$name" ] || absent="$absent $name"
done

if [ -n "$absent" ]; then
  n_absent=$(echo $absent | wc -w | tr -d ' ')
  # Is the marketplace that provides them installed YET? This script runs early in
  # setup — before the interview's plugins step installs the superpowers
  # marketplace — so on a fresh machine these skills are legitimately "not here
  # yet" rather than missing. Distinguishing the two is the whole difference
  # between a check worth reading and a wall of text a first-timer learns to skip.
  mkt_installed=0
  for m in "$HOME"/.claude/plugins/marketplaces/*superpowers*/ \
           "$HOME"/.claude/plugins/cache/*superpowers*/; do
    [ -d "$m" ] && { mkt_installed=1; break; }
  done

  echo ""
  if [ "$mkt_installed" -eq 1 ]; then
    # The marketplace IS installed and the skills still are not there. That is the
    # real defect: the premise is false on this machine, right now.
    echo "⚠️  $n_absent skill(s) skipped on the assumption a marketplace provides them, but"
    echo "    they are NOT in $DEST — and the marketplace IS installed:"
    for n in $absent; do echo "     · $n"; done
    echo ""
    echo "   Anything declaring one of these receives nothing — no error, just silence."
    echo "   Drop that source from the exclusion list in this script so it registers"
    echo "   like any other. (This is exactly how anthropic/ was found.)"
  else
    # Expected on a fresh install. State it once, quietly, and do not enumerate.
    echo "ℹ️  $n_absent skill(s) come from a marketplace that is not installed yet —"
    echo "    the cold-start interview installs it at its plugins step. Nothing to do."
    echo "    If they are still absent after that, re-run this script: it will say so"
    echo "    loudly, because at that point the assumption really is broken."
  fi
fi

#!/bin/bash
# Skill registration — symlinks AIOS-origin skills into ~/.claude/skills so
# Claude Code auto-loads them (the "skills-dir" mechanism, same way the
# superpowers/anthropic skills load). Run once after cloning, or after
# /aios:update adds a new skill. Idempotent. Usage: bash skills/setup.sh
#
# Registers skills/<source>/<skill>/ for every source. `superpowers/` is the one
# conditional source (#313): when a Superpowers plugin is installed it provides those
# skills (namespaced, outside ~/.claude/skills), so the bundled copy is skipped to avoid
# doubling them; when none is installed, the bundled, pinned copy is registered like any
# other source. That used to be an unconditional skip on the premise that a marketplace
# always provides Superpowers, and on a machine without the plugin it left sessions on
# whatever old copies sat in ~/.claude/skills. Skips any name already present in
# ~/.claude/skills (re-run safe; never clobbers a marketplace- or hand-installed skill),
# and names a plain-folder Superpowers copy as stale rather than touching it.
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
# content-writer, proposal-writer, protocol-steward (doc-coauthoring),
# email-drafter, report-drafter (internal-comms), deck-builder (theme-factory),
# aios-builder (mcp-builder, skill-creator). An agent that silently lacks the
# skill it declares still answers; it just answers worse, and nothing anywhere
# says why. That is a defect for every operator who installs this framework, on
# any day — the kind of thing you only find by measuring rather than by hitting
# an error.
#
# The lesson stands for superpowers too: an exclusion must rest on a premise the script
# CHECKS at runtime. So the bundled Superpowers is skipped only when a Superpowers
# plugin is actually installed (checked below), and a plain-folder copy shadowing a
# bundled name is reported instead of passing for "registered".
#
# Skills register as standalone skills-dir entries — they do NOT touch the
# `aios` commands plugin. Restart Claude Code sessions to pick up new links.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"
mkdir -p "$DEST"
echo "Registering AIOS skills into $DEST ..."
echo ""

# Is a Superpowers plugin INSTALLED? Then it provides those skills, and linking the
# bundled copy would double them. Read from Claude Code's own record of installed plugins
# (any "superpowers@<marketplace>" entry), never from which marketplaces exist: a
# marketplace can be added with the plugin never installed, and the plugin can come from
# a marketplace with any name. Checked here, at runtime, never assumed.
# Parsed, not grepped: a user-wide install ("scope": "user") that settings.json has not
# disabled. A disabled plugin, or one installed for another project only, provides nothing
# here, and counting it would leave this vault with no Superpowers at all.
sp_plugin=$(python3 - "$HOME" <<'PY' 2>/dev/null || echo 0
import json, os, sys
home = sys.argv[1]
def load(*p):
    try:
        with open(os.path.join(home, ".claude", *p), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
enabled = (load("settings.json").get("enabledPlugins") or {})
plugins = (load("plugins", "installed_plugins.json").get("plugins") or {})
active = any(k.startswith("superpowers@") and enabled.get(k) is not False
             and any(isinstance(e, dict) and e.get("scope", "user") == "user"
                     for e in (v if isinstance(v, list) else [v]))
             for k, v in plugins.items())
print(1 if active else 0)
PY
)
[ "$sp_plugin" = 1 ] || sp_plugin=0
sp_linked=0
unlinked=0

linked=0
skipped=0
skipped_sources=""
stale=""
for skill_md in "$SCRIPT_DIR"/*/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  skill_dir="$(dirname "$skill_md")"
  source_dir="$(basename "$(dirname "$skill_dir")")"
  name="$(basename "$skill_dir")"

  # A Superpowers plugin provides these skills when installed (see the header). A link
  # this script made earlier, before the plugin arrived, would now double it: remove
  # exactly that link (it points at the bundled copy). Never a plain folder, never data.
  if [ "$source_dir" = superpowers ] && [ "$sp_plugin" -eq 1 ]; then
    # Compared as resolved paths, so a link made before the vault moved is still recognised.
    if [ -L "$DEST/$name" ] && [ "$(cd "$DEST/$name" 2>/dev/null && pwd -P)" = "$(cd "$skill_dir" && pwd -P)" ]; then
      rm "$DEST/$name" && { echo "  - unlinked (its plugin provides it): $name"; unlinked=$((unlinked + 1)); }
    elif [ -d "$DEST/$name" ] && [ ! -L "$DEST/$name" ]; then
      stale="$stale $name"; echo "  ! old copy, left as it is: $name"
    fi
    skipped_sources="$skipped_sources $name"; continue
  fi

  target="$DEST/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    # A plain folder under a bundled Superpowers name is an old copy that never updates.
    if [ "$source_dir" = superpowers ] && [ -d "$target" ] && [ ! -L "$target" ]; then
      stale="$stale $name"
      echo "  ! old copy, left as it is: $name"
    else
      echo "  • skip (already registered): $name"
    fi
    skipped=$((skipped + 1))
    continue
  fi

  if ln -s "$skill_dir" "$target"; then
    echo "  ✓ linked: $name  ($source_dir)"
    linked=$((linked + 1))
    [ "$source_dir" = superpowers ] && sp_linked=$((sp_linked + 1))
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
# Superpowers report (#313). The source is skipped only when a plugin provides it, a
# premise checked above rather than assumed, so the only thing left to report is the
# case nothing else catches: plain-folder copies under the bundled names, which shadow
# the bundled version and never update.
# ─────────────────────────────────────────────────────────────────────────────
if [ "$sp_plugin" -eq 1 ]; then
  echo ""
  extra=""; [ "$unlinked" -gt 0 ] && extra=" (removed $unlinked earlier link(s))"
  echo "ℹ️  Superpowers comes from its installed plugin, so the bundled copy is not linked$extra."
fi
if [ "$sp_linked" -gt 0 ]; then
  echo ""
  echo "ℹ️  Linked the bundled Superpowers ($sp_linked skills). If you later install the Superpowers plugin,"
  echo "    run this script again: it removes these links so the skills are not doubled."
fi
if [ -n "$stale" ]; then
  n_stale=$(echo $stale | wc -w | tr -d ' ')
  echo ""
  echo "⚠️  $n_stale Superpowers skill(s) in $DEST are plain folders: old copies that never update."
  echo "    /aios:update offers to archive them. By hand: move them out of $DEST, then run this again."
fi

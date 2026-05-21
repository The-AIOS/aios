#!/bin/bash
#
# extract-to-the-aios.sh — Phase 1 migration script (sarah-drafted, 2026-05-20 → 21)
#
# Extracts AIOS product infrastructure from ~/obsidian into The-AIOS/aios for
# the public distribution. Run AFTER Phase 0 cleanup commits land in
# ~/obsidian (path-config + sovra-strip + plist-rename + auth-gitignore).
#
# Strategy: squash-extract with history preserved by reference.
# - Build a clean snapshot of just the product-infra subset
# - Initial commit with HISTORY-PRE-2026-05-21.md linking back to chuy/obsidian
# - Push to The-AIOS/aios as the canonical first product commit
#
# This is sarah's first pass. Chuy refines tomorrow morning before execution.
# Key deferred decisions baked as FLAGS at top — change before running.
#
# Usage:
#   ./extract-to-the-aios.sh --dry-run     # preview without touching anything
#   ./extract-to-the-aios.sh --execute     # actually do the migration

set -e

# ──────────────────────────────────────────────────────────────────────────
# DEFERRED DECISIONS — set before --execute (see migration-map for context)
# ──────────────────────────────────────────────────────────────────────────

# (1) Promote templates/agents to top-level OR keep nested under vault/?
#     true = top-level (cleaner, Obsidian-agnostic)
#     false = nested (preserves source paths, easier 1:1 diff)
PROMOTE_TOP_LEVEL=true

# (2) History preservation strategy
#     squash = single initial commit with HISTORY reference (fast, ~1min)
#     filter-repo = preserve every commit touching migrated files (slow, ~1hr)
HISTORY_STRATEGY="squash"

# (3) LICENSE confirmation — sarah scaffolded MIT; uncomment to change
# LICENSE_TYPE="MIT"   # other options: Apache-2.0, BSD-3-Clause, proprietary

# (4) Source vault path (only change if running from a non-default location)
SOURCE_VAULT="${SOURCE_VAULT:-$HOME/obsidian}"

# (5) Destination repo path (where to assemble the migration)
DEST_REPO="${DEST_REPO:-/tmp/the-aios-aios-migration}"

# (6) The-AIOS/aios remote URL
REMOTE_URL="git@github.com:The-AIOS/aios.git"

# ──────────────────────────────────────────────────────────────────────────
# MODE PARSING
# ──────────────────────────────────────────────────────────────────────────

MODE="${1:-}"
if [ "$MODE" != "--dry-run" ] && [ "$MODE" != "--execute" ]; then
  echo "Usage: $0 --dry-run | --execute"
  exit 1
fi

DRY=""
[ "$MODE" = "--dry-run" ] && DRY="echo [DRY] "

echo "═══════════════════════════════════════════════════════════"
echo "AIOS extract → The-AIOS/aios   (mode: $MODE)"
echo "═══════════════════════════════════════════════════════════"
echo "Source: $SOURCE_VAULT"
echo "Dest:   $DEST_REPO"
echo "Remote: $REMOTE_URL"
echo "Promote top-level: $PROMOTE_TOP_LEVEL"
echo "History strategy:  $HISTORY_STRATEGY"
echo ""

# ──────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT — verify source state
# ──────────────────────────────────────────────────────────────────────────

echo "── Pre-flight: source vault state ──"

if [ ! -d "$SOURCE_VAULT/.git" ]; then
  echo "✗ Source not a git repo: $SOURCE_VAULT"
  exit 1
fi

cd "$SOURCE_VAULT"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ Source vault has uncommitted changes — commit or stash first"
  git status --short | head -10
  exit 1
fi

echo "✓ Source vault clean"

# Verify Phase 0 cleanup landed (these are smoke checks, not exhaustive)
PHASE0_FLAGS_REMAINING=0

if grep -rl --exclude-dir=.git "~/obsidian" commands/ 2>/dev/null | head -1 > /dev/null; then
  echo "⚠ Phase 0.1 may not be complete: hardcoded ~/obsidian found in commands/"
  PHASE0_FLAGS_REMAINING=$((PHASE0_FLAGS_REMAINING + 1))
fi

if [ -f "hooks/com.sovra.claude-quota-watch.plist" ]; then
  echo "⚠ Phase 0.2 may not be complete: sovra-named plist still present"
  PHASE0_FLAGS_REMAINING=$((PHASE0_FLAGS_REMAINING + 1))
fi

if git ls-files mcps/playwright-mcp/auth/ 2>/dev/null | head -1 > /dev/null; then
  echo "⚠ Phase 0.3 may not be complete: auth/ files still tracked"
  PHASE0_FLAGS_REMAINING=$((PHASE0_FLAGS_REMAINING + 1))
fi

if [ -d "vault/00 - notes/context/ventures/sovra" ] && [ ! -f ".phase0-sovra-stripped" ]; then
  echo "⚠ Phase 0.4 may not be complete: ventures/sovra/ still in product layer (touch .phase0-sovra-stripped to acknowledge)"
  PHASE0_FLAGS_REMAINING=$((PHASE0_FLAGS_REMAINING + 1))
fi

if [ $PHASE0_FLAGS_REMAINING -gt 0 ]; then
  echo ""
  echo "✗ Phase 0 cleanup incomplete ($PHASE0_FLAGS_REMAINING flags). Land Phase 0 commits first."
  if [ "$MODE" = "--execute" ]; then
    echo "  (Use --dry-run to preview anyway)"
    exit 1
  fi
fi

echo "✓ Phase 0 smoke check passed"

# ──────────────────────────────────────────────────────────────────────────
# ASSEMBLE — build the snapshot
# ──────────────────────────────────────────────────────────────────────────

echo ""
echo "── Assemble: building destination snapshot ──"

${DRY}rm -rf "$DEST_REPO"
${DRY}mkdir -p "$DEST_REPO"

# Top-level files
${DRY}cp "$SOURCE_VAULT/CLAUDE.md" "$DEST_REPO/CLAUDE.md"
${DRY}cp "$SOURCE_VAULT/CHANGELOG.md" "$DEST_REPO/CHANGELOG.md"

# Product-infra directories (always at top level)
for d in commands hooks mcps plugins skills; do
  if [ -d "$SOURCE_VAULT/$d" ]; then
    ${DRY}cp -R "$SOURCE_VAULT/$d" "$DEST_REPO/"
    echo "  ✓ $d/ copied"
  fi
done

# Templates + agents — promoted to top-level OR nested per flag
if [ "$PROMOTE_TOP_LEVEL" = "true" ]; then
  ${DRY}cp -R "$SOURCE_VAULT/vault/02 - templates" "$DEST_REPO/templates"
  ${DRY}cp -R "$SOURCE_VAULT/vault/06 - agents" "$DEST_REPO/agents"
  echo "  ✓ templates/ + agents/ promoted to top-level"
else
  ${DRY}mkdir -p "$DEST_REPO/vault"
  ${DRY}cp -R "$SOURCE_VAULT/vault/02 - templates" "$DEST_REPO/vault/02 - templates"
  ${DRY}cp -R "$SOURCE_VAULT/vault/06 - agents" "$DEST_REPO/vault/06 - agents"
  echo "  ✓ templates/ + agents/ nested under vault/"
fi

# Strip personal-only overlays from agents/ (my-agents/ stays in chuy's vault, not product)
if [ -d "$DEST_REPO/agents/my-agents" ]; then
  ${DRY}rm -rf "$DEST_REPO/agents/my-agents"
  echo "  ✓ agents/my-agents/ stripped (personal addon, stays in user vault)"
fi
if [ -d "$DEST_REPO/vault/06 - agents/my-agents" ]; then
  ${DRY}rm -rf "$DEST_REPO/vault/06 - agents/my-agents"
fi

# Write HISTORY pointer
HISTORY_NOTE="$DEST_REPO/HISTORY-PRE-2026-05-21.md"
${DRY}cat > "$HISTORY_NOTE" <<'HEOF'
# Pre-extraction history

The AIOS infrastructure (commands/, hooks/, mcps/, plugins/, skills/, templates/, agents/)
evolved inside [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) from
Mar 2026 through May 20, 2026 before being extracted as a standalone framework
under The-AIOS/aios on 2026-05-21.

This file exists because the extraction used a squash-initial-commit strategy
rather than a full git-history-preserving extract (per the deployment plan's
sarah-lean decision). The full development history — every commit, every PR,
every Co-Authored-By trail — is preserved at:

  https://github.com/chuycepeda/obsidian

If you need to trace the lineage of a specific file or feature in this repo
back to its origins, check chuycepeda/obsidian's commits through May 20, 2026.

Post-2026-05-21 history (this repo's git log) is the canonical record going
forward. The chuycepeda/obsidian vault continues to evolve in parallel —
extending AIOS with vault content, user-specific addons, and personal-scope
infrastructure that doesn't belong in the public distribution.
HEOF
echo "  ✓ HISTORY-PRE-2026-05-21.md written"

# ──────────────────────────────────────────────────────────────────────────
# COMMIT — initialize as a fresh git repo and push to The-AIOS/aios
# ──────────────────────────────────────────────────────────────────────────

echo ""
echo "── Commit: initial commit + push ──"

${DRY}cd "$DEST_REPO"
${DRY}git init
${DRY}git add -A

EXTRACT_DATE=$(date -u +%Y-%m-%d)
${DRY}git commit -m "init: extract AIOS framework from chuycepeda/obsidian ($EXTRACT_DATE)

Phase 1 cutover per the AIOS Deployment Plan
(vault/00 - notes/reflections/plans/2026-05-09-aios-deployment-plan.md).

Contents:
- commands/ — vault-command files
- hooks/ — Claude Code event hooks + harness wrappers
- mcps/ — bundled MCP servers
- plugins/ — Claude Code plugins
- skills/ — reusable capabilities
- templates/ — vault templates ($([ "$PROMOTE_TOP_LEVEL" = "true" ] && echo "promoted from vault/02 - templates/" || echo "nested under vault/02 - templates/"))
- agents/ — task agents ($([ "$PROMOTE_TOP_LEVEL" = "true" ] && echo "promoted from vault/06 - agents/" || echo "nested under vault/06 - agents/"))

Phase 0 cleanup landed in chuycepeda/obsidian before this extract
(path-config-driven, sovra-strip, plist-rename, auth-gitignore).

Full pre-extraction history at chuycepeda/obsidian.
See HISTORY-PRE-2026-05-21.md for lineage.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"

# Force-push to overwrite the scaffold sarah pushed overnight (sarah's scaffold
# commit `43065c8` was a placeholder; this commit is the real initial state)
${DRY}git remote add origin "$REMOTE_URL"
${DRY}git branch -M main
${DRY}git push --force-with-lease origin main

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✓ Extract complete"
echo "  Destination: $REMOTE_URL"
echo "  Local working copy: $DEST_REPO"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Next steps (per migration map § Tomorrow's execution order):"
echo "  4. Phase 1 tracker rewire (.vault-update → The-AIOS/aios)"
echo "  5. First external clone validation (chuy clones to ~/Documents/test-aios)"
echo "  6. sovrahq/internal-vault archive (see sovrahq-audit-checklist.md)"
echo "  7. Zineb-clone validation"

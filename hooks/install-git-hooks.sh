#!/usr/bin/env bash
# install-git-hooks.sh — wire a concurrently-written AIOS repo to the attribution guard.
# git config is NOT version-controlled, so this runs per-machine (idempotent). Targets the
# vault (~/aios) by default; pass a repo path to guard another (e.g. the canonical repo).
# Auto-run by /aios:update when hooks/git or aios-commit changes (like install-wrappers.sh).
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"          # …/hooks
chmod +x "$HOOKS_DIR/aios-commit" "$HOOKS_DIR/git/pre-commit" "$HOOKS_DIR/git/secret-scan.sh" 2>/dev/null || true

REPO="${1:-$HOME/aios}"
[ -d "$REPO/.git" ] || { echo "install-git-hooks: $REPO is not a git repo — skipped" >&2; exit 0; }

# core.hooksPath relative to the repo root → each repo uses its own hooks/git copy
git -C "$REPO" config core.hooksPath "hooks/git"

# put aios-commit on PATH for agents/rituals that call it by name (idempotent symlink)
BINDIR="$HOME/.local/bin"; mkdir -p "$BINDIR"
ln -sf "$HOOKS_DIR/aios-commit" "$BINDIR/aios-commit"

echo "aios git-hooks installed on $REPO → core.hooksPath = hooks/git"
echo "  raw 'git commit' is now guarded; commit via  aios-commit -m \"…\" <paths>"
echo "  ('$BINDIR' on PATH? add it if not: export PATH=\"\$HOME/.local/bin:\$PATH\")"

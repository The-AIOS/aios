#!/usr/bin/env bash
# install-git-hooks.sh — wire a concurrently-written AIOS repo to the attribution guard.
# git config is NOT version-controlled, so this runs per-machine (idempotent). Targets the
# vault (~/aios) by default; pass a repo path to guard another (e.g. the canonical repo).
# Auto-run by /aios:update when hooks/git or aios-commit changes (like install-wrappers.sh).
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"          # …/hooks

# Make every hook runnable — DERIVED from what is in hooks/git, never a hardcoded list.
# The list used to name pre-commit and secret-scan.sh literally, so pre-push shipped
# without an exec bit the day it was added. Same class as this framework's other
# enumeration bugs: a list can only describe the files that existed when it was written.
chmod +x "$HOOKS_DIR/aios-commit" 2>/dev/null || true
for _h in "$HOOKS_DIR/git/"*; do
  case "$_h" in *.md|*'*') continue ;; esac
  [ -f "$_h" ] && { chmod +x "$_h" 2>/dev/null || true; }
done

# Normalize CRLF -> LF on the hook scripts. This is the ONLY surface that reaches every
# operator, which is why it lives here rather than in .gitattributes:
#   * .gitattributes DOES carry `text eol=lf` for these paths, but it is Tier-0 — it never
#     reaches an operator vault through /aios:update, and a fork's copy freezes at fork time.
#   * On Windows, core.autocrlf=true (the Git-for-Windows default) rewrites LF -> CRLF on
#     checkout. git then runs the hook through sh, where a trailing \r makes the shebang
#     unresolvable — measured: `env: bash\r: No such file or directory`, exit 127.
# The consequence is not a mangled message: git treats any non-zero pre-commit/pre-push exit
# as a refusal, so the operator simply cannot commit or push, with an error naming neither
# AIOS nor the cause. Strip only a CR that terminates a line; a lone CR inside a string stays.
for _h in "$HOOKS_DIR/git/"* "$HOOKS_DIR/aios-commit"; do
  case "$_h" in *.md|*'*') continue ;; esac
  [ -f "$_h" ] || continue
  LC_ALL=C grep -q $'\r' "$_h" 2>/dev/null || continue
  _t="$_h.aios-eol.$$"
  # `cat "$_t" > "$_h"`, NOT `mv "$_t" "$_h"`. mv replaces the inode, so the hook would
  # inherit the temp file's default mode and lose the exec bit the chmod above just set —
  # trading a CRLF hook that cannot run for an LF hook that cannot run. Redirecting writes
  # through the existing inode and leaves its mode alone.
  if sed $'s/\r$//' "$_h" > "$_t" 2>/dev/null && cat "$_t" > "$_h" 2>/dev/null; then
    rm -f "$_t"; echo "  normalized CRLF -> LF: $(basename "$_h")"
  else
    rm -f "$_t"; echo "  WARNING: could not normalize line endings in $_h - the hook may not run" >&2
  fi
done

REPO="${1:-$HOME/aios}"
[ -d "$REPO/.git" ] || { echo "install-git-hooks: $REPO is not a git repo — skipped" >&2; exit 0; }

# core.hooksPath relative to the repo root → each repo uses its own hooks/git copy
git -C "$REPO" config core.hooksPath "hooks/git"

# put aios-commit on PATH for agents/rituals that call it by name (idempotent symlink)
BINDIR="$HOME/.local/bin"; mkdir -p "$BINDIR"
ln -sf "$HOOKS_DIR/aios-commit" "$BINDIR/aios-commit"

echo "aios git-hooks installed on $REPO → core.hooksPath = hooks/git"
echo "  raw 'git commit' is now guarded; commit via  aios-commit -m \"…\" <paths>"
echo "  pre-push refuses off-limits remote owners — inert until you set them:"
echo "      git config --global aios.blockedRemoteOwners \"AcmeCorp anotherorg\""
echo "  ('$BINDIR' on PATH? add it if not: export PATH=\"\$HOME/.local/bin:\$PATH\")"

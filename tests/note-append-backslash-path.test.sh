#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# `aios-note-append --before` reads a block file whose path contains backslashes
#
# The block path used to reach awk as `-v bf="$BLOCKFILE"`. awk processes escape
# sequences in a `-v` assignment, so a Windows temp path (C:\Users\...\Temp\...)
# lost characters at every \U, \L, \T. getline then failed, the block read as
# EMPTY, the note was rewritten unchanged, and aios-commit reported "nothing to
# commit" -- a lost session block that looked like success (#361).
#
# On Windows (cygpath present) the test passes the block path in native form.
# Elsewhere it uses a directory whose NAME contains `\t` and `\U` sequences,
# which reproduces the same escape-processing on Linux and macOS.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

HELPER="$PWD/hooks/vault/aios-note-append"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -x "$HELPER" ] || { printf '  FAIL  %s missing\n' "$HELPER"; exit 1; }

D="$TMP/vault"; mkdir -p "$D"
( cd "$D" && git init -q . && git config user.email t@example.com && git config user.name t )
printf '# Day\n\n## Plan\nwork\n\n## Close of Day\ndone\n' > "$D/note.md"
( cd "$D" && git add -A && git commit -qm init )

if command -v cygpath >/dev/null 2>&1; then
  BD="$TMP/blocks"; mkdir -p "$BD"
  printf '## Session — 10:00 | probe\nbody\n' > "$BD/block.md"
  BLOCK="$(cygpath -w "$BD/block.md")"
else
  BD="$TMP/a\\tb\\Users\\Temp"; mkdir -p "$BD"
  printf '## Session — 10:00 | probe\nbody\n' > "$BD/block.md"
  BLOCK="$BD/block.md"
fi
case "$BLOCK" in *\\*) ;; *) no "fixture: block path has no backslash" "$BLOCK" ;; esac

echo "── 1. a backslash path with --before inserts the block ──"
OUT="$( cd "$D" && "$HELPER" --note "$D/note.md" --block-file "$BLOCK" --before "## Close of Day" -m "probe" --no-push 2>&1 )"
RC=$?
[ "$RC" = 0 ] && ok "helper exited 0" || no "helper exited $RC" "$OUT"
ORDER="$(grep '^## ' "$D/note.md" | sed 's/ *|.*//' | tr '\n' '>')"
[ "$ORDER" = "## Plan>## Session — 10:00>## Close of Day>" ] \
  && ok "block landed before the marker" || no "block missing or misplaced" "$ORDER"
( cd "$D" && git log -1 --format=%s ) | grep -q probe \
  && ok "the note was committed" || no "no commit was made"

echo "── 2. an unreadable block is a loud failure, never 'nothing to commit' ──"
BEFORE_SUM="$(cksum < "$D/note.md")"
chmod 000 "$BD/block.md" 2>/dev/null
if [ -r "$BD/block.md" ]; then
  ok "skipped: this platform cannot make the block unreadable"
else
  OUT="$( cd "$D" && "$HELPER" --note "$D/note.md" --block-file "$BLOCK" --before "## Close of Day" -m "probe2" --no-push 2>&1 )"
  RC=$?
  [ "$RC" != 0 ] && ok "helper failed (exit $RC)" || no "helper reported success on an unreadable block" "$OUT"
  [ "$(cksum < "$D/note.md")" = "$BEFORE_SUM" ] && ok "note unchanged" || no "note was modified"
fi
chmod 644 "$BD/block.md" 2>/dev/null

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]

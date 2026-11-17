#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# `aios-note-append --create-if-missing` creates the note UNDER the append lock
#
# The first close of the day often runs before anyone has written the daily
# note. Without the flag the helper dies with "note does not exist", so callers
# created the note themselves with a plain write first -- a check-then-create
# race: two sessions both see "missing", both write the file, and the slower
# write erases the block the faster one had already appended. Nothing errors,
# and neither session can see the loss.
#
# The flag moves the "does it exist?" decision inside the per-file lock the
# append already takes, so exactly one holder creates and every later holder
# finds the file and appends.
#
# REFUSAL cases first: without the flag a missing note must still fail, and
# must leave nothing behind -- the default behaviour is not allowed to change.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

HELPER="$PWD/hooks/vault/aios-note-append"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -x "$HELPER" ] || { printf '  FAIL  %s missing\n' "$HELPER"; exit 1; }

mkrepo(){ # $1 = dir name -> echoes repo path (one seed commit, no note)
  local d="$TMP/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name t )
  printf 'x\n' > "$d/seed"; ( cd "$d" && git add -A && git commit -qm init ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
printf '## Session — 19:19 | new work\nbody\n' > "$TMP/block.md"

echo "── 1. REFUSAL: without the flag a missing note still fails ──"
R="$(mkrepo noflag)"; N="$R/2026-10/2026-10-14.md"
OUT="$( cd "$R" && "$HELPER" --note "$N" --block-file "$TMP/block.md" -m x --no-push 2>&1 )"; RC=$?
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -F 'note does not exist' >/dev/null; } \
  && ok "missing note refused (rc=$RC), naming the reason" || no "missing note accepted without the flag" "rc=$RC $OUT"
[ ! -e "$N" ] && ok "no note was created" || no "a note was created without the flag"
[ ! -e "$R/2026-10" ] && ok "no directory was created" || no "the note's directory was created without the flag"

echo "── 2. REFUSAL: --header without --create-if-missing is an error ──"
R="$(mkrepo hdr)"; printf '# Day\n' > "$R/note.md"
OUT="$( cd "$R" && "$HELPER" --note "$R/note.md" --block-file "$TMP/block.md" --header "# X" -m x --no-push 2>&1 )"; RC=$?
[ "$RC" -ne 0 ] && ok "--header alone refused" || no "--header alone accepted" "$OUT"
[ "$(cat "$R/note.md")" = "# Day" ] && ok "and the note is untouched" || no "note changed" "$(cat "$R/note.md")"

echo "── 3. REFUSAL: a directory at the note path is not 'missing' ──"
R="$(mkrepo isdir)"; mkdir -p "$R/note.md"
OUT="$( cd "$R" && "$HELPER" --note "$R/note.md" --block-file "$TMP/block.md" --create-if-missing -m x --no-push 2>&1 )"; RC=$?
[ "$RC" -ne 0 ] && ok "a directory at the path is refused" || no "appended into a directory path" "$OUT"

echo "── 4. with the flag: creates the note (and its folder), appends, commits ──"
R="$(mkrepo create)"; N="$R/2026-10/2026-10-14.md"
OUT="$( cd "$R" && "$HELPER" --note "$N" --block-file "$TMP/block.md" --before "## Close of Day" --create-if-missing -m "s1" --no-push 2>&1 )"; RC=$?
[ "$RC" -eq 0 ] && ok "rc=0" || no "rc=$RC" "$OUT"
[ -f "$N" ] && ok "note created (with its month folder)" || no "note not created"
[ "$(cat "$N" 2>/dev/null)" = "$(cat "$TMP/block.md")" ] \
  && ok "an empty-created note holds exactly the block (no leading blank line)" \
  || no "unexpected content" "$(cat "$N" 2>/dev/null)"
git -C "$R" ls-files --error-unmatch "2026-10/2026-10-14.md" >/dev/null 2>&1 \
  && ok "the new note was committed" || no "the new note is not tracked"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "worktree clean afterwards (lock released)" \
  || no "leftovers" "$(git -C "$R" status --porcelain)"

echo "── 5. --header seeds the new note; an existing note is never re-created ──"
R="$(mkrepo header)"; N="$R/note.md"
( cd "$R" && "$HELPER" --note "$N" --block-file "$TMP/block.md" --create-if-missing --header "# 2026-10-14" -m s1 --no-push ) >/dev/null 2>&1
[ "$(head -1 "$N")" = "# 2026-10-14" ] && ok "header is the first line" || no "header missing" "$(head -3 "$N")"
grep -c '^## Session' "$N" | grep -qx 1 && ok "block appended after it" || no "block missing" "$(cat "$N")"
printf '## Session — 20:00 | second\nb\n' > "$TMP/b2.md"
( cd "$R" && "$HELPER" --note "$N" --block-file "$TMP/b2.md" --create-if-missing --header "# OTHER" -m s2 --no-push ) >/dev/null 2>&1
{ [ "$(grep -c '^## Session' "$N")" = 2 ] && [ "$(grep -c '^# ' "$N")" = 1 ] && [ "$(head -1 "$N")" = "# 2026-10-14" ]; } \
  && ok "second run appended to the existing note; header not rewritten" || no "existing note was re-created or re-headed" "$(cat "$N")"

echo "── 6. CONCURRENCY: N writers race to create the same missing note ──"
R="$(mkrepo conc)"; N="$R/2026-10/2026-10-14.md"
K=6
for i in $(seq 1 $K); do printf '## Session — %s\nb%s\n' "$i" "$i" > "$TMP/c$i.md"; done
for i in $(seq 1 $K); do
  ( cd "$R" && "$HELPER" --note "$N" --block-file "$TMP/c$i.md" --before "## Close of Day" --create-if-missing -m "s$i" --no-push >/dev/null 2>&1; echo $? > "$TMP/rc$i" ) &
done
wait
BAD=0; for i in $(seq 1 $K); do [ "$(cat "$TMP/rc$i")" = 0 ] || BAD=$((BAD+1)); done
[ "$BAD" = 0 ] && ok "all $K writers exited 0" || no "$BAD of $K writers failed"
LANDED="$(grep -c '^## Session — ' "$N" 2>/dev/null || true)"
[ "$LANDED" = "$K" ] && ok "$K concurrent creators, $K blocks landed — none erased" \
  || no "only $LANDED of $K blocks survived" "$(cat "$N" 2>/dev/null)"
MISSING=""; for i in $(seq 1 $K); do grep -qx "b$i" "$N" || MISSING="$MISSING $i"; done
[ -z "$MISSING" ] && ok "every block's body is present" || no "bodies missing:$MISSING"
[ -z "$(git -C "$R" status --porcelain)" ] && ok "all of it committed, no lock left behind" \
  || no "leftovers" "$(git -C "$R" status --porcelain)"

echo "── 7. CONTROL: the caller-side create this flag replaces DOES lose blocks ──"
# Replays the retired pattern -- check, then write the note with the block, outside
# any lock -- and requires it to lose something. Without the control this suite
# could pass against a helper that never needed the lock.
C="$TMP/ctl"; mkdir -p "$C"
for i in $(seq 1 $K); do
  ( [ -f "$C/note.md" ] || { sleep 0.2; cat "$TMP/c$i.md" > "$C/note.md"; } ) &
done
wait
GOT="$(grep -c '^## Session — ' "$C/note.md" || true)"
[ "$GOT" -lt "$K" ] && ok "control: check-then-create kept $GOT of $K (the race reproduces)" \
  || no "control: check-then-create kept all $K" "if this no longer reproduces, re-derive why the flag exists"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

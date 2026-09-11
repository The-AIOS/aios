#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The daily note's section order — `## Close of Day` stays last (AI-126 bundle)
#
# Reported 2026-09-09: two `--auto` close blocks "landed BELOW Close of Day".
# The reported cause was `aios-note-append --before` failing to find its marker.
# The git history says otherwise — at 18:43 and 19:20, when those two blocks were
# appended, the note contained NO `## Close of Day` at any line, so appending at
# the end was the only correct action and the helper did it correctly. The marker
# appeared at 20:11, inserted by /close-day at line 153 of a note whose session
# blocks already ran to line 267.
#
# So the defect was placement by /close-day, and the helper was sound. This suite
# asserts the CONTRACT rather than either implementation's current text, because
# the contract is what the two commands share:
#
#   Close of Day is the LAST section. /close-session inserts before it, so the
#   marker being last is exactly what keeps session blocks above it.
#
# It is checked end to end against the real helper — a close-day append followed
# by a session close — so it fails if either side stops holding up its half.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

HELPER="$PWD/hooks/aios-note-append"
CLOSE_DAY="plugins/aios/commands/close-day.md"
CLOSE_SESSION="plugins/aios/commands/close-session.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[ -x "$HELPER" ] || { printf '  FAIL  %s missing or not executable\n' "$HELPER"; exit 1; }

# a throwaway repo, because the helper commits through aios-commit
mk_note(){ # $1 = note contents on stdin → echoes the note path
  local d="$TMP/repo-$RANDOM"; mkdir -p "$d"
  ( cd "$d" && git init -q . \
      && git config user.email t@example.com && git config user.name t )
  cat > "$d/note.md"
  ( cd "$d" && git add -A && git commit -qm init )
  printf '%s\n' "$d/note.md"
}
append(){ # $1 = note · $2 = block text file · $3.. = extra args
  local n="$1" b="$2"; shift 2
  ( cd "$(dirname "$n")" && "$HELPER" --note "$n" --block-file "$b" -m "probe" --no-push "$@" ) >/dev/null 2>&1
}
headings(){ grep '^## ' "$1" | sed 's/ *|.*//'; }

echo "── 1. the specs agree on the contract ──"
grep -q -- '--before "## Close of Day"' "$CLOSE_SESSION" \
  && ok "/close-session inserts before the Close of Day marker" \
  || no "/close-session no longer uses --before \"## Close of Day\"" \
        "if that changed, the ordering contract changed with it — update this suite deliberately"
grep -q 'aios-note-append' "$CLOSE_DAY" \
  && ok "/close-day writes through the locking helper" \
  || no "/close-day does not reference aios-note-append" \
        "a lock only works if EVERY writer takes it; a direct write here clobbers a concurrent session block"
grep -qiE 'LAST section|at the END of the note' "$CLOSE_DAY" \
  && ok "/close-day names the end of the note as the insertion point" \
  || no "/close-day never says WHERE its block goes" \
        "unstated placement is how it landed mid-note above two session blocks"

echo "── 2. helper: marker ABSENT → append at end ──"
# This is the case the incident was blamed on. It is correct behaviour: with no
# marker in the file there is nowhere else for the block to go.
N="$(printf '%s\n' '# Day' '' '## Energy note' '_Close-day question: did it land?_' | mk_note)"
printf '%s\n' '## Session — 18:05 | first' 'body' > "$TMP/b1.md"
append "$N" "$TMP/b1.md" --before "## Close of Day"
if [ "$(headings "$N" | tail -1)" = "## Session — 18:05" ]; then
  ok "no marker → block appended at the end"
else
  no "unexpected order with the marker absent" "$(headings "$N" | tr '\n' '|')"
fi

echo "── 3. helper: marker PRESENT → insert above it ──"
N="$(printf '%s\n' '# Day' '' '## Session — 18:05 | first' 'body' '' '## Close of Day' 'verdict' | mk_note)"
printf '%s\n' '## Session — 19:19 | second' 'body' > "$TMP/b2.md"
append "$N" "$TMP/b2.md" --before "## Close of Day"
GOT="$(headings "$N" | tr '\n' '|')"
[ "$GOT" = "## Session — 18:05|## Session — 19:19|## Close of Day|" ] \
  && ok "marker present → inserted above it, after the earlier session" \
  || no "insertion landed wrong" "$GOT"

echo "── 4. END TO END — close-day appends last, then two sessions close ──"
# The actual reported sequence, with the fixed ordering: sessions run, close-day
# appends its block at the END (no --before), then later sessions close against
# the marker. Close of Day must still be last and no session may be below it.
N="$(printf '%s\n' '# Day' '' '## Energy note' '_Close-day question: did it land?_' | mk_note)"
printf '%s\n' '## Session — 18:05 | first' 'body' > "$TMP/s1.md"
printf '%s\n' '## Close of Day' 'verdict' > "$TMP/cd.md"
printf '%s\n' '## Session — 18:42 | second' 'body' > "$TMP/s2.md"
printf '%s\n' '## Session — 19:19 | third'  'body' > "$TMP/s3.md"
append "$N" "$TMP/s1.md" --before "## Close of Day"   # marker absent → end
append "$N" "$TMP/cd.md"                              # close-day: NO --before
append "$N" "$TMP/s2.md" --before "## Close of Day"
append "$N" "$TMP/s3.md" --before "## Close of Day"
GOT="$(headings "$N" | tr '\n' '|')"
WANT="## Energy note|## Session — 18:05|## Session — 18:42|## Session — 19:19|## Close of Day|"
[ "$GOT" = "$WANT" ] && ok "Close of Day is last; all three sessions above it" \
  || no "ordering broke" "got:  $GOT
        want: $WANT"
BELOW="$(sed -n '/^## Close of Day/,$p' "$N" | grep -c '^## Session —' || true)"
[ "$BELOW" = 0 ] && ok "no session block below Close of Day" \
  || no "$BELOW session block(s) below Close of Day — the reported symptom"

echo "── 5. CONTROL — the buggy placement must FAIL this suite ──"
# Anchoring the close-day block mid-note is what actually happened. If this suite
# cannot tell that apart from the fixed order, it is not measuring anything.
N="$(printf '%s\n' '# Day' '' '## Energy note' '_Close-day question: did it land?_' | mk_note)"
append "$N" "$TMP/s1.md" --before "## Close of Day"
append "$N" "$TMP/cd.md" --before "_Close-day question"   # the bug: mid-note anchor
append "$N" "$TMP/s2.md" --before "## Close of Day"
BELOW="$(sed -n '/^## Close of Day/,$p' "$N" | grep -c '^## Session —' || true)"
if [ "$BELOW" -ge 1 ]; then
  ok "control: a mid-note anchor puts $BELOW session(s) below the marker (detected)"
else
  no "control: the buggy placement produced a CLEAN note" \
     "this suite would pass against the defect it exists to catch"
fi

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

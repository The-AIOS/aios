#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# `aios-note-append --before` anchors to the START of a line, never mid-line
#
# A daily note is PROSE, and prose quotes headings. `--before "## Close of Day"`
# used to match with a bare `index($0, marker)`, so any sentence that happened to
# mention the marker became an insertion anchor.
#
# Measured 2026-09-11 on a live vault. A bullet written in the morning contained
# the words "the note held no `## Close of Day` at any line" -- a sentence
# DOCUMENTING this helper's behaviour. Hours later a close-session ran
# `--before "## Close of Day"` against a note with no such heading. Instead of
# appending at the end it anchored to that bullet, landing the session block in
# the middle of an unrelated section: the heading stayed above the block and its
# two bullets were stranded below. Nothing was deleted, nothing errored, and
# neither session could see it.
#
# This is antifragile #105's family -- "a guard written next to its own
# explanation matches the explanation" -- one domain over. There the instrument
# was a grep scanning source; here it is an insertion anchor scanning a note.
# Both break precisely BECAUSE the behaviour was worth documenting.
#
# Per #110 the REFUSAL cases are written first: the tests that prove a marker is
# NOT matched come before any happy path, because the bug lived entirely in the
# should-not-match branch while the happy path was fine throughout.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

HELPER="$PWD/hooks/aios-note-append"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -x "$HELPER" ] || { printf '  FAIL  %s missing\n' "$HELPER"; exit 1; }

mknote(){ # $1 = dir name; stdin = note body  -> echoes note path
  local d="$TMP/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q . && git config user.email t@example.com && git config user.name t )
  cat > "$d/note.md"
  ( cd "$d" && git add -A && git commit -qm init )
  printf '%s\n' "$d/note.md"
}
append(){ local n="$1" b="$2"; shift 2
  ( cd "$(dirname "$n")" && "$HELPER" --note "$n" --block-file "$b" -m "probe" --no-push "$@" ) >/dev/null 2>&1; }
# Heading SEQUENCE, never line numbers: the contract is about order, and a
# line-number assertion breaks on any unrelated edit to the fixture.
heads(){ grep '^## ' "$1" | sed 's/ *|.*//' | tr '\n' '>'; }

printf '## Session — 19:19 | new work\nbody\n' > "$TMP/block.md"

echo "── 1. REFUSAL: a marker quoted INSIDE prose must not anchor ──"
# The exact incident. The marker appears mid-line in a bullet; there is no such
# heading anywhere. Correct behaviour: append at the END, bullet untouched.
N="$(mknote prose <<'NOTE'
# Day

## Today I ship
the deliverable

## Work orders
- **canonical** — the history settles it: the note held no `## Close of Day` at any line, so the end was the only correct place.
- **app** — second bullet

## Rhythm
morning
NOTE
)"
append "$N" "$TMP/block.md" --before "## Close of Day"
GOT="$(heads "$N")"
if [ "$GOT" = "## Today I ship>## Work orders>## Rhythm>## Session — 19:19>" ]; then
  ok "prose mention did NOT anchor; the block went to the end"
else
  no "the quoted marker anchored the block mid-note" "$GOT"
fi
# the two bullets must still sit together under their own heading
BODY="$(awk '/^## Work orders/{f=1;next} f&&/^## /{exit} f' "$N" | grep -c '^- \*\*')"
[ "$BODY" = 2 ] && ok "both bullets still under their heading" \
  || no "the section was split — $BODY of 2 bullets remain under it"
tail -3 "$N" | grep -q '^## Session — 19:19' \
  && ok "block appended at the end, where a missing marker belongs" \
  || no "block did not land at the end" "$(tail -4 "$N")"

echo "── 2. REFUSAL: marker absent entirely → append at end ──"
N="$(mknote absent <<'NOTE'
# Day

## Rhythm
morning
NOTE
)"
append "$N" "$TMP/block.md" --before "## Close of Day"
tail -3 "$N" | grep -q '^## Session — 19:19' \
  && ok "no marker at all → end" || no "unexpected placement" "$(cat "$N")"

echo "── 3. REFUSAL: a line that merely STARTS with similar text ──"
# `index()==1` still requires the marker to be the line's prefix, so a heading
# that merely shares a prefix word must not steal the anchor.
N="$(mknote prefix <<'NOTE'
# Day

## Closing notes
not the marker

## Close of Day
verdict
NOTE
)"
append "$N" "$TMP/block.md" --before "## Close of Day"
GOT="$(heads "$N")"
[ "$GOT" = "## Closing notes>## Session — 19:19>## Close of Day>" ] \
  && ok "anchored to the real heading, not the similar one" || no "wrong anchor" "$GOT"
awk '/^## Session — 19:19/{s=NR} /^## Close of Day/{c=NR} END{exit !(s<c)}' "$N" \
  && ok "block sits above Close of Day" || no "block did not land above the marker"

echo "── 4. HAPPY PATH: a real heading anchors ──"
N="$(mknote happy <<'NOTE'
# Day

## Session — 18:05 | earlier
body

## Close of Day
verdict
NOTE
)"
append "$N" "$TMP/block.md" --before "## Close of Day"
GOT="$(heads "$N")"
[ "$GOT" = "## Session — 18:05>## Session — 19:19>## Close of Day>" ] \
  && ok "inserted above the marker, after the earlier session" || no "ordering wrong" "$GOT"

echo "── 5. CONTROL: the retired substring rule must FAIL these fixtures ──"
# Without this the suite could pass against either implementation. Replay the old
# predicate on the incident fixture and require it to place the block WRONG.
cat > "$TMP/old.awk" <<'AWK'
BEGIN{ blk=""; while((getline l < bf) > 0) blk = blk l "\n" }
!done && index($0, marker) { printf "%s%s\n", blk, $0; done=1; next }
{ print }
AWK
printf '# Day\n\n## Work orders\n- the note held no `## Close of Day` at any line\n- second bullet\n\n## Rhythm\nx\n' > "$TMP/ctl.md"
awk -v marker="## Close of Day" -v bf="$TMP/block.md" -f "$TMP/old.awk" "$TMP/ctl.md" > "$TMP/ctl.out"
if awk '/^## Session — 19:19/{s=NR} /^## Rhythm/{r=NR} END{exit !(s>0 && s<r)}' "$TMP/ctl.out"; then
  ok "control: the old rule DOES mis-anchor into the section (bug reproduced)"
else
  no "control: the old rule placed it correctly" \
     "if the defect no longer reproduces, re-derive why this suite exists before deleting it"
fi

echo "── 6. one matcher decides both branches ──"
# The retired version asked `grep -qF` whether to enter the awk, so two different
# matchers had to agree; a marker grep found but awk would not placed the block
# by the wrong rule. The decision must live in exactly one predicate.
if grep -qE 'grep -qF -- "\$BEFORE"' "$HELPER"; then
  no "the helper still gates the awk on a separate grep matcher" \
     "grep and awk can disagree about the same question"
else
  ok "no second matcher gating the insert"
fi
grep -qF 'index($0, marker) == 1' "$HELPER" \
  && ok "the insert anchors at position 1" || no "the anchored predicate is gone"
grep -qE 'END\{ *if \(!done\)' "$HELPER" \
  && ok "the no-match case is handled in the same pass" || no "no END fallback — a missing marker may drop the block"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

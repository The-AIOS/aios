#!/usr/bin/env bash
# Regression suite for /close-session Mode A's idempotency gate (Step 4.5).
#
# The gate exists because a misbehaving command bus delivered `/aios:close-session --auto`
# to one session four times in twelve minutes (2026-08-12). Four blocks would have meant
# four copies of the same wins in the daily note AND four copies of the same Tier A/B
# candidates for /close-day to route into observed context.
#
# The FIRST version of the gate compared the stamped vault hash directly against the
# current HEAD. It was inert: appending a block commits it, so HEAD advances on every
# close, while the stamp can only hold the pre-commit value. `stamped == HEAD` was
# unsatisfiable, so the gate always appended and could never once fire.
#
# TEST 1 IS THE CONTROL THAT WOULD HAVE CAUGHT THAT, and it is the reason this file
# exists: it asserts the duplicate branch is REACHABLE. A comparison whose equal branch
# cannot happen is not a check. Every other test here is downstream of that one.

set -u
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || { no "$3"; printf '       expected %s, got %s\n' "$2" "$1"; }; }

WORK=$(mktemp -d) || { echo "cannot mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

git init -q . 2>/dev/null
git config user.email t@example.com; git config user.name Test; git config commit.gpgsign false

SID="11111111-2222-3333-4444-555555555555"
NOTE="note.md"

# --- the gate, transcribed from close-session.md Step 4.5 -------------------
# Returns: SKIP (duplicate) | APPEND (first close or real work since)
gate(){
  local sid="$1"
  local prior stamped work
  prior=$(grep -o "<!-- close-session: ${sid} @ [0-9a-f]* -->" "$NOTE" 2>/dev/null | tail -1)
  [ -z "$prior" ] && { echo APPEND; return; }
  stamped=$(printf '%s' "$prior" | sed -E 's/.* @ ([0-9a-f]*) -->/\1/')
  work=$(git log --format=%s "${stamped}..HEAD" 2>/dev/null | grep -cvE '^session: ')
  [ "$work" -eq 0 ] && echo SKIP || echo APPEND
}

# --- the ORIGINAL (broken) gate, kept so test 1 can prove it fails ---------
gate_v1(){
  local sid="$1" prior stamped head
  prior=$(grep -o "<!-- close-session: ${sid} @ [0-9a-f]* -->" "$NOTE" 2>/dev/null | tail -1)
  [ -z "$prior" ] && { echo APPEND; return; }
  stamped=$(printf '%s' "$prior" | sed -E 's/.* @ ([0-9a-f]*) -->/\1/')
  head=$(git rev-parse HEAD)
  [ "$stamped" = "$head" ] && echo SKIP || echo APPEND
}

# simulate a close: stamp the CURRENT head into the note, then commit the note
# (this ordering is the whole point — the stamp cannot know its own commit's hash)
do_close(){
  local sid="$1"
  printf '## Session — 10:00 | work\n<!-- close-session: %s @ %s -->\nbody\n\n' \
    "$sid" "$(git rev-parse HEAD)" >> "$NOTE"
  git add "$NOTE"; git commit -q -m "session: 10:00 work"
}

printf 'close-session idempotency gate\n'

echo "seed" > f; git add f; git commit -q -m "initial work"

# ---------------------------------------------------------------------------
# TEST 1 — THE CONTROL. The duplicate branch must be reachable.
# ---------------------------------------------------------------------------
do_close "$SID"
have "$(gate "$SID")" "SKIP" "1. duplicate branch is REACHABLE — a re-fire right after a close SKIPs"

# ---------------------------------------------------------------------------
# TEST 2 — the same scenario against the original logic. MUST differ, or test 1
# proves nothing about the fix (a test that passes both ways is not a regression test).
# ---------------------------------------------------------------------------
have "$(gate_v1 "$SID")" "APPEND" "2. original logic returns APPEND on that same duplicate (i.e. was inert)"

# ---------------------------------------------------------------------------
# TEST 3 — real work since the stamp must still append.
# ---------------------------------------------------------------------------
echo "more" >> f; git add f; git commit -q -m "feat: real work landed"
have "$(gate "$SID")" "APPEND" "3. real (non-close) work since the stamp → APPEND"

# ---------------------------------------------------------------------------
# TEST 4 — a second close after real work stamps again and re-arms the gate.
# ---------------------------------------------------------------------------
do_close "$SID"
have "$(gate "$SID")" "SKIP" "4. after a legitimate 2nd close, a further re-fire SKIPs again"

# ---------------------------------------------------------------------------
# TEST 5 — a DIFFERENT session must never be blocked by another's stamp.
# ---------------------------------------------------------------------------
have "$(gate "99999999-8888-7777-6666-555555555555")" "APPEND" "5. a different session id → APPEND (never blocked by a peer)"

# ---------------------------------------------------------------------------
# TEST 6 — several close commits in a row (block + observed context) still read as 0 work.
# ---------------------------------------------------------------------------
git commit -q --allow-empty -m "session: 2026-08-13 observed context — routed inline"
have "$(gate "$SID")" "SKIP" "6. multiple 'session:' commits (block + observed) still count as no work"

# ---------------------------------------------------------------------------
# TEST 7 — an unstamped legacy note appends (forward-only, loses nothing).
# ---------------------------------------------------------------------------
printf '## Session — 09:00 | legacy\nbody\n' > "$NOTE"
have "$(gate "$SID")" "APPEND" "7. legacy note with no stamp → APPEND"

# ---------------------------------------------------------------------------
# TEST 8 — a missing session id degrades to append, never to silence.
# ---------------------------------------------------------------------------
have "$(gate "unknown")" "APPEND" "8. SID 'unknown' → APPEND (degrade toward a block, never lose one)"

# ---------------------------------------------------------------------------
# TESTS 9-12 — provenance. The v2 gate counted any non-"session:" commit, so a
# PEER's commit read as "this session did work". Git cannot tell sessions apart,
# so aios-commit stamps AIOS-Session: and the gate reads it.
# ---------------------------------------------------------------------------
SID2="aaaabbbb-cccc-dddd-eeee-ffff00001111"

commit_as(){ # $1=session-id ("" = none) $2=subject
  echo "$RANDOM" >> f; git add f
  if [ -n "$1" ]; then git commit -q -m "$2

AIOS-Session: $1"
  else git commit -q -m "$2"; fi
}

# the v3 gate, transcribed from close-session.md Step 4.5
gate3(){
  local sid="$1" prior stamped range mine=0 anytag=0 b
  prior=$(grep -o "<!-- close-session: ${sid} @ [0-9a-f]* -->" "$NOTE" 2>/dev/null | tail -1)
  [ -z "$prior" ] && { echo APPEND; return; }
  stamped=$(printf '%s' "$prior" | sed -E 's/.* @ ([0-9a-f]*) -->/\1/')
  range=$(git log --format='%H' "${stamped}..HEAD" 2>/dev/null)
  for c in $range; do
    b=$(git log -1 --format='%B' "$c" 2>/dev/null)
    printf '%s' "$b" | grep -q '^AIOS-Session: ' && anytag=1
    printf '%s' "$b" | grep -q "^AIOS-Session: ${sid}$" || continue
    printf '%s' "$b" | head -1 | grep -qE '^session: ' && continue
    mine=$((mine+1))
  done
  if [ "$anytag" -eq 1 ]; then
    [ "$mine" -eq 0 ] && echo SKIP || echo APPEND
  else
    local w
    w=$(printf '%s\n' "$range" | while IFS= read -r c; do [ -n "$c" ] && git log -1 --format=%s "$c"; done | grep -cvE '^session: ')
    [ "$w" -eq 0 ] && echo SKIP || echo APPEND
  fi
}

# fresh note + a stamped close carrying provenance
printf '# note\n' > "$NOTE"
echo seed >> f; git add f; git commit -q -m "base"
printf '## Session — 10:00 | work\n<!-- close-session: %s @ %s -->\nbody\n' "$SID" "$(git rev-parse HEAD)" >> "$NOTE"
git add "$NOTE"; commit_as "$SID" "session: 10:00 work"

# 9 — a PEER commits. This session did nothing → must SKIP.
commit_as "$SID2" "feat: a different session's work"
have "$(gate3 "$SID")" "SKIP" "9. a PEER's commit does NOT count as this session's work"

# 10 — the v2 rule on that same state, to prove the test is not vacuous.
have "$(gate "$SID")" "APPEND" "10. v2 rule says APPEND on that same state (the imprecision)"

# 11 — this session then does real work → APPEND.
commit_as "$SID" "feat: my own work"
have "$(gate3 "$SID")" "APPEND" "11. this session's own non-close commit → APPEND"

# 12 — untagged range (a vault predating the trailer) degrades to the coarse rule.
printf '# note2\n' > "$NOTE"
echo x >> f; git add f; git commit -q -m "base2"
printf '## Session — 11:00 | w\n<!-- close-session: %s @ %s -->\nb\n' "$SID" "$(git rev-parse HEAD)" >> "$NOTE"
git add "$NOTE"; git commit -q -m "session: 11:00 w"
have "$(gate3 "$SID")" "SKIP" "12. no trailers in range → degrades to the coarse rule, still correct here"
commit_as "" "feat: untagged peer work"
have "$(gate3 "$SID")" "APPEND" "13. untagged work in range → APPEND (degrade toward a block, never silence)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

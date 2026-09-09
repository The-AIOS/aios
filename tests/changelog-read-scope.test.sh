#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:update must read the CHANGELOG in the operator's LANGUAGE and read only
# as much of the FILE as it needs.
#
# WHY. Two operator reports, one file. (1) The changelog is 74k+ words and grows
# monotonically, while a sync typically needs ONE entry -- Step 1.5 used to say
# "Read CHANGELOG.md from the cloned repo root", so every operator ingested the
# whole history on every sync. (2) An operator clicked Update on a Spanish-
# language surface, got an English wall, and could not follow what changed --
# the entries are English SOURCE TEXT, not the delivery.
#
# The read change is the dangerous one: making the reader cheaper must not make
# it stop earlier. The stop condition is the ANY-hash rule, unchanged -- an
# entry is new if ANY of its hashes is unsynced, so stopping on the first synced
# HASH (rather than the first fully-synced ENTRY) hides same-day subsections and
# the action items inside them. Under-reporting is the one failure a changelog
# cannot afford, so these checks assert the guard rails around the optimisation,
# not merely that the optimisation is described.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
U=plugins/aios/commands/update.md
C=CHANGELOG.md
for f in "$U" "$C"; do [ -f "$f" ] || { echo "::error::$f missing"; exit 1; }; done

echo "-- 1. the reader streams and stops; it does not load the file --"
grep -qF 'Do NOT `Read` the whole' "$U" && ok "the whole-file read is explicitly forbidden" \
  || no "no instruction against reading the whole file" "the default reading of 'Read CHANGELOG.md' is the 74k-word ingest"
grep -qiE 'newest-first|newest first' "$U" && ok "states why stopping early is safe (newest-first)" \
  || no "does not say entries are newest-first" "without it, stopping looks like truncation"

echo "-- 2. the optimisation cannot change what counts as NEW --"
# SCOPED to the warning block that states the invariant. A file-wide alternation passed a
# mutation that changed the normative sentence to "first synced hash" while a lowercase
# variant survived in prose nearby.
warn=$(awk '/Two ways to get this wrong/{f=1} f&&/^### /{exit} f' "$U")
printf '%s' "$warn" | grep -qF 'first fully-synced ENTRY' \
  && ok "stop condition is the ENTRY, not a hash (stated in the warning block)" \
  || no "stop condition not stated as the entry" "stopping on the first synced HASH hides same-day subsections"
grep -qiE 'unreachable hash is NOT synced|never satisfies the stop' "$U" \
  && ok "an unreachable hash never satisfies the stop" \
  || no "unreachable hashes may end the scan" "128 means inconclusive, never synced"
grep -qiE 'read \*\*one entry more\*\*|one entry more' "$U" \
  && ok "biases toward over-reading on doubt" \
  || no "no over-read bias" "under-reporting is the failure a changelog cannot afford"

echo "-- 3. a tracker with no baseline is capped, and says so --"
grep -qE 'newest 3 entries|newest [0-9]+ entries' "$U" && ok "caps the no-baseline case" \
  || no "no cap for hash=initial" "every entry reads as new -> the whole file lands in one message"
grep -qiE 'Never silently truncate' "$U" && ok "requires saying that it truncated" \
  || no "may truncate silently" "a silent cap is indistinguishable from 'nothing else changed'"
grep -qiE 'fresh install is not affected' "$U" && ok "scopes it to the recovery path, not fresh installs" \
  || no "does not distinguish fresh install from lost tracker" "SETUP records the real HEAD on purpose"

echo "-- 4. entries are delivered in the operator's language --"
grep -qiE "How to read this TO the operator" "$C" && ok "CHANGELOG states the language rule" \
  || no "no language rule in the changelog header" "an operator who cannot read the entry cannot verify the sync"
grep -qiE 'source text, not the delivery' "$C" && ok "names English as source, not delivery" \
  || no "does not separate source language from delivery"
grep -qiE "operator's language" "$U" && ok "/aios:update carries the instruction at the point of presentation" \
  || no "the executor never sees the rule" "a rule only in the data file is not read by the code path that renders it"
# one home for the rule: update.md must POINT at the header, not restate the signal list
if grep -qiE 'declared context.*writing to you in|surface.s own language setting' "$U"; then
  no "update.md restates the signal list" "one bound, one home -- it must reference CHANGELOG.md's header instead"
else ok "update.md references the rule rather than duplicating it"; fi
grep -qiE 'Leave unchanged|Keep unchanged' "$C" && ok "names what must NOT be translated (paths, commands, hashes)" \
  || no "no do-not-translate list" "a translated command name is an instruction that fails"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

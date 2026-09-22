#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Rules that must not be restated, and one rule that must not contradict another
#
# WHY
# A number restated outside its owner is a second implementation: it is right on
# the day it is copied and wrong from the day the owner moves, and nothing says
# so. An audit (#152–#155) found four live instances, each in a file an operator
# or session reads as authoritative:
#
#   #152  /aios:compact hand-rolled the snapshot `cp` CLAUDE.md forbids, and
#         required `entries == highest` while its own rules call a gap correct —
#         so every legitimate removal read as structural damage.
#   #153  CLAUDE.md told memory to hold preferences (dual-write) and, a paragraph
#         later, that a preference "never belonged in memory" (channeling).
#   #154  INTENT.md restated /close-day's project-note line threshold.
#   #155  /aios:housekeeping restated the context-rungs verdict as a token size;
#         the hook decides by a RATIO of everything to the floor.
#
# Each check below fails against the pre-fix text; each names the owner to read.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
has(){ grep -qF -- "$2" "$1"; }

C=plugins/aios/commands/compact.md
if has "$C" 'hooks/aios-snapshot "vault/00 - notes/context/observed/antifragile.md"'; then
  ok "#152 compact § 3.5 snapshots through aios-snapshot"
else no "#152 compact § 3.5 snapshots through aios-snapshot" "the snapshot step must call the tool, not hand-roll it"; fi
if grep -qE '`cp` the current file to .*observed-snapshots' "$C"; then
  no "#152 compact carries no hand-rolled snapshot cp" "$(grep -nE '`cp` the current file' "$C" | head -1 | cut -c1-120)"
else ok "#152 compact carries no hand-rolled snapshot cp"; fi
if has "$C" 'entries == highest` AND'; then
  no "#152 compact's invariant allows gaps" "'entries == highest' makes every legitimate removal read as damage"
else ok "#152 compact's invariant allows gaps (duplicated == 0 is the damage signal)"; fi

if grep -qE 'BOTH memory' CLAUDE.md; then
  no "#153 CLAUDE.md does not ask memory to hold a copy" "dual-write contradicts the channeling rule; memory holds a pointer at most"
else ok "#153 CLAUDE.md does not ask memory to hold a copy"; fi
has CLAUDE.md 'one-line pointer' && ok "#153 CLAUDE.md names memory's pointer role" \
  || no "#153 CLAUDE.md names memory's pointer role" "the reconciled rule is missing"

if grep -qE 'Project note exceeds [0-9]+ lines' INTENT.md; then
  no "#154 INTENT.md defers the line threshold to /close-day" "$(grep -nE 'Project note exceeds [0-9]+ lines' INTENT.md | cut -c1-100)"
else ok "#154 INTENT.md defers the line threshold to /close-day"; fi

H=plugins/aios/commands/housekeeping.md
if grep -qE 'roughly [0-9]+k tokens' "$H"; then
  no "#155 housekeeping restates no rungs cut-off" "$(grep -nE 'roughly [0-9]+k tokens' "$H" | cut -c1-100)"
else ok "#155 housekeeping restates no rungs cut-off"; fi
if grep -q 'CHEAP_IF_UNDER' hooks/context-rungs.py && has "$H" 'CHEAP_IF_UNDER'; then
  ok "#155 housekeeping names the hook constant that owns it"
else no "#155 housekeeping names the hook constant that owns it" "CHEAP_IF_UNDER must exist in the hook and be the pointer"; fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

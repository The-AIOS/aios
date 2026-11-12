#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /close-day notices when the operator's rhythm actually changed (#266)
#
# WHY THIS EXISTS
# vault-routine.md is restated (rewritten in place), so it has no staleness clock, and
# nothing replaced the clock: close-day only said to update it "when needed", with no way
# of noticing that it was.
#
# WHAT IT HOLDS (spec-reading): close-day.md names all six detectors, both cases that must
# not fire, silence when nothing fires, "still accurate" as a valid answer, and no script.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
F=plugins/aios/commands/close-day.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
sec=$(awk '/^\*\*Routine change check/{f=1} f&&/^\*\*Snapshot|^### /{if(f>1)exit} f{f++;print}' "$F")
[ -n "$sec" ] && ok "close-day has a routine change check" || no "no routine change check in close-day"
for d in "Adherence shift" "New calendar instrument" "Broken Monday anchor" "Gap" "Fan-in change" "Unused command"; do
  printf '%s' "$sec" | grep -F "**$d" >/dev/null && ok "detector: $d" || no "missing detector: $d"
done
printf '%s' "$sec" | grep -i 'vacation' >/dev/null && ok "a vacation week is not a broken anchor" || no "the vacation case is missing"
printf '%s' "$sec" | grep -i 'never fired' >/dev/null && ok "a command whose trigger never fired is not unused" || no "the never-fired case is missing"
printf '%s' "$sec" | grep -i 'say nothing' >/dev/null && ok "silent when nothing fires" || no "silence when nothing fires is not stated"
printf '%s' "$sec" | grep -iF 'still accurate' >/dev/null && ok "\"still accurate\" is a valid answer" || no "confirming without a rewrite is not allowed"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

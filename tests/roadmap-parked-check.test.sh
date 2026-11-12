#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A roadmap key is not minted for work INTENT.md still parks (#268)
#
# WHY THIS EXISTS
# /aios:today drops any carried item that matches INTENT.md's `## Explicitly NOT doing`,
# but nothing stopped a new roadmap key for parked work, so it sat on the roadmap and was
# never carried into a day.
#
# WHAT IT HOLDS (spec-reading, like tests/housekeeping-checks-that-cannot-fail.test.sh)
#   * the roadmap template's key system says to check the parked list before adding a key,
#     and that un-parking means removing the line from INTENT.md
#   * housekeeping's Explicitly NOT doing check also flags open keys in LIVE roadmaps whose
#     subject is still parked, proposes un-park or kill, skips copies under logs/, and
#     uses the same matching as /today
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
T=templates/aios/roadmap-template.md; H=plugins/aios/commands/housekeeping.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
ks=$(grep -F '**THE KEY SYSTEM.**' "$T")
printf '%s' "$ks" | grep -F 'Explicitly NOT doing' >/dev/null && ok "the key system checks the parked list first" || no "the key system does not check the parked list"
printf '%s' "$ks" | grep -i 'un-park' >/dev/null && ok "it says how un-parking is recorded" || no "un-parking is not explained"
b8=$(grep -F -- '- **Explicitly NOT doing**' "$H")
printf '%s' "$b8" | grep -i 'live roadmap' >/dev/null && ok "housekeeping checks live roadmaps' open keys" || no "housekeeping does not check roadmap keys against the parked list"
printf '%s' "$b8" | grep -i 'un-park or kill' >/dev/null && ok "it proposes un-park or kill" || no "no un-park-or-kill proposal"
printf '%s' "$b8" | grep -F 'logs/' >/dev/null && ok "it skips archived copies under logs/" || no "archived copies are not excluded"
printf '%s' "$b8" | grep -F 'INTENT.md parked items check' >/dev/null && ok "it uses /today's matching" || no "it does not point at /today's matching"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

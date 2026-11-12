#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:housekeeping --placement: a small, regular sweep for misplaced files (#300)
#
# WHAT IT HOLDS (spec-reading)
#   * housekeeping documents a --placement mode that runs only Buckets 21 and 25 plus the
#     context-reach checks, proposes and never moves on its own, and logs like a full run
#   * Bucket 21 gains the five context-reach checks: unreachable files, duplicates, context
#     weight, operator statements stranded in daily notes, loose files beside their subfolder
#   * a declined finding is not proposed again unless the file changed
#   * /today offers the sweep when the last housekeeping log is 14+ days old
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
H=plugins/aios/commands/housekeeping.md; D=plugins/aios/commands/today.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
mode=$(awk '/^\*\*`--placement` mode/{f=1} f{print} f&&/^$/{exit}' "$H")
[ -n "$mode" ] && ok "housekeeping documents --placement" || no "no --placement mode"
printf '%s' "$mode" | grep -F 'Bucket 21' >/dev/null && printf '%s' "$mode" | grep -F 'Bucket 25' >/dev/null && ok "it runs Buckets 21 and 25" || no "it does not name Buckets 21 and 25"
printf '%s' "$mode" | grep -i 'never moves' >/dev/null && ok "it never moves on its own" || no "propose-only is not stated"
b21=$(awk '/^#### Bucket 21/{f=1;next} f&&/^#### Bucket 22/{exit} f' "$H")
for c in "Unreachable files" "Duplicates" "Context weight" "Stranded operator statements" "Loose files"; do
  printf '%s' "$b21" | grep -F "**$c" >/dev/null && ok "Bucket 21 check: $c" || no "Bucket 21 is missing: $c"
done
printf '%s' "$b21" | grep -i 'declined' >/dev/null && ok "a declined finding is not proposed again" || no "declined findings can repeat"
grep -F '/aios:housekeeping --placement' "$D" | grep -F '14' >/dev/null && ok "/today offers the sweep after 14 days" || no "/today does not offer the sweep"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

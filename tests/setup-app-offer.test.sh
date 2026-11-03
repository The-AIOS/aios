#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# SETUP.md offers the AIOS App, once, to someone who arrives from a terminal
#
# WHY THIS EXISTS
# The site and its llms.txt lead with the App, but SETUP.md, the file a session
# actually follows, set up every terminal arrival the terminal way and never said the
# App existed as the simpler path. (#280)
#
# WHAT IT HOLDS (in the terminal branch of the execution sequence's step 1)
#   * the offer comes BEFORE any prerequisite check
#   * choosing the App gives the releases link and stops before cloning
#   * it is one offer, and it says the door stays open
#   * README and START-HERE describe the same first move
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
BR=$(awk '/\*\*Arrived through a terminal\*\*/{f=1} f&&/What the App does NOT do/{exit} f' SETUP.md)
printf '%s' "$BR" | head -1 | grep -q 'before any prerequisite check, make one offer' && ok "the terminal branch opens with the offer" || no "the terminal branch opens with the offer"
printf '%s' "$BR" | grep -q 'aios-app/releases/latest' && ok "choosing the App gives the latest release" || no "choosing the App gives the latest release"
printf '%s' "$BR" | grep -q 'stop here, before cloning' && ok "choosing the App stops before cloning" || no "choosing the App stops before cloning"
printf '%s' "$BR" | grep -q 'It is one offer' && ok "it is asked once" || no "it is asked once"
printf '%s' "$BR" | grep -q 'instead of cloning again' && ok "it says the App can be added later, reusing ~/aios" || no "it says the App can be added later"
printf '%s' "$BR" | grep -q 'recommend the App over the IDE' && ok "the terminal path still recommends the App as the surface" || no "the terminal path recommends the App as the surface"
grep -q 'Claude first offers the \[AIOS App\]' README.md && ok "README describes the same first move" || no "README describes the same first move"
grep -q 'Offers the AIOS App once' START-HERE.md && ok "START-HERE describes the same first move" || no "START-HERE describes the same first move"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

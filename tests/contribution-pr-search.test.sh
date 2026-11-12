#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A session searches and picks the repo before it opens a PR, not only an issue (#259)
#
# WHAT IT HOLDS
#   * aios-feedback's route 3 (a fix they built) runs Step 2 (route) and Step 3
#     (de-duplicate, including PRs and the work in flight) before handing off
#   * CONTRIBUTING's "If you are a Claude session" section says the same, pointing at
#     § Before you open anything and § Which repo?
#   * opening the PR still waits for the operator's yes
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
A=agents/aios/personal/aios-feedback.md; C=CONTRIBUTING.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
r3=$(grep -E '^3\. \*\*A fix they built' "$A")
printf '%s' "$r3" | grep -F 'Step 2' >/dev/null && printf '%s' "$r3" | grep -F 'Step 3' >/dev/null && ok "route 3 runs the route and de-duplicate steps first" || no "route 3 hands off without searching or routing"
printf '%s' "$r3" | grep -i 'in-progress\|in flight' >/dev/null && ok "a match in flight means joining it" || no "route 3 does not send a match in flight to the existing work"
sess=$(awk '/^### If you are a Claude session doing this/{f=1;next} f&&/^---/{exit} f' "$C")
printf '%s' "$sess" | grep -F 'Before you open anything' >/dev/null && printf '%s' "$sess" | grep -F 'Which repo?' >/dev/null && ok "CONTRIBUTING's session section searches and routes before the PR" || no "CONTRIBUTING's session section does not say to search and route"
printf '%s' "$sess" | grep -F 'gh pr create' >/dev/null && ok "opening the PR still needs the operator's yes" || no "the confirmation before gh pr create is gone"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

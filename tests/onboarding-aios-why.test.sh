#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# onboarding-aios answers "what is all this for?", not only "where am I" (#270)
#
# WHAT IT HOLDS
#   * the trigger list carries the question in English and Spanish
#   * a named section, placed after Step 7, says how to answer: one paragraph from the
#     operator's own vault, pointing at CLAUDE.md § The Belief, inventing nothing on an
#     empty vault
#   * a question about the operator's OWN purpose is handed to finding-your-why
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
F=agents/aios/personal/onboarding-aios.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
grep -F '"what is all this for?"' "$F" >/dev/null && ok "English trigger" || no "no English trigger for the question"
grep -F '"¿para qué sirve todo esto?"' "$F" >/dev/null && ok "Spanish trigger" || no "no Spanish trigger for the question"
s7=$(grep -n '^### Step 7' "$F" | cut -d: -f1); sec=$(grep -n '^### When they ask what it.s for' "$F" | cut -d: -f1)
[ -n "$sec" ] && [ -n "$s7" ] && [ "$sec" -gt "$s7" ] && ok "a named section after Step 7" || no "no 'When they ask what it's for' section after Step 7"
body=$(awk '/^### When they ask what it.s for/{f=1;next} f&&/^##/{exit} f' "$F")
printf '%s' "$body" | grep -F '§ The Belief' >/dev/null && ok "it points at CLAUDE.md § The Belief" || no "no pointer to § The Belief"
printf '%s' "$body" | grep -i 'invent' >/dev/null && ok "on an empty vault it invents nothing" || no "the empty-vault rule is missing"
printf '%s' "$body" | grep -F 'finding-your-why' >/dev/null && ok "the operator's own purpose goes to finding-your-why" || no "no hand-off to finding-your-why"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

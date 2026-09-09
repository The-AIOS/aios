#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Step 2.7 must give exactly ONE strategy per dual-owned file, and must not
# carry prose describing an approach that was replaced.
#
# WHY. Found by running /aios:update as the command rather than by hand. An edit
# on 2026-09-08 replaced the mcps/_index.md handling: a section-scoped splice
# was swapped for keep-local-and-report, because the splice silently dropped
# operator additions written outside `## Bundling candidates`. The edit was
# anchored on the CODE FENCE, so it replaced the implementation and left the
# sentence that introduced it -- and that sentence came FIRST. Step 2.7 then
# held two contradictory rules for one file, with the data-losing one on top,
# plus a sentence duplicated onto itself.
#
# This is not a typo class. A session reads the spec top-down and acts on the
# first instruction that matches, so a stale description is not dead text --
# it is the rule that runs. Hand-executing the command cannot catch it, because
# a hand-run follows intent; only reading the spec as written does.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
U=plugins/aios/commands/update.md
[ -f "$U" ] || { echo "::error::$U missing"; exit 1; }

# Step 2.7 only — a rule stated elsewhere (the Tier-1 entry) is a pointer, not a strategy.
SEC=$(awk '/^2\.7\./{f=1} f&&/^3\. \*\*Overwrite\*\*/{exit} f' "$U")
[ -n "$SEC" ] && ok "Step 2.7 extracted ($(printf '%s' "$SEC" | wc -l | tr -d ' ') lines)" \
  || { no "could not extract Step 2.7" "the anchors moved; fix the extraction before trusting the rest"; echo; echo "-- $PASS passed, $FAIL failed --"; exit 1; }

echo "-- 1. one strategy per dual-owned file --"
# Each dual-owned file must be introduced exactly once in this section.
for f in 'mcps/_index.md'; do
  n=$(printf '%s' "$SEC" | grep -cF "For **\`$f\`**")
  [ "$n" -eq 1 ] && ok "$f: exactly one strategy stated" \
    || no "$f: $n strategy statements in Step 2.7" "a session acts on the FIRST match, so a second rule is not redundancy -- it is the rule that runs"
done

echo "-- 2. the replaced approach leaves no prose behind --"
# The splice was abandoned because it drops additions outside one section. Any
# surviving instruction to carry a single section back is the data-losing rule.
printf '%s' "$SEC" | grep -qiE "carry the operator's \`## Bundling candidates\` body" \
  && no "the abandoned section-splice is still instructed" "it silently drops operator additions written in any other section -- measured on a live vault" \
  || ok "no instruction to splice a single section"
# keep-local-and-report must be the one that IS stated
printf '%s' "$SEC" | grep -qF 'KEEP LOCAL AND REPORT' \
  && ok "keep-local-and-report is the stated rule" \
  || no "keep-local-and-report is missing" "without it a session falls back to the plain overwrite, which loses the operator's registry rows"

echo "-- 3. no sentence duplicated onto itself --"
# The `X.   X.` shape is what a replace-by-anchor produces when the new text
# ends with the same sentence the anchor preserved.
dupes=$(printf '%s\n' "$SEC" | grep -oE '([A-Z][^.]{15,120}\.)[[:space:]]+\1' | head -3)
[ -z "$dupes" ] && ok "no self-duplicated sentence in Step 2.7" \
  || { no "a sentence is duplicated onto itself" "the tell of an anchored replace whose new text re-stated the anchor"; printf '%s\n' "$dupes" | sed 's/^/       /'; }

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

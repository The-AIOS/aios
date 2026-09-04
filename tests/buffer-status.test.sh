#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The observation buffer's state must be MEASURED, not judged
#
# session-insights.md was the last compounding surface governed entirely by
# prose. Its cap, clock and disposition all required reading the whole file —
# ~22,000 tokens on one reporting vault, ~12,800 on another — so all three were
# executed by judgment and all three drifted. Reported with machine-derived
# figures (issue #62) and reproduced independently: 14/10 Emerging, median entry
# ~1,857 chars, ~86% of entries system-class, on a second vault that had never
# seen the report.
#
# TWO REGRESSIONS THIS PINS, both found by running the tool against a live vault
# rather than against its own fixtures:
#
#   1. A false "missing route" on 19 of 19 entries. All nineteen named a target
#      in the pre-contract `**Route to:** [[x]]` shape; the parser accepted only
#      the new backtick field. The check was measuring its own format preference
#      rather than the property it claimed to check — and a false finding at that
#      volume is exactly how a linter teaches people to ignore it.
#   2. A wrong-cause message. With nothing classified, it announced "no method
#      entries, so review the behavioural ones" — asserting a fact it had not
#      measured, and directing the work at the one class that was NOT the cause.
#      Same shape as the credentials-vs-list-ID diagnosis fixed earlier.
#
# Every assertion below mutates a fixture so the defect is genuinely present and
# requires the red line. The parse-failure check carries a CONTROL: a linter that
# reports a healthy zero because its regex missed is the defect class this file
# exists to reduce, so "cannot measure" must be loud and non-zero.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
B=hooks/buffer-status.py

mk(){ # mk <file> <n-emerging-method> <n-emerging-behavioural> [extra]
  { echo "# Session Insights"; echo; echo "## Emerging"; echo
    i=0; while [ "$i" -lt "$2" ]; do i=$((i+1))
      echo "### method finding $i"
      echo '`class: method` · `first-seen: 2026-09-01` · `route: antifragile.md`'
      echo "body"; echo; done
    i=0; while [ "$i" -lt "$3" ]; do i=$((i+1))
      echo "### behavioural finding $i"
      echo '`class: behavioural` · `first-seen: 2026-09-01` · `route: patterns.md`'
      echo "body"; echo; done
    printf '%s\n' "${4:-}"
    echo; echo "## Reinforced"; echo
  } > "$1"; }

echo "── counts are counts ──"
mk "$T/a.md" 3 2
out=$(python3 "$B" "$T/a.md" --json); rc=$?
e=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["emerging"])')
m=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["method_awaiting_disposition"])')
[ "$e" = "5" ] && ok "counted 5 Emerging" || no "counted $e Emerging, expected 5"
[ "$m" = "3" ] && ok "counted 3 method awaiting disposition" || no "counted $m method, expected 3"
[ "$rc" = "1" ] && ok "parked method entries → exit 1 (action needed)" || no "exit $rc, expected 1"

echo "── a clean buffer is exit 0, and CAN be reached ──"
mk "$T/clean.md" 0 2
out=$(python3 "$B" "$T/clean.md"); rc=$?
[ "$rc" = "0" ] && ok "within contract → exit 0" || no "exit $rc on a clean buffer" "$out"
case "$out" in *"Within contract"*) ok "says so in words" ;; *) no "clean buffer did not report 'Within contract'" ;; esac

echo "── over cap is detected, and names the RIGHT cause ──"
mk "$T/over.md" 12 0
out=$(python3 "$B" "$T/over.md")
case "$out" in *"over by 2"*) ok "over-cap delta is correct (12/10)" ;; *) no "over-cap delta wrong" "$out" ;; esac
case "$out" in *"class:method"*|*"method"*) ok "names method entries as the cause" ;; *) no "over-cap message never mentions method entries" ;; esac

echo "── REGRESSION: the wrong-cause message ──"
# Nothing classified: the tool must NOT claim there are no method entries.
{ echo "## Emerging"; i=0; while [ "$i" -lt 12 ]; do i=$((i+1)); echo "### old entry $i"; echo "body"; echo; done; } > "$T/uncl.md"
out=$(python3 "$B" "$T/uncl.md")
case "$out" in
  *"no method entries"*) no "asserts 'no method entries' while NOTHING is classified" "a cause it never measured" ;;
  *"NOTHING is classified"*) ok "unclassified buffer is reported as unclassified, not as behavioural" ;;
  *) no "unclassified over-cap produced no recognisable diagnosis" "$out" ;;
esac

echo "── REGRESSION: the pre-contract **Route to:** form counts as a route ──"
{ echo "## Emerging"; echo "### legacy entry"; echo "body"; echo '**Route to:** [[patterns]] (some reason)'; } > "$T/legacy.md"
out=$(python3 "$B" "$T/legacy.md" --json)
mr=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["missing_route"])')
[ "$mr" = "0" ] && ok "**Route to:** counts — 0 missing" || no "legacy route form reported as missing ($mr)" "the 19-of-19 false positive"
# Control: a genuinely route-less entry must still be caught, or the check above is vacuous.
{ echo "## Emerging"; echo "### no destination"; echo "body with no target at all"; } > "$T/noroute.md"
mr2=$(python3 "$B" "$T/noroute.md" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["missing_route"])')
[ "$mr2" = "1" ] && ok "control: a truly route-less entry IS still caught" || no "CONTROL FAILED — missing_route=$mr2; the check above proved nothing"

echo "── an unmeasurable file is LOUD, never a healthy zero ──"
printf 'just some prose with no sections at all\n' > "$T/bad.md"
out=$(python3 "$B" "$T/bad.md" 2>&1); rc=$?
[ "$rc" = "2" ] && ok "unparseable → exit 2" || no "unparseable → exit $rc, expected 2" "$out"
case "$out" in *"cannot measure"*) ok "says it cannot measure" ;; *) no "no 'cannot measure' in the error" "$out" ;; esac
: > "$T/empty.md"
rc2=$(python3 "$B" "$T/empty.md" >/dev/null 2>&1; echo $?)
[ "$rc2" = "2" ] && ok "empty file → exit 2, not 'zero entries, healthy'" || no "empty file → exit $rc2"
rc3=$(python3 "$B" "$T/does-not-exist.md" >/dev/null 2>&1; echo $?)
[ "$rc3" = "2" ] && ok "missing file → exit 2" || no "missing file → exit $rc3"
# Control: a file with sections but no Emerging/Reinforced must ALSO fail loudly.
printf '## Something Else\n\n### x\nbody\n' > "$T/wrongsec.md"
rc4=$(python3 "$B" "$T/wrongsec.md" >/dev/null 2>&1; echo $?)
[ "$rc4" = "2" ] && ok "sections present but neither stage named → exit 2" || no "wrong-section file → exit $rc4, expected 2"

echo "── an unrecognised class is surfaced ──"
{ echo "## Emerging"; echo "### weird"; echo '`class: sytem` · `route: x.md`'; echo body; } > "$T/badclass.md"
case "$(python3 "$B" "$T/badclass.md")" in
  *"unrecognised class"*) ok "typo'd class is flagged (not silently ignored)" ;;
  *) no "an unrecognised class passed silently" "a typo would make an entry invisible to disposition" ;;
esac

echo "── it never writes ──"
mk "$T/ro.md" 4 1
before=$(shasum -a 256 < "$T/ro.md")
python3 "$B" "$T/ro.md" >/dev/null 2>&1
[ "$(shasum -a 256 < "$T/ro.md")" = "$before" ] && ok "the buffer is byte-identical after a run" || no "buffer-status MODIFIED the file"

echo "── the doctrine it enforces is actually written down ──"
grep -qF 'class: behavioural' CLAUDE.md && ok "CLAUDE.md carries the entry contract" || no "CLAUDE.md never shows the class line"
grep -qF 'Most method findings fold or drop' CLAUDE.md && ok "CLAUDE.md states the pressure valve" || no "the fold/drop valve is undocumented"
for f in plugins/aios/commands/close-session.md plugins/aios/commands/close-day.md; do
  grep -qF 'class: method' "$f" || grep -qF 'class:method' "$f" \
    && ok "$(basename "$f") disposes by class" || no "$(basename "$f") never mentions the method class"
done

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]

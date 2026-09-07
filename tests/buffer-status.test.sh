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

echo "── REGRESSION: a MIXED buffer does not claim everything is classified ──"
# Three states need three messages. The first version had two, so a buffer with
# SOME entries classified fell through to the all-classified branch and asserted
# "every entry is classified" one line above reporting N unclassified. A report
# that contradicts itself is the same assert-a-cause-you-did-not-measure shape
# this whole file exists to reduce — caught by running it on a real buffer.
{ echo "## Emerging"
  i=0; while [ "$i" -lt 11 ]; do i=$((i+1)); echo "### old $i"; echo "body"; echo; done
  echo "### classified one"; echo '`class: behavioural` · `route: patterns.md`'; echo "body"; } > "$T/mixed.md"
out=$(python3 "$B" "$T/mixed.md")
case "$out" in
  *"Every entry is classified"*) no "claims every entry is classified while some are not" "self-contradicting report" ;;
  *"still unclassified — the cause cannot be attributed"*) ok "mixed buffer refuses to attribute the cause" ;;
  *) no "mixed buffer produced no recognisable diagnosis" "$(printf '%s' "$out" | tail -2)" ;;
esac
# Control: the all-classified branch must STILL be reachable, or the fix above
# just made one message unreachable instead of correct.
{ echo "## Emerging"
  i=0; while [ "$i" -lt 12 ]; do i=$((i+1)); echo "### b $i"; echo '`class: behavioural` · `route: patterns.md`'; echo "body"; echo; done; } > "$T/allb.md"
case "$(python3 "$B" "$T/allb.md")" in
  *"Every entry is classified"*) ok "control: the all-classified branch is still reachable" ;;
  *) no "CONTROL FAILED — the all-classified message is now unreachable" ;;
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

echo '-- entries may be BULLETS, not only ### headings --'
# `route-insight.py` — the tool that EXCISES entries from this same file — resolves
# BOTH styles and documents why. This parser counted only `### `, so the framework's
# two readers of session-insights.md disagreed about what an entry is, and this one
# lost silently: a live vault holding 5 Reinforced anchors and 9 Emerging entries
# reported `0/5`, `0/10`, `~0 tokens`, "Within contract", exit 0. Every guard above
# passes on that file (non-empty, `## ` sections present, both stages named), which
# is why nothing caught it.
{ echo "# Session Insights"; echo; echo "## Emerging"; echo
  echo "- **(2026-09-01)** first bullet entry"
  echo '  `class: method` · `first-seen: 2026-09-01` · `route: antifragile.md`'
  echo "  - an indented facet, which is BODY and must not count as an entry"
  echo "  > a blockquote facet, likewise"
  echo "- **(2026-09-02)** second bullet entry"
  echo '  `class: behavioural` · `first-seen: 2026-09-02` · `route: patterns.md`'
  echo "unindented continuation prose that belongs to the entry above"
  echo
  echo "<!-- ROUTED 2026-08-01: a tombstone is furniture, never an entry. -->"
  echo; echo "## Reinforced"; echo
  echo "- **An anchor.** Body."
  echo '  `class: behavioural` · `first-seen: 2026-06-12` · `route: patterns.md`'
} > "$T/bul.md"
out=$(python3 "$B" "$T/bul.md" --json); rc=$?
be=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["emerging"])')
br=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["reinforced"])')
bm=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["method_awaiting_disposition"])')
bu=$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["unclassified"])')
[ "$be" = "2" ] && ok "counted 2 bullet Emerging entries" || no "counted $be bullet Emerging, expected 2" "indented facets or the tombstone were counted as entries"
[ "$br" = "1" ] && ok "counted 1 bullet Reinforced entry" || no "counted $br bullet Reinforced, expected 1"
[ "$bm" = "1" ] && ok "class: fields parse inside a bullet entry" || no "method count $bm, expected 1" "the class line sits on the bullet's indented continuation"
[ "$bu" = "0" ] && ok "no bullet entry is misread as unclassified" || no "$bu unclassified, expected 0"
# Control: the heading style must still work, or the change above just swapped one
# blind spot for another.
mk "$T/hd.md" 2 1
he=$(python3 "$B" "$T/hd.md" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["emerging"])')
[ "$he" = "3" ] && ok "control: heading-style entries still counted" || no "CONTROL FAILED — heading style now counts $he, expected 3"
# Control: a stage holding ONLY tombstones is legitimately empty, not a parse failure.
{ echo "## Reinforced"; echo; echo "## Emerging"; echo
  echo "<!-- ROUTED 2026-08-24: graduated to patterns.md; removed from buffer. -->"
} > "$T/tomb.md"
rct=$(python3 "$B" "$T/tomb.md" >/dev/null 2>&1; echo $?)
[ "$rct" = "0" ] && ok "control: a genuinely empty buffer still measures clean" || no "CONTROL FAILED — empty-but-valid buffer → exit $rct, expected 0"
# A shape matching NEITHER style must refuse, not report zero.
{ echo "## Emerging"; echo; echo "some prose that is neither a heading nor a top-level bullet,"
  echo "long enough to be unmistakably substantive content in this stage."; } > "$T/neither.md"
rcn=$(python3 "$B" "$T/neither.md" >/dev/null 2>&1; echo $?)
[ "$rcn" = "2" ] && ok "an unknown entry shape refuses (exit 2), never reports 0" || no "unknown shape → exit $rcn, expected 2"

echo "── an unrecognised class is surfaced ──"
{ echo "## Emerging"; echo "### weird"; echo '`class: sytem` · `route: x.md`'; echo body; } > "$T/badclass.md"
case "$(python3 "$B" "$T/badclass.md")" in
  *"unrecognised class"*) ok "typo'd class is flagged (not silently ignored)" ;;
  *) no "an unrecognised class passed silently" "a typo would make an entry invisible to disposition" ;;
esac

echo "── the file's cost is reported, not only the entries' ──"
# Furniture: tombstones the entry parser never sees but every session pays to load.
mk "$T/furn.md" 2 2
i=0; while [ "$i" -lt 40 ]; do i=$((i+1))
  echo "<!-- ROUTED 2026-01-01 → [[x]]: «tombstone $i — a routed entry whose body already lives in its target file, kept here only as a receipt» -->" >> "$T/furn.md"
done
out=$(python3 "$B" "$T/furn.md" --json)
gt=$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["approx_tokens_file"] > d["approx_tokens_entries"])')
[ "$gt" = "True" ] && ok "file cost is reported above entry cost when furniture is present" || no "file cost not above entry cost" "$out"
case "$(python3 "$B" "$T/furn.md")" in
  *"NOT entries"*) ok "the report names the share that is not entries" ;;
  *) no "furniture-heavy buffer printed no warning" "the caps read fine while most of the file was tombstones" ;;
esac
mk "$T/lean.md" 2 2
case "$(python3 "$B" "$T/lean.md")" in
  *"NOT entries"*) no "CONTROL FAILED — a lean buffer triggered the furniture warning" ;;
  *) ok "control: a lean buffer prints no furniture warning" ;;
esac
old=$(printf '%s' "$out" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["approx_tokens_to_read_in_full"] == d["approx_tokens_entries"])')
[ "$old" = "True" ] && ok "the original JSON key keeps its meaning (entries)" || no "approx_tokens_to_read_in_full changed meaning" "a consumer reading the old key would silently get a different number"

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

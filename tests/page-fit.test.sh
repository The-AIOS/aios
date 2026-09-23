#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hooks/page-fit.py — a report's page fit is measured, and an unmeasured fit is
# never reported as one
#
# WHY
# /weekly-learnings said "fit exactly 3 pages" and nothing measured a page (#156).
# HTML has no page, so an overflowing `.page` box reads fine on screen and only
# splits across extra sheets at print time — measured on a real report: two of
# three pages over, six sheets printed. The hook renders and reads box heights.
#
# Two failure shapes this pins:
#   1. A blind instrument. Desktop Chrome can print the DOM and then never exit,
#      so a wait-for-exit timeout reports "did not complete" on a render that
#      had succeeded. The overflow fixture is the positive control: if the hook
#      cannot see 2000+ px on a stuffed page, its "fits" means nothing.
#   2. A silent pass. No browser, no `.page`, no file → exit 2 naming what was
#      not measured, never exit 0.
#
# The verdict logic runs everywhere; the render cases need Chrome/Chromium and
# are REQUIRED under CI (a skipped positive control is not a pass).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
PY="${PYBIN:-python3}"
H=hooks/page-fit.py
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "-- verdict logic (no browser) --"
OUT="$("$PY" - "$H" 2>/dev/null <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pf", sys.argv[1]); pf = importlib.util.module_from_spec(spec); spec.loader.exec_module(pf)
def check(label, cond): print(("OK" if cond else "NO") + "\t" + label)
c, _ = pf.verdict([1122.5, 1122.0, 1123.0], expect=3); check("sub-pixel A4 heights fit", c == 0)
c, l = pf.verdict([1122, 1213, 1122], expect=3); check("an overflowing page fails and is named with px", c == 1 and "page 2" in l[1] and "OVER by 90" in l[1])
c, l = pf.verdict([1122, 1122], expect=3); check("a wrong page count fails", c == 1 and any("expected 3" in x for x in l))
c, _ = pf.verdict([1122, 1122]); check("no --expect → count is not judged", c == 0)
pf.find_browser = lambda: None
check("no browser → exit 2, never a pass", pf.main([sys.argv[1]]) == 2)
check("missing file → exit 2", pf.main(["/nonexistent/report.html"]) == 2)
PYEOF
)"; RC=$?
[ "$RC" -eq 0 ] || no "verdict probe ran" "python exited $RC"
while IFS=$'\t' read -r v label; do [ -z "$v" ] && continue; [ "$v" = OK ] && ok "$label" || no "$label"; done <<< "$OUT"

echo "-- render (needs Chrome/Chromium) --"
page(){ printf '<div class="page"><div class="page-content">%s</div></div>' "$1"; }
CSS='<style>@page{size:A4;margin:0}body{margin:0}.page{width:210mm;min-height:297mm;padding:22mm 25mm 12mm 25mm;box-sizing:border-box;page-break-after:always;display:flex;flex-direction:column}.page-content{flex:1}</style>'
LONG="$(printf '<p>overflow line to push past one sheet</p>%.0s' $(seq 1 120))"
printf '<html><head>%s</head><body>%s%s</body></html>' "$CSS" "$(page a)" "$(page b)" > "$T/fit.html"
printf '<html><head>%s</head><body>%s%s</body></html>' "$CSS" "$(page a)" "$(page "$LONG")" > "$T/over.html"
printf '<html><body><p>no pages here</p></body></html>' > "$T/none.html"

HAVE=$("$PY" -c "import importlib.util,sys;s=importlib.util.spec_from_file_location('pf','$H');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(m.find_browser() or '')")
if [ -z "$HAVE" ]; then
  if [ -n "${CI:-}" ]; then no "a browser is available under CI" "the positive control cannot run — install Chrome/Chromium on this runner"
  else echo "  - no Chrome/Chromium here: render cases skipped (required under CI)"; fi
else
  "$PY" "$H" --expect 2 "$T/fit.html" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "two A4 pages fit (exit 0)" || no "two A4 pages fit" "exit $rc"
  o="$("$PY" "$H" --expect 2 "$T/over.html" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && printf '%s' "$o" | grep -q 'page 2: .*OVER by'; then ok "positive control: stuffed page 2 is caught and named (exit 1)"
  else no "positive control: stuffed page 2 is caught" "exit $rc: $(printf '%s' "$o" | tr '\n' ' ' | cut -c1-160)"; fi
  "$PY" "$H" "$T/none.html" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && ok "no .page boxes → exit 2 (not measured)" || no "no .page boxes → exit 2" "exit $rc"
fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

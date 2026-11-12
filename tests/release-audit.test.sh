#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Two independent audits gate a release, and a missing one never reads as a pass (#267 b)
#
# Stand-ins replace both reviewers (AIOS_AUDIT_OUTSIDE, AIOS_AUDIT_CLAUDE), so this runs
# offline and checks what the script does with their answers, not what a model says.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S=.github/scripts/release-audit.py
mk(){ printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/%s.args"\ncat >/dev/null\n%s\n' "$T" "$1" "$2" > "$T/$1"; chmod +x "$T/$1"; }
run(){ AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $S run --base HEAD~1 --head HEAD --out "$T/r" >"$T/log" 2>&1; }

mk out 'echo "fine"; echo "VERDICT: PASS"'; mk cl 'echo "fine"; echo "VERDICT: PASS"'
run; rc=$?
[ $rc -eq 0 ] && ok "both PASS → the release may be cut" || no "both PASS but blocked" "$(cat "$T/log")"
[ -f "$T/r/outside.md" ] && [ -f "$T/r/claude.md" ] && [ -f "$T/r/brief.md" ] && ok "both reports and the brief are saved" || no "reports missing"
grep -F -- '--tools  --setting-sources user,project --strict-mcp-config --permission-mode default' "$T/cl.args" >/dev/null \
  && ok "the Claude audit runs with no tools, no local settings and no MCP servers" || no "the Claude audit is not contained" "$(cat "$T/cl.args")"
grep -F 'who gets hurt' "$T/r/brief.md" >/dev/null && grep -F -- '--- DIFF ---' "$T/r/brief.md" >/dev/null && ok "the brief asks who gets hurt and carries the diff" || no "the brief is wrong"

rm -rf "$T/r"; mk cl 'echo "VERDICT: BLOCK"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'claude audit says BLOCK' "$T/log" >/dev/null && ok "one BLOCK blocks the release" || no "a BLOCK was not honoured" "$(cat "$T/log")"

rm -rf "$T/r"; mk out 'echo "no key: create ~/.config/aios-secrets/openrouter.env" >&2; exit 3'; mk cl 'echo "VERDICT: PASS"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'NOT RUN' "$T/r/outside.md" >/dev/null && ok "no outside key → the report says NOT RUN and the release is blocked" || no "a missing outside audit passed" "$(cat "$T/log")"

rm -rf "$T/r"; mk out 'echo "looks ok"'; mk cl 'echo "VERDICT: PASS"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'no VERDICT line' "$T/log" >/dev/null && ok "an answer with no VERDICT line blocks" || no "a report with no verdict passed" "$(cat "$T/log")"

rm -rf "$T/r"; $PYBIN $S check --out "$T/r" >"$T/log" 2>&1; rc=$?
[ $rc -ne 0 ] && grep -F 'no outside audit report' "$T/log" >/dev/null && ok "check with no reports at all blocks" || no "check passed with no reports"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

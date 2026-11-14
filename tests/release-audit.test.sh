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
# A small repo of its own, so the test never depends on this checkout's history (CI clones
# shallow) or on its origin (a fork's would differ): the script, a few commits, and an
# origin that names the public framework repo.
F="$T/fixture"; mkdir -p "$F/.github/scripts" "$F/docs"; cp .github/scripts/release-audit.py "$F/.github/scripts/"
g(){ git -C "$F" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g init -q; g remote add origin https://github.com/The-AIOS/aios.git; g add -A; g commit -qm base
for i in 1 2 3; do for j in 1 2 3; do seq 1 400 | sed "s/^/line $i.$j /" > "$F/docs/f$i$j.txt"; done; g add -A; g commit -qm "change $i"; done
S="$F/.github/scripts/release-audit.py"
mk(){ printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/%s.args"\npwd >> "%s/%s.cwd"\nfor a in "$@"; do case "$a" in *settings.json) cat "$a" >> "%s/%s.settings";; esac; done\ncat >/dev/null\n%s\n' "$T" "$1" "$T" "$1" "$T" "$1" "$2" > "$T/$1"; chmod +x "$T/$1"; }
run(){ AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $S run --base HEAD~1 --head HEAD --out "$T/r" >"$T/log" 2>&1; }

mk out 'echo "fine"; echo "VERDICT: PASS"'; mk cl 'echo "fine"; echo "VERDICT: PASS"'
run; rc=$?
[ $rc -eq 0 ] && ok "both PASS → the release may be cut" || no "both PASS but blocked" "$(cat "$T/log")"
[ -f "$T/r/outside.md" ] && [ -f "$T/r/claude.md" ] && [ -f "$T/r/brief.md" ] && ok "both reports and the brief are saved" || no "reports missing"
grep -E -- '--tools  --setting-sources user --settings [^ ]+settings.json --strict-mcp-config --permission-mode default' "$T/cl.args" >/dev/null \
  && ok "the Claude audit runs with no tools, no MCP servers and no project settings layer" || no "the Claude audit is not contained" "$(cat "$T/cl.args")"
grep -F '"disableAllHooks": true' "$T/cl.settings" >/dev/null && ok "every hook is disabled for the Claude audit" || no "hooks are not disabled" "$(cat "$T/cl.settings" 2>&1)"
case "$(head -1 "$T/cl.cwd")" in "$PWD"*) no "the Claude audit runs inside the repo" "$(head -1 "$T/cl.cwd")";; *release-audit-*) ok "the Claude audit runs from an empty temporary folder";; *) no "unexpected working folder" "$(head -1 "$T/cl.cwd")";; esac
grep -F 'who gets hurt' "$T/r/brief.md" >/dev/null && grep -F -- '--- DIFF ---' "$T/r/brief.md" >/dev/null && ok "the brief asks who gets hurt and carries the diff" || no "the brief is wrong"

rm -rf "$T/r"; mk cl 'echo "VERDICT: BLOCK"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'claude audit says BLOCK' "$T/log" >/dev/null && ok "one BLOCK blocks the release" || no "a BLOCK was not honoured" "$(cat "$T/log")"

rm -rf "$T/r"; mk out 'echo "no key: create ~/.config/aios-secrets/openrouter.env" >&2; exit 3'; mk cl 'echo "VERDICT: PASS"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'NOT RUN' "$T/r/outside.md" >/dev/null && ok "no outside key → the report says NOT RUN and the release is blocked" || no "a missing outside audit passed" "$(cat "$T/log")"

rm -rf "$T/r"; mk out 'echo "looks ok"'; mk cl 'echo "VERDICT: PASS"'; run; rc=$?
[ $rc -ne 0 ] && grep -F 'did not run or gave no verdict' "$T/r/outside.md" >/dev/null && ok "an answer with no VERDICT line blocks, and the report says why" || no "a report with no verdict passed" "$(cat "$T/log")"

rm -rf "$T/r"; : > "$T/cl.args"; mk out 'echo "VERDICT: PASS"'; mk cl 'echo "VERDICT: PASS"'
AIOS_AUDIT_MAX_DIFF=3000 AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $S run --base HEAD~3 --head HEAD --out "$T/r" >"$T/log" 2>&1; rc=$?
n=$(ls "$T/r"/brief-*.md 2>/dev/null | wc -l | tr -d ' ')
[ $rc -eq 0 ] && [ "$n" -gt 1 ] && ok "a diff over the limit is split into $n parts, each reviewed, never truncated" || no "a large diff was not split" "rc=$rc parts=$n $(cat "$T/log")"
rm -rf "$T/r"; mk cl 'n=$(cat "$0.count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$0.count"; [ $n -eq 2 ] && echo "VERDICT: BLOCK" || echo "VERDICT: PASS"'
AIOS_AUDIT_MAX_DIFF=3000 AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $S run --base HEAD~3 --head HEAD --out "$T/r" >"$T/log" 2>&1; rc=$?
[ $rc -ne 0 ] && grep -F 'claude audit says BLOCK' "$T/log" >/dev/null && ok "one blocking part blocks the whole release" || no "a BLOCK in one part was lost" "$(cat "$T/log")"

git clone -q "$F" "$T/vaultlike" 2>/dev/null; git -C "$T/vaultlike" remote set-url origin https://github.com/The-AIOS/aios.git; touch "$T/vaultlike/.aios-update"
AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN "$T/vaultlike/.github/scripts/release-audit.py" run --base HEAD~1 --head HEAD --out "$T/rv" >"$T/log" 2>&1; rc=$?
[ $rc -ne 0 ] && grep -F '.aios-update' "$T/log" >/dev/null && [ ! -e "$T/rv/outside.md" ] && ok "it refuses to run in an operator's vault, before sending anything" || no "it ran in a vault" "$(cat "$T/log")"
rm -f "$T/vaultlike/.aios-update"; git -C "$T/vaultlike" remote set-url origin https://example.com/someone/fork.git
AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN "$T/vaultlike/.github/scripts/release-audit.py" run --base HEAD~1 --head HEAD --out "$T/rv" >"$T/log" 2>&1; rc=$?
[ $rc -ne 0 ] && grep -F 'not The-AIOS/aios' "$T/log" >/dev/null && ok "it refuses any repo whose origin is not The-AIOS/aios" || no "it ran outside the public repo" "$(cat "$T/log")"

rm -rf "$T/r"; $PYBIN $S check --out "$T/r" >"$T/log" 2>&1; rc=$?
[ $rc -ne 0 ] && grep -F 'no outside audit report' "$T/log" >/dev/null && ok "check with no reports at all blocks" || no "check passed with no reports"
# Vendored folders proven against their upstream: docs left out, scripts still read, scope named.
V="$T/vend"; mkdir -p "$V/.github/scripts" "$V/skills/up"; cp .github/scripts/release-audit.py "$V/.github/scripts/"
gv(){ git -C "$V" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
gv init -q; gv remote add origin https://github.com/The-AIOS/aios.git
printf 'repo=x\nhash=abc\n' > "$V/skills/up/.upstream-sync"; echo old > "$V/skills/up/guide.md"; gv add -A; gv commit -qm base
echo "UPSTREAM DOC CHANGE" > "$V/skills/up/guide.md"; printf 'print("UPSTREAM SCRIPT")\n' > "$V/skills/up/run.py"; echo "OUR CODE" > "$V/ours.md"
gv add -A; gv commit -qm release
VS="$V/.github/scripts/release-audit.py"
mk out 'echo "VERDICT: PASS"'; mk cl 'echo "VERDICT: PASS"'
AIOS_AUDIT_PIN_CHECK=true AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $VS run --base HEAD~1 --head HEAD --out "$T/rp" >"$T/log" 2>&1; rc=$?
B="$T/rp/brief.md"
[ $rc -eq 0 ] && grep -qF 'OUR CODE' "$B" && ! grep -qF 'UPSTREAM DOC CHANGE' "$B" && ok "a proven vendored folder's docs are left out; our own code is sent" || no "proven docs were sent or our code was not" "$(cat "$T/log")"
grep -qF 'UPSTREAM SCRIPT' "$B" && ok "a script inside a proven vendored folder is still audited" || no "a vendored script was left out"
grep -qF 'skills/up: proven byte for byte' "$B" && grep -qF 'skills/up: proven' "$T/rp/outside.md" && grep -qF 'skills/up/guide.md' "$T/rp/left-out.txt" \
  && ok "the brief, the reports and left-out.txt name what was left out" || no "the scope is not named"
AIOS_AUDIT_PIN_CHECK=false AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $VS run --base HEAD~1 --head HEAD --out "$T/rf" >"$T/log" 2>&1
grep -qF 'UPSTREAM DOC CHANGE' "$T/rf/brief.md" && grep -qF 'NOT proven' "$T/rf/brief.md" && ok "a vendored folder that fails its proof is audited in full" || no "an unproven folder's docs were left out"
AIOS_AUDIT_PIN_CHECK=true AIOS_AUDIT_OUTSIDE="$T/out" AIOS_AUDIT_CLAUDE="$T/cl" $PYBIN $VS run --all --base HEAD~1 --head HEAD --out "$T/ra" >"$T/log" 2>&1
grep -qF 'UPSTREAM DOC CHANGE' "$T/ra/brief.md" && ok "--all audits proven vendored folders in full" || no "--all still left files out"

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

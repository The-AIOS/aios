#!/usr/bin/env bash
# tests/headless-live-opt-in.test.sh
#
# tests/headless-allowlist.test.sh measures a guarantee that only shows as an absent side effect, so
# its runtime half starts real `claude -p` sessions: nine per run. They ran on every local full
# suite, on the operator's own default model (#421): a coordinator saw sessions nobody had launched,
# and a machine whose default is the top rung paid top-rung prices for a permissions check.
#
# This holds the two fixes, with a stand-in `claude` first on PATH that only records how it was
# called, so no real session is ever started here:
#   1. without AIOS_LIVE_CHECKS=1 the live half never calls `claude`, and the run SAYS it skipped
#      and why, in the summary line too (a skipped check must not read as a passed one);
#   2. with it, every call carries --model, set to what `hooks/pipeline/resolve-tier fast` answers;
#   3. a model that cannot be resolved stops the live half before any call, as a failure.
set -u
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/config/projects" "$T/tmp"
cat > "$T/bin/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$T/calls"
exit 0
STUB
chmod +x "$T/bin/claude"
FAST=$(bash hooks/pipeline/resolve-tier fast 2>/dev/null)
[ -n "$FAST" ] || { echo "::error::resolve-tier fast answered nothing; cannot test"; exit 1; }

# CI is unset on purpose: the test under test skips on CI before it reaches the switch held here.
run(){ env -u CI -u AIOS_LIVE_CHECKS PATH="$T/bin:$PATH" CLAUDE_CONFIG_DIR="$T/config" TMPDIR="$T/tmp" AIOS_LIVE_TIMEOUT=5 "$@" bash tests/headless-allowlist.test.sh 2>&1; }

echo "── 1. without AIOS_LIVE_CHECKS=1: no session, and the run says so ──"
rm -f "$T/calls"; out=$(run)
[ ! -s "$T/calls" ] && ok "no call reached claude" || no "the live half called claude without being asked" "$(wc -l < "$T/calls" | tr -d ' ') calls"
printf '%s\n' "$out" | grep -q 'skip runtime check' && printf '%s\n' "$out" | grep -q 'AIOS_LIVE_CHECKS=1' \
  && ok "the skip line names the variable that runs it" || no "the skip does not say how to run the live half" "$(printf '%s\n' "$out" | grep -A1 'runtime' | head -4)"
last=$(printf '%s\n' "$out" | tail -1)
case "$last" in *skipped*"AIOS_LIVE_CHECKS=1"*) ok "the summary line itself says the live checks did not run: $last" ;;
  *) no "the summary line reads like a full pass" "$last" ;; esac
for v in 0 yes true ""; do
  rm -f "$T/calls"; run AIOS_LIVE_CHECKS="$v" >/dev/null
  [ ! -s "$T/calls" ] && ok "AIOS_LIVE_CHECKS='$v' is not a yes: no call" || no "AIOS_LIVE_CHECKS='$v' started the live half"
done

echo "── 2. with AIOS_LIVE_CHECKS=1: every call on the cheapest rung ──"
rm -f "$T/calls"; out=$(run AIOS_LIVE_CHECKS=1)
n=$(grep -c . "$T/calls" 2>/dev/null || echo 0)
[ "$n" -ge 1 ] && ok "the live half ran ($n calls to the stand-in)" || no "the live half did not run with the variable set" "$(printf '%s\n' "$out" | tail -5)"
miss=$(grep -v -- "--model $FAST" "$T/calls" 2>/dev/null | head -1)
[ "$n" -ge 1 ] && [ -z "$miss" ] && ok "every call carries --model $FAST (resolve-tier fast)" || no "a call ran without the cheapest model" "${miss:-no calls}"
[ "$(grep -c -- '--model' "$T/calls" 2>/dev/null)" = "$n" ] && ! grep -q -- '--model.*--model' "$T/calls" \
  && ok "exactly one --model per call" || no "a call carries --model twice or not at all"
printf '%s\n' "$out" | grep -q "on $FAST" && ok "the run names the model it used" || no "the run does not say which model the live calls used"

echo "── 3. no model to pin: the live half stops before any call, as a failure ──"
mkdir -p "$T/fw/hooks/pipeline"; cp -R tests "$T/fw/"; cp CLAUDE.md MODEL-ROUTING.md "$T/fw/"; mkdir -p "$T/fw/skills/aios/orchestration-ladder" "$T/fw/plugins/aios/commands"
cp skills/aios/orchestration-ladder/SKILL.md "$T/fw/skills/aios/orchestration-ladder/"; cp plugins/aios/commands/housekeeping.md "$T/fw/plugins/aios/commands/"
printf '#!/usr/bin/env bash\nexit 2\n' > "$T/fw/hooks/pipeline/resolve-tier"; chmod +x "$T/fw/hooks/pipeline/resolve-tier"
git -C "$T/fw" init -q 2>/dev/null
rm -f "$T/calls"; out=$(env -u CI PATH="$T/bin:$PATH" CLAUDE_CONFIG_DIR="$T/config" TMPDIR="$T/tmp" AIOS_LIVE_CHECKS=1 bash "$T/fw/tests/headless-allowlist.test.sh" 2>&1); rc=$?
[ ! -s "$T/calls" ] && ok "no call when the model cannot be resolved" || no "the live half ran unpinned" "$(head -1 "$T/calls")"
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'FAIL.*resolve-tier' && ok "and it is a failure that names resolve-tier, not a skip" || no "an unresolvable model was not a failure (rc=$rc)" "$(printf '%s\n' "$out" | grep -i 'resolve\|model' | head -3)"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

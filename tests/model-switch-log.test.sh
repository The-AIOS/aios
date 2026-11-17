#!/usr/bin/env bash
# tests/model-switch-log.test.sh
#
# hooks/pipeline/model-switch-log.py (SETUP Hook F) appends one line per PostModelSwitch to a JSONL log that
# /close-session, /close-day and the App read back. Asserts: the real payload's field names map to
# the documented format; every key is present even when the payload is thin; garbage input writes
# nothing and still exits 0 (a log must never break a session); a second switch appends.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/pipeline/model-switch-log.py"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
LOG="$T/model-switch.jsonl"
mkdir -p "$T/cfg/sessions"
printf '{"name":"worker-a","sessionId":"s1","pid":1}' > "$T/cfg/sessions/1.json"
run(){ printf '%s' "$1" | AIOS_MODEL_SWITCH_LOG="$LOG" CLAUDE_CONFIG_DIR="$T/cfg" $PYBIN "$H"; }

echo "── the real payload maps to the documented row ──"
run '{"session_id":"s1","hook_event_name":"PostModelSwitch","from_model":"claude-opus-5-5","to_model":"claude-opus-4-8","requested_model":"claude-opus-5-5","source":"fallback"}'; rc=$?
[ "$rc" = 0 ] && ok "exits 0" || no "exit $rc"
row="$(tail -1 "$LOG" 2>/dev/null)"
check(){ $PYBIN -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get(sys.argv[2])==sys.argv[3] else 1)' "$row" "$1" "$2" && ok "$1 = $2" || no "$1 is not $2" "$row"; }
check session_id s1; check name worker-a; check from claude-opus-5-5; check to claude-opus-4-8
check requested claude-opus-5-5; check reason fallback
$PYBIN -c 'import json,sys,re; d=json.loads(sys.argv[1]); sys.exit(0 if re.match(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", d["at"]) else 1)' "$row" \
  && ok "at is written by the hook, UTC ISO 8601" || no "at malformed" "$row"

echo "── a thin payload still yields every key ──"
run '{"to_model":"claude-haiku-5-5"}'
$PYBIN -c 'import json,sys; d=json.loads(sys.argv[1]); k={"at","session_id","name","from","to","requested","reason"}; sys.exit(0 if set(d)==k and d["to"]=="claude-haiku-5-5" and d["name"]=="" else 1)' "$(tail -1 "$LOG")" \
  && ok "all seven keys present, unknowns empty" || no "keys missing on a thin payload" "$(tail -1 "$LOG")"
[ "$(wc -l < "$LOG" | tr -d ' ')" = 2 ] && ok "a second switch appends" || no "expected 2 lines" "$(cat "$LOG")"

echo "── garbage writes nothing and never fails ──"
out=$(printf 'not json' | AIOS_MODEL_SWITCH_LOG="$LOG" $PYBIN "$H" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "bad input: exit 0, silent" || no "bad input rc=$rc" "$out"
[ "$(wc -l < "$LOG" | tr -d ' ')" = 2 ] && ok "bad input appended nothing" || no "bad input wrote a row"

echo "── --report flags only what finished on a model it did not ask for ──"
run '{"session_id":"s2","from_model":"claude-opus-4-8","to_model":"claude-opus-5-5","requested_model":"claude-opus-5-5","source":"user"}'
rep=$(AIOS_MODEL_SWITCH_LOG="$LOG" $PYBIN "$H" --report)
case "$rep" in *"worker-a"*"claude-opus-5-5 -> claude-opus-4-8"*) ok "the fallback row is reported" ;; *) no "fallback row missing" "$rep" ;; esac
case "$rep" in *"(asked for claude-opus-5-5; user)"*) no "a switch back to the requested model was flagged" "$rep" ;; *) ok "a switch back to the requested model is not flagged" ;; esac
[ -z "$(AIOS_MODEL_SWITCH_LOG="$LOG" $PYBIN "$H" --report --session nobody)" ] && ok "--session filters to one session" || no "--session did not filter"
[ -z "$(AIOS_MODEL_SWITCH_LOG="$LOG" $PYBIN "$H" --report --since 2999-01-01)" ] && ok "--since filters by date" || no "--since did not filter"
[ -z "$(AIOS_MODEL_SWITCH_LOG="$T/absent.jsonl" $PYBIN "$H" --report)" ] && ok "no log: silent, exit 0" || no "missing log was not silent"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]

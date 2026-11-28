#!/usr/bin/env bash
# quota-rotation-setting.test.sh — the rotation threshold and the on/off switch are a stored
# setting (#430), which the App and Glass show and edit through `claude-identity.sh rotation`.
#
# WHAT IT HOLDS
#   * no file: rotate at 98 in both windows, automatic rotation on, every value "default"
#   * `rotation --set` writes the file, and the watcher, `--threshold` and `--availability`
#     all read the same numbers from it, saying "file"
#   * CLAUDE_QUOTA_5H / CLAUDE_QUOTA_7D keep winning over the file, saying "environment"
#   * the writer refuses anything outside 50-98 (or not a whole number) and writes nothing
#   * a bad value IN the file (infinite, out of range, a string, true, broken JSON) is ignored
#     field by field and reported; it never turns rotation off or leaves a window at 0
#   * only a literal JSON false turns rotation off; "false", 0 or null is reported and ignored
#   * turned off, a tick over the threshold does not rotate, but the reading is still recorded;
#     CONTROL: turned on, the same tick goes on to the rotation gate
#   * the pause is untouched: off and paused are reported separately
#
# Runs against a fabricated HOME and CLAUDE_CONFIG_DIR with toy accounts; a `security` stand-in
# goes first on PATH, so nothing reaches the real Keychain, account list or ~/.claude.
set -uo pipefail
export AIOS_QUOTA_NOTIFY=0
unset USER_MD_PATH CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CONFIG_DIR CLAUDE_QUOTA_5H CLAUDE_QUOTA_7D

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/hooks/claude-identity/claude-identity.sh"
W="$ROOT/hooks/claude-identity/_watch.py"

PY=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PY="$_cand"; break; fi
done
[ -n "$PY" ] || { echo "SKIP: no working Python" >&2; exit 0; }

PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/rotset-XXXXXX")"
trap 'rm -rf "$BASE"' EXIT
A=first@example.com B=second@example.com
H="$BASE/h"
F="$H/.claude/quota-rotation.json"
mkdir -p "$H/.claude/identities" "$H/.aios" "$H/bin"
cat > "$H/bin/security" <<SEC
#!/usr/bin/env bash
case "\$1" in
  find-generic-password) [ -f "$H/live.json" ] && cat "$H/live.json" || exit 44 ;;
  *) exit 1 ;;
esac
SEC
chmod +x "$H/bin/security"
env_run() { HOME="$H" USERPROFILE="$H" PATH="$H/bin:$PATH" AIOS_KEYCHAIN_SERVICE="aios-rotation-setting-test" "$@"; }
rot() { env_run bash "$SH" rotation "$@" 2>/dev/null; }
avail() { env_run bash "$SH" switch --availability 2>/dev/null; }

ms_from_now() { $PY -c "import sys,time; print(int((time.time()+float(sys.argv[1]))*1000))" "$1"; }
blob() { printf '{"claudeAiOauth":{"accessToken":"t","refreshToken":"t","refreshTokenExpiresAt":%s}}' "$(ms_from_now 2592000)"; }
for e in "$A" "$B"; do
  d="$H/.claude/identities/$e"; mkdir -p "$d"; blob > "$d/keychain.json"
  printf '{"emailAddress":"%s"}' "$e" > "$d/oauthAccount.json"; printf 'uid-%s' "$e" > "$d/userID.txt"
done
printf '{"oauthAccount":{"emailAddress":"%s"},"userID":"uid-%s"}' "$A" "$A" > "$H/.claude.json"
blob > "$H/live.json"; cp "$H/live.json" "$H/.claude/.credentials.json"
printf '{"version":1,"accounts":[{"email":"%s"},{"email":"%s"}]}' "$A" "$B" > "$H/.aios/accounts.json"

# check <python expression over `s`> <json> <label>
check() {
  if $PY -c "import json,sys; s=json.loads(sys.argv[1]); sys.exit(0 if ($1) else 1)" "$2" 2>/dev/null; then ok "$3"; else no "$3" "${2:0:500}"; fi
}

echo "== 1. no file: the defaults, and where they come from =="
J="$(rot)"
check 's["five_hour"]=={"value":98,"source":"default"} and s["seven_day"]=={"value":98,"source":"default"}' "$J" "98 / 98, from the default"
check 's["enabled"]=={"value":True,"source":"default"} and s["ignored"]==[] and (s["min"],s["max"])==(50,98)' "$J" "automatic rotation on, nothing ignored, range 50-98"
[ ! -e "$F" ] && ok "reading does not create the file" || no "reading created $F"

echo "== 2. the writer, and every reader agreeing with it =="
J="$(rot --set 5h=90 7d=95)"
check 's["five_hour"]=={"value":90,"source":"file"} and s["seven_day"]=={"value":95,"source":"file"}' "$J" "--set 5h=90 7d=95 answers the new setting, from the file"
check '{"five_hour":90,"seven_day":95}.items() <= s.items()' "$(cat "$F" 2>/dev/null || echo '{}')" "the file holds exactly what was set"
J="$(avail)"
check 'len(s)==2 and all(r["rotate_at"]=={"five_hour":90,"seven_day":95} and r["swap_offer_at"]=={"five_hour":87,"seven_day":92} for r in s)' "$J" "--availability rotates at 90/95 and offers the button at 87/92"
check 'all(r["rotation_setting"]["five_hour"]["source"]=="file" and r["rotation_setting"]["enabled"]["value"] is True for r in s)' "$J" "and carries the setting with its sources on every row"
T="$(env_run $PY "$W" --threshold 2>/dev/null)"
case "$T" in *"5h: 90%  (file)"*"7d: 95%  (file)"*"automatic rotation: on"*) ok "watch --threshold says the same, and where from" ;; *) no "--threshold disagrees" "$T" ;; esac
X="$(env_run $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _watch; print(_watch.thresholds())' "$ROOT/hooks/claude-identity")"
[ "$X" = "(90, 95)" ] && ok "CONTROL: the watcher's own thresholds() reads (90, 95)" || no "the watcher disagrees" "$X"
rot --set 7d=97 >/dev/null
check 's.get("five_hour")==90 and s.get("seven_day")==97' "$(cat "$F")" "setting one window keeps the other"

echo "== 3. the environment keeps winning =="
J="$(CLAUDE_QUOTA_5H=80 rot)"
check 's["five_hour"]=={"value":80,"source":"environment"} and s["seven_day"]["source"]=="file"' "$J" "CLAUDE_QUOTA_5H=80 over a stored 90, per field"
J="$(CLAUDE_QUOTA_5H=20 rot)"
check 's["five_hour"]=={"value":20,"source":"environment"}' "$J" "the environment keeps its old 1-100 range (a machine that set 20 behaves as before)"
J="$(CLAUDE_QUOTA_5H=abc rot)"
check 's["five_hour"]=={"value":90,"source":"file"} and any("CLAUDE_QUOTA_5H" in i for i in s["ignored"])' "$J" "an invalid override falls back to the file, and is reported"

echo "== 4. the writer refuses, and writes nothing =="
before="$(cat "$F")"
for bad in 5h=99 5h=100 5h=49 5h=0 5h=abc 5h=inf 5h=9.5 5h=-90 10h=90 5h= maybe; do
  env_run bash "$SH" rotation --set "$bad" >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && [ "$(cat "$F")" = "$before" ] && ok "--set $bad is refused (exit $rc), file unchanged" || no "--set $bad was accepted" "rc=$rc file=$(cat "$F")"
done
env_run bash "$SH" rotation --set 5h=90 5h=200 >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$F")" = "$before" ] && ok "one bad value refuses the whole call" || no "a partial write happened" "$(cat "$F")"
env_run bash "$SH" rotation --set >/dev/null 2>&1 && no "--set with nothing was accepted" || ok "--set with nothing is refused"
env_run bash "$SH" rotation --bogus >/dev/null 2>&1 && no "an unknown rotation flag was accepted" || ok "an unknown rotation flag is refused"

echo "== 5. a bad value in the file is ignored and reported, never honoured =="
bad_file() { printf '%s' "$1" > "$F"; rot; }
for body in '{"five_hour":"inf"}' '{"five_hour":1e400}' '{"five_hour":Infinity}' '{"five_hour":NaN}' '{"five_hour":120}' \
            '{"five_hour":10}' '{"five_hour":97.5}' '{"five_hour":true}' '{"five_hour":null}' '{"five_hour":"90"}'; do
  J="$(bad_file "$body")"
  check 's["five_hour"]=={"value":98,"source":"default"} and len(s["ignored"])>=1 and s["enabled"]["value"] is True' "$J" "$body → 98 from the default, reported, rotation still on"
done
for body in 'not json' '[90,95]' '' '{"five_hour":'; do
  J="$(bad_file "$body")"
  check 's["five_hour"]["value"]==98 and s["seven_day"]["value"]==98 and s["enabled"]["value"] is True' "$J" "a file reading '$body' → defaults, rotation on"
done
J="$(bad_file '{"five_hour":200,"seven_day":91}')"
check 's["five_hour"]["source"]=="default" and s["seven_day"]=={"value":91,"source":"file"}' "$J" "one bad window does not drag the other"
J="$(env_run bash "$SH" switch --availability 2>/dev/null)"
check 'all(r["rotate_at"]=={"five_hour":98,"seven_day":91} and r["rotation_setting"]["ignored"] for r in s)' "$J" "--availability says so too"
rot --set 5h=92 >/dev/null
check 's=={"five_hour":92,"seven_day":91}' "$(cat "$F")" "the writer drops the bad field it finds and keeps the good one"

echo "== 6. on and off =="
for body in '{"enabled":"false"}' '{"enabled":0}' '{"enabled":null}' '{"enabled":"off"}'; do
  J="$(bad_file "$body")"
  check 's["enabled"]=={"value":True,"source":"default"} and s["ignored"]' "$J" "$body is a typo: rotation stays on, and it is reported"
done
rm -f "$F"
J="$(rot --set off)"
check 's["enabled"]=={"value":False,"source":"file"} and s["five_hour"]["value"]==98' "$J" "--set off turns it off and leaves the numbers alone"
J="$(avail)"
check 'all(r["rotation_setting"]["enabled"]["value"] is False and r["swap_offer_at"]=={"five_hour":95,"seven_day":95} for r in s)' "$J" "--availability says off, and still says where the manual button goes"
FUT="$($PY -c 'import time; print(int(time.time()) + 7200)')"
printf '%s\n' "$FUT" > "$H/.claude/quota-watch.paused"; touch -t 200001010000 "$H/.claude/quota-watch.paused"
J="$(avail)"
check "all(r['rotation_paused_until']==$FUT and r['rotation_setting']['enabled']['value'] is False for r in s)" "$J" "off and paused are reported separately, side by side"
rm -f "$H/.claude/quota-watch.paused"
J="$(rot --set on)"
check 's["enabled"]=={"value":True,"source":"file"}' "$J" "--set on turns it back on"

echo "== 7. a tick over the threshold: off does not rotate, on does =="
tick() { # $1 = on|off ; prints "<gate reached> <reading recorded> <OFF logged>"
  rot --set "$1" >/dev/null
  env_run $PY - "$W" "$A" <<'PY'
import importlib.util, json, os, sys, time
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
A = sys.argv[2]
with open(w.CACHE, "w", encoding="utf-8") as f:
    json.dump({"captured_at": time.time(), "five_hour_pct": 99, "seven_day_pct": 10, "email": A}, f)
seen = {"gate": False, "recorded": False}
w.reconnect_if_account_changed = lambda *a, **k: None
w._read_active_email = lambda: A
w.last_actual_swap = lambda: None
w.check_adoption = lambda c: None
w.recently_swapped = lambda: (False, 0)
w.record_state = lambda e, c: seen.__setitem__("recorded", True)
def gate(*a, **k):
    seen["gate"] = True
    return False  # stop at the gate: nothing past it runs
w.confirm_or_arm = gate
open(w.LOG, "w").close()
w.main("unused")
logged = "OFF" in open(w.LOG, encoding="utf-8").read()
print(int(seen["gate"]), int(seen["recorded"]), int(logged))
PY
}
r="$(tick off)"
[ "$r" = "0 1 1" ] && ok "off: 5h at 99 % does not reach the rotation gate, the reading is still recorded, and the log says OFF" || no "off → '$r' (want '0 1 1')"
r="$(tick on)"
[ "$r" = "1 1 0" ] && ok "CONTROL: on, the same tick reaches the rotation gate" || no "on → '$r' (want '1 1 0')"

echo "== 8. an older framework refuses the subcommand rather than switching =="
grep -qE '^\s*\*\)\s*$' "$SH" && grep -q 'unknown subcommand' "$SH" && ok "unknown subcommands are refused by the dispatcher (what an older script does with 'rotation')" || no "the dispatcher no longer refuses unknown subcommands"
grep -q '"rotation_setting"' "$W" && ok "--availability names the field the surfaces gate the editor on" || no "rotation_setting missing from availability()"

echo
echo "quota-rotation-setting: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

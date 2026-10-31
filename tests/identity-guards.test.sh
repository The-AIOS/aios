#!/usr/bin/env bash
# identity-guards.test.sh — the confirmation gate, and credentials with no tokens.
#
# Runs against a fabricated HOME. On macOS a `security` stand-in goes first on PATH, so
# nothing can reach the real Keychain, and swaps write to a fixture file.
#
# Regression origins:
#   - A session from before a swap reports the previous account's numbers under the new
#     account's name. One such reading used to rotate off a healthy account.
#   - A credential can be valid JSON with empty tokens. `--capture` saved it over a good
#     snapshot and reported success; a switch restored it, down to a login screen.
set -uo pipefail
export AIOS_QUOTA_NOTIFY=0   # drives real watcher ticks: no banners on this machine's desktop
unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/hooks/claude-identity/claude-identity.sh"
WATCH="$ROOT/hooks/claude-identity/_watch.py"

PY=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PY="$_cand"; break; fi
done
[ -n "$PY" ] || { echo "SKIP: no working Python" >&2; exit 0; }

PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
has(){ case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "expected [$2] in: $3" ;; esac; }
hasnt(){ case "$3" in *"$2"*) no "$1" "did not expect [$2] in: $3" ;; *) ok "$1" ;; esac; }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/guards-XXXXXX")"
trap 'rm -rf "$BASE"' EXIT
SECRET="sentinel-token-must-never-appear"
A=first@example.com B=second@example.com

sandbox() {
  H="$BASE/h${N:-0}"; N=$(( ${N:-0} + 1 ))
  mkdir -p "$H/.claude/identities" "$H/bin"
  printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$A" "$B" > "$H/USER.md"
  cat > "$H/bin/security" <<SEC
#!/usr/bin/env bash
case "\$1" in
  find-generic-password) [ -f "$H/live.json" ] && cat "$H/live.json" || exit 44 ;;
  add-generic-password) while [ \$# -gt 0 ]; do [ "\$1" = -w ] && { printf '%s' "\$2" > "$H/live.json"; }; shift; done ;;
  *) exit 1 ;;
esac
SEC
  chmod +x "$H/bin/security"
}
env_run() { HOME="$H" USERPROFILE="$H" PATH="$H/bin:$PATH" USER_MD_PATH="$H/USER.md" AIOS_KEYCHAIN_SERVICE="aios-guards-test" "$@"; }
sw() { env_run bash "$SH" switch "$@"; }
good() { printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s"}}' "$SECRET" "$SECRET"; }
empty() { printf '{"claudeAiOauth":{"accessToken":"","refreshToken":""}}'; }
capture() {  # capture <email> <blob>
  local d="$H/.claude/identities/$1"; mkdir -p "$d"
  printf '%s' "$2" > "$d/keychain.json"
  printf '{"emailAddress":"%s"}' "$1" > "$d/oauthAccount.json"
  printf 'uid-%s' "$1" > "$d/userID.txt"
}
seat() {  # seat <email> <blob>
  printf '{"oauthAccount":{"emailAddress":"%s"},"userID":"uid-%s"}' "$1" "$1" > "$H/.claude.json"
  printf '%s' "$2" > "$H/live.json"
  printf '%s' "$2" > "$H/.claude/.credentials.json"
}
active() { $PY -c "import json,sys; print(json.load(open(sys.argv[1]))['oauthAccount']['emailAddress'])" "$H/.claude.json"; }
reading() {  # reading <email> <7d pct>
  $PY - "$H/.claude/rate-limit-cache.json" "$1" "$2" <<'PY'
import json, sys, time
now = int(time.time())
json.dump({"email": sys.argv[2], "five_hour_pct": 1.0, "five_hour_resets_at": now + 3600,
           "seven_day_pct": float(sys.argv[3]), "seven_day_resets_at": now + 86400,
           "captured_at": now}, open(sys.argv[1], "w"))
PY
}
at() {  # at <email> <7d pct> <seconds from now>: a sample with its own explicit time
  $PY - "$H/.claude/rate-limit-cache.json" "$1" "$2" "$3" <<'PY'
import json, sys, time
now = int(time.time())
json.dump({"email": sys.argv[2], "five_hour_pct": 1.0, "five_hour_resets_at": now + 3600,
           "seven_day_pct": float(sys.argv[3]), "seven_day_resets_at": now + 86400,
           "captured_at": now + int(sys.argv[4])}, open(sys.argv[1], "w"))
PY
  tick
}
tick() { env_run $PY "$WATCH" "$SH" >/dev/null 2>&1; }
age_arming() {  # age_arming <seconds> [first-only]: as if the samples were that much older
  $PY - "$H/.claude/quota-watch.armed.json" "$1" "${2:-}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["first_sample"] -= int(sys.argv[2])
if not sys.argv[3]: d["last_sample"] -= int(sys.argv[2])
json.dump(d, open(sys.argv[1], "w"))
PY
}
rotated() { grep -c 'TRIGGER' "$H/.claude/quota-watch.log" 2>/dev/null || true; }

echo "== 1. the confirmation gate, driven through real ticks =="
two() { sandbox; capture "$A" "$(good)"; capture "$B" "$(good)"; seat "$A" "$(good)"; }
two; reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "one reading over threshold does not rotate" || no "rotated on one reading" "$(cat "$H/.claude/quota-watch.log")"
has "and says it is waiting" "gate armed" "$(cat "$H/.claude/quota-watch.log")"
reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "a second reading moments later does not confirm" || no "confirmed inside the gap" ""
[ "$(grep -c 'gate armed' "$H/.claude/quota-watch.log")" = 1 ] && ok "and does not re-arm or log again" || no "re-armed" "$(cat "$H/.claude/quota-watch.log")"
age_arming 31; reading "$A" 99; tick
[ "$(active)" = "$B" ] && ok "a reading past the gap rotates" || no "did not rotate" "$(cat "$H/.claude/quota-watch.log")"
has "and says so" "gate confirmed" "$(cat "$H/.claude/quota-watch.log")"
[ ! -f "$H/.claude/quota-watch.armed.json" ] && ok "nothing armed is left for the next account" || no "arming inherited" ""

two; reading "$A" 99; tick; age_arming 31 first; tick
[ "$(active)" = "$A" ] && ok "the same sample read twice is one reading" || no "one sample counted as two" "$(cat "$H/.claude/quota-watch.log")"

two; reading "$A" 99; tick; reading "$A" 40; tick
[ -f "$H/.claude/quota-watch.armed.json" ] && ok "one normal reading does not cancel: either session may be the stale one" || no "disarmed at once" ""
age_arming 121; reading "$A" 40; tick
[ ! -f "$H/.claude/quota-watch.armed.json" ] && ok "two minutes of normal readings drop a lone spike" || no "stayed armed" ""
reading "$A" 99; tick; [ "$(active)" = "$A" ] && ok "and the next high starts over" || no "rotated on a dropped spike" ""

two; reading "$A" 99; tick; age_arming 31; reading "$A" 40; tick; reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "over, under, over shortly after is not enough" || no "rotated on a phantom" "$(cat "$H/.claude/quota-watch.log")"
age_arming 301 first; age_arming 5; reading "$A" 40; tick; reading "$A" 99; tick
[ "$(active)" = "$B" ] && ok "highs and lows alternating for 5 minutes rotate" || no "stuck at a real cap" "$(cat "$H/.claude/quota-watch.log")"

two; reading "$A" 99; tick
$PY - "$H/.claude/quota-watch.armed.json" "$B" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["email"] = sys.argv[2]; d["first_sample"] -= 60; d["last_sample"] -= 60; json.dump(d, open(sys.argv[1], "w"))
PY
reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "an arming for another account does not confirm this one" || no "another account's arming confirmed" ""

two; reading "$A" 99; tick; age_arming 301; reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "an arming past its 5 minutes says nothing: re-arm" || no "stale arming confirmed" ""

two; reading "$A" 99; tick; age_arming 31
$PY - "$H/.claude/rate-limit-cache.json" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1])); d["seven_day_pct"] = 1.0; d["five_hour_pct"] = 99.0; d["captured_at"] = int(time.time()); json.dump(d, open(sys.argv[1], "w"))
PY
tick
[ "$(active)" = "$B" ] && ok "the other window over threshold confirms too: the account is over" || no "the wait restarted on a different window" "$(cat "$H/.claude/quota-watch.log")"

two; at "$A" 99 -40; at "$A" 99 -21
[ "$(active)" = "$A" ] && ok "two samples 19s apart do not confirm" || no "confirmed inside the gap" "$(cat "$H/.claude/quota-watch.log")"
at "$A" 99 -9
[ "$(active)" = "$B" ] && ok "a third at 31s from the first does" || no "did not confirm past the gap" "$(cat "$H/.claude/quota-watch.log")"

# Two sessions disagreeing, from end to end, with no hand on the arming file.
two; t=-300; rotated_at=""
while [ "$t" -le -60 ]; do
  at "$A" 99 "$t"; [ "$(active)" = "$A" ] || { rotated_at="$t"; break; }
  at "$A" 5 "$((t + 30))"
  t=$((t + 60))
done
[ -z "$rotated_at" ] && ok "highs and lows alternating do not rotate before 5 minutes" || no "rotated early, at $rotated_at" "$(cat "$H/.claude/quota-watch.log")"
at "$A" 99 0
[ "$(active)" = "$B" ] && ok "and do once they have lasted that long" || no "stuck past 5 minutes" "$(cat "$H/.claude/quota-watch.log")"

two; at "$A" 99 -100; at "$A" 5 -90; at "$A" 99 -60; at "$A" 99 -20
[ "$(active)" = "$A" ] && ok "once two sessions have disagreed, the longer wait holds through consecutive highs" || no "a low reading was forgotten" "$(cat "$H/.claude/quota-watch.log")"

two; at "$A" 99 -600; at "$A" 5 -570; at "$A" 5 -470; at "$A" 99 -440; at "$A" 5 -410; at "$A" 5 -310; at "$A" 99 -280
[ "$(active)" = "$A" ] && ok "highs over 2 minutes apart, with lows between, read as spikes" || no "rotated on spaced spikes" ""

two; reading "$A" 99
printf 'not json' > "$H/.claude/quota-watch.armed.json"; tick
[ "$(active)" = "$A" ] && has "a corrupt arming file just re-arms" "gate armed" "$(cat "$H/.claude/quota-watch.log")" || no "corrupt file rotated" ""

out="$(HOME="$BASE/unwritable" USER_MD_PATH=/dev/null $PY - "$WATCH" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
def boom(*a, **k): raise OSError("disk full")
w.write_json_atomic = boom
print(w.confirm_or_arm("a@example.com", "7d", 99.0, 1000))
PY
)"
has "an arming that cannot be saved rotates, not never" "True" "$out"

partial() { printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":""}}' "$SECRET"; }
partial_rt() { printf '{"claudeAiOauth":{"accessToken":"","refreshToken":"%s"}}' "$SECRET"; }
blank() { printf '{"claudeAiOauth":{"accessToken":"   ","refreshToken":"   "}}'; }
pending() { ls "$H"/.claude/.switch*.pending "$H"/.claude/.switch.pending 2>/dev/null | head -1; }

echo "== 2. --capture never saves a credential with no tokens =="
sandbox; capture "$A" "$(good)"; seat "$A" "$(empty)"
before="$(cat "$H/.claude/identities/$A/keychain.json")"
out="$(sw --capture 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "refused" "carries no tokens" "$out" || no "captured an empty credential" "$out"
[ "$(cat "$H/.claude/identities/$A/keychain.json")" = "$before" ] && ok "the good snapshot is untouched" || no "good snapshot destroyed" ""
seat "$A" 'not json'
out="$(sw --capture 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "not JSON reads differently" "malformed" "$out" || no "captured garbage" "$out"
seat "$A" "$(good)"
sw --capture >/dev/null 2>&1 && ok "CONTROL: a real credential captures" || no "refused a real credential" ""

echo "== 3. switching to a snapshot with no tokens stops before any write =="
sandbox; capture "$A" "$(good)"; capture "$B" "$(empty)"; seat "$A" "$(good)"
live="$(cat "$H/live.json")"
out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "refused" "refusing to switch" "$out" || no "restored an empty snapshot" "$out"
[ "$(active)" = "$A" ] && [ "$(cat "$H/live.json")" = "$live" ] && ok "the seat did not move" || no "seat changed" ""
hasnt "no token in the message" "$SECRET" "$out"
[ -z "$(pending)" ] && ok "no interrupted-switch marker is left behind" || no "a refusal left a pending marker" "$(pending)"
[ ! -f "$H/.claude.json.bak-claude-switch" ] && ok "and nothing was backed up, because nothing started" || no "refused after starting" ""
has "the repair does not send a /login into this seat" "CLAUDE_CONFIG_DIR" "$out"
has "and gives each account a config dir of its own" ".claude-acct-$B" "$out"
for b in partial partial_rt blank; do
  capture "$B" "$($b)"; out="$(sw "$B" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(active)" = "$A" ] && ok "refused: $b" || no "restored: $b" "$out"
  hasnt "$b: no token in the message" "$SECRET" "$out"
done
printf '[1,2]' > "$H/.claude/identities/$B/keychain.json"; out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(active)" = "$A" ] && ok "refused: JSON that is not an object" || no "restored a list" "$out"
printf '{"claudeAiOauth":null}' > "$H/.claude/identities/$B/keychain.json"; out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "refused: oauth null" || no "restored null" "$out"
printf '{"accessToken":"x","refreshToken":"y"}' > "$H/.claude/identities/$B/keychain.json"
env_run $PY -c "import sys; sys.path.insert(0, sys.argv[1]); from _fs import blob_token_state as b; print(b(sys.stdin.read()))" "$ROOT/hooks/claude-identity" < "$H/.claude/identities/$B/keychain.json" | grep -x ok >/dev/null && ok "the flat form is accepted" || no "flat form refused" ""
capture "$B" "$(good)"
sw "$B" >/dev/null 2>&1; [ "$(active)" = "$B" ] && ok "CONTROL: a real snapshot switches" || no "refused a real snapshot" ""

echo "== 4. a rotation leaving a dead credential still rotates =="
sandbox; capture "$A" "$(good)"; capture "$B" "$(good)"; seat "$A" "$(empty)"
before="$(cat "$H/.claude/identities/$A/keychain.json")"
out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(active)" = "$B" ] && ok "it goes on to the good account" || no "stranded on a dead credential" "$out"
[ "$(cat "$H/.claude/identities/$A/keychain.json")" = "$before" ] && ok "and keeps the outgoing account's last good snapshot" || no "overwrote it" ""
has "and says what it did not save" "left as it is" "$out"

sandbox; capture "$A" "$(good)"; capture "$B" "$(good)"; seat "$A" "$(partial)"
out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(active)" = "$B" ] && ok "same for a credential with one token missing" || no "stranded" "$out"
hasnt "and its warning prints no token" "$SECRET" "$out"
sandbox; capture "$A" "$(good)"; seat "$A" "$(partial)"
out="$(sw --capture 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && hasnt "a refused capture prints no token" "$SECRET" "$out" || no "captured a partial credential" "$out"

echo "== 4b. the watcher goes around a broken snapshot =="
C=third@example.com
three() { sandbox; printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n3. `%s`\n' "$A" "$B" "$C" > "$H/USER.md"; capture "$A" "$(good)"; capture "$C" "$(good)"; seat "$A" "$(good)"; }
over() {  # a confirmed reading: armed a minute ago, and a new sample now
  reading "$A" 99
  $PY - "$H/.claude/quota-watch.armed.json" "$A" <<'PY'
import json, sys, time
t = int(time.time()) - 60
json.dump({"email": sys.argv[2], "metric": "7d", "pct": 99, "first_sample": t, "last_sample": t}, open(sys.argv[1], "w"))
PY
  tick
}
three; capture "$B" "$(empty)"; over
[ "$(active)" = "$C" ] && ok "an empty snapshot is passed over for the next healthy account" || no "stuck on a broken snapshot" "$(cat "$H/.claude/quota-watch.log")"
three; capture "$B" "not json"; over
[ "$(active)" = "$C" ] && ok "so is a malformed one" || no "stuck on a malformed snapshot" ""
three; capture "$B" "$(good)"; over
[ "$(active)" = "$B" ] && ok "CONTROL: a healthy one is chosen" || no "skipped a healthy account" "$(cat "$H/.claude/quota-watch.log")"
three; capture "$B" "$(empty)"; capture "$C" "$(empty)"; over
[ "$(active)" = "$A" ] && has "all broken: it stays, and says why" "no usable alternative" "$(cat "$H/.claude/quota-watch.log")" || no "wrong outcome" "$(cat "$H/.claude/quota-watch.log")"

if [ "$(id -u)" != 0 ]; then
  three; capture "$B" "$(good)"; chmod 000 "$H/.claude/identities/$B/keychain.json"; over
  [ "$(active)" = "$C" ] && ok "so is one that cannot be read" || no "stuck on an unreadable snapshot" "$(cat "$H/.claude/quota-watch.log")"
  chmod 600 "$H/.claude/identities/$B/keychain.json"
fi

echo "== 4d. while armed, a low reading reaches the gate =="
CACHE_PY="$ROOT/hooks/claude-identity/_cache.py"
render() {  # render <5h pct>: the real statusLine path, with the watcher kept out of the way
  printf '{"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":2000000000},"seven_day":{"used_percentage":1,"resets_at":2000000000}}}' "$1" \
    | env_run $PY "$CACHE_PY" >/dev/null 2>&1
}
marker_age() { $PY -c "import os,sys,time; print(int(time.time()-os.path.getmtime(sys.argv[1])))" "$H/.claude/watch-tick"; }
old_marker() { : > "$H/.claude/watch-tick"; $PY -c "import os,sys,time; t=time.time()-10; os.utime(sys.argv[1],(t,t))" "$H/.claude/watch-tick"; }
two; old_marker; render 5
[ "$(marker_age)" -ge 9 ] && ok "CONTROL: nothing armed, a low render 10s after a kick stays quiet" || no "control kicked" "$(marker_age)"
printf '{"email":"%s","metric":"7d","pct":99,"first_sample":1,"last_sample":1}' "$A" > "$H/.claude/quota-watch.armed.json"
old_marker; render 5
[ "$(marker_age)" -lt 9 ] && ok "armed, the same render kicks the watcher" || no "the low reading never reached the gate" "$(marker_age)"
sleep 1

echo "== 4c. a refusal during an interrupted switch tells the truth =="
sandbox; capture "$A" "$(good)"; capture "$B" "$(empty)"; seat "$A" "$(good)"
P="$H/.claude/.switch-aios-guards-test.pending"; [ "$(uname -s)" = Darwin ] || P="$H/.claude/.switch.pending"
printf '%s %s\n' "$A" "$B" > "$P"
out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "it says the seat is inconsistent" "still unfinished" "$out" || no "refusal missing" "$out"
hasnt "and does not claim to be staying" "Staying on the current account" "$out"
[ -e "$P" ] && ok "the marker survives" || no "marker lost" ""

echo "== 5. --list reads what a snapshot contains =="
C=third@example.com D=fourth@example.com
sandbox; printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n3. `%s`\n4. `%s`\n' "$A" "$B" "$C" "$D" > "$H/USER.md"
capture "$A" "$(good)"; capture "$B" "$(empty)"; seat "$A" "$(good)"
mkdir -p "$H/.claude/identities/$D"; printf '%s' "$(good)" > "$H/.claude/identities/$D/keychain.json"
out="$(env_run bash "$SH" list 2>&1)"
line() { printf '%s\n' "$out" | grep -F "$1"; }
has "a real snapshot is saved" "saved" "$(line "$A")"
has "an empty one is BROKEN" "BROKEN" "$(line "$B")"
has "one never captured reads not saved" "not saved" "$(line "$C")"
hasnt "and not BROKEN" "BROKEN" "$(line "$C")"
has "one missing files cannot be restored, so it is not saved" "not saved" "$(line "$D")"
hasnt "no stray error from reading a missing file" "No such file" "$out"
hasnt "no token printed" "$SECRET" "$out"
capture "$B" "$(partial)"; out="$(env_run bash "$SH" list 2>&1)"
has "a partial one is BROKEN" "BROKEN" "$(line "$B")"
hasnt "and its line prints no token" "$SECRET" "$out"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$H/.claude/identities/$B/keychain.json"; out="$(env_run bash "$SH" list 2>&1)"; rc=$?
  chmod 600 "$H/.claude/identities/$B/keychain.json"
  [ "$rc" = 0 ] && has "an unreadable snapshot does not stop the list" "$C" "$out" || no "the list died" "$out"
  has "and reads as such" "cannot be read" "$(line "$B")"
fi

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

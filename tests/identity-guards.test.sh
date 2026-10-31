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
tick() { env_run $PY "$WATCH" "$SH" >/dev/null 2>&1; }
age_arming() {  # age_arming <seconds>: as if the first reading were that old
  $PY - "$H/.claude/quota-watch.armed.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["ts"] -= int(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))
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

two; reading "$A" 99; tick; reading "$A" 40; tick
[ ! -f "$H/.claude/quota-watch.armed.json" ] && ok "a normal reading disarms" || no "stayed armed" ""
reading "$A" 99; tick; age_arming 31; reading "$A" 40; tick; reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "over, under, over is a phantom, not a cap" || no "rotated on a phantom" ""

two; reading "$A" 99; tick; age_arming 301; reading "$A" 99; tick
[ "$(active)" = "$A" ] && ok "an arming past its 5 minutes says nothing: re-arm" || no "stale arming confirmed" ""

two; reading "$A" 99; tick; age_arming 31
$PY - "$H/.claude/rate-limit-cache.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["seven_day_pct"] = 1.0; d["five_hour_pct"] = 99.0; json.dump(d, open(sys.argv[1], "w"))
PY
tick
[ "$(active)" = "$A" ] && ok "the same account over a different window does not confirm" || no "crossed metrics confirmed" ""

two; reading "$A" 99
printf 'not json' > "$H/.claude/quota-watch.armed.json"; tick
[ "$(active)" = "$A" ] && has "a corrupt arming file just re-arms" "gate armed" "$(cat "$H/.claude/quota-watch.log")" || no "corrupt file rotated" ""

out="$(HOME="$BASE/unwritable" USER_MD_PATH=/dev/null $PY - "$WATCH" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
def boom(*a, **k): raise OSError("disk full")
w.write_json_atomic = boom
print(w.confirm_or_arm("a@example.com", "7d", 99.0))
PY
)"
has "an arming that cannot be saved rotates, not never" "True" "$out"

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
capture "$B" "$(good)"
sw "$B" >/dev/null 2>&1; [ "$(active)" = "$B" ] && ok "CONTROL: a real snapshot switches" || no "refused a real snapshot" ""

echo "== 4. a rotation leaving a dead credential still rotates =="
sandbox; capture "$A" "$(good)"; capture "$B" "$(good)"; seat "$A" "$(empty)"
before="$(cat "$H/.claude/identities/$A/keychain.json")"
out="$(sw "$B" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(active)" = "$B" ] && ok "it goes on to the good account" || no "stranded on a dead credential" "$out"
[ "$(cat "$H/.claude/identities/$A/keychain.json")" = "$before" ] && ok "and keeps the outgoing account's last good snapshot" || no "overwrote it" ""
has "and says what it did not save" "left as it is" "$out"

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

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

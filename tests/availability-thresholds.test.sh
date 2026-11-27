#!/usr/bin/env bash
# availability-thresholds.test.sh — `claude-switch --availability` tells the surfaces the
# numbers the watcher uses, so the App and Glass hold none of their own.
#
# Every row carries `rotate_at` (the watcher's thresholds), `swap_offer_at` (where a surface
# offers the swap button: the threshold minus SWAP_OFFER_MARGIN_PCT, floor 1) and
# `rotation_paused_until` (the operator's pause, or null). Global values, repeated per row,
# because the answer is a list and the surfaces' parser refuses any other shape.
#
# Regression origin: Glass offered the button at 5h >= 95 / 7d >= 99 from constants of its own,
# the App never offered it, and the watcher rotated at 98. Three surfaces, three rules.
#
# Runs against a fabricated HOME with toy accounts; a `security` stand-in goes first on PATH so
# nothing reaches the real Keychain. No real credential or account list is read.
set -uo pipefail
export AIOS_QUOTA_NOTIFY=0
unset USER_MD_PATH CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CONFIG_DIR CLAUDE_QUOTA_5H CLAUDE_QUOTA_7D

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/hooks/claude-identity/claude-identity.sh"

PY=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PY="$_cand"; break; fi
done
[ -n "$PY" ] || { echo "SKIP: no working Python" >&2; exit 0; }

PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

BASE="$(mktemp -d "${TMPDIR:-/tmp}/avail-XXXXXX")"
trap 'rm -rf "$BASE"' EXIT
SECRET="sentinel-token-must-never-appear"
A=first@example.com B=second@example.com

H="$BASE/h"
mkdir -p "$H/.claude/identities" "$H/.aios" "$H/bin"
cat > "$H/bin/security" <<SEC
#!/usr/bin/env bash
case "\$1" in
  find-generic-password) [ -f "$H/live.json" ] && cat "$H/live.json" || exit 44 ;;
  *) exit 1 ;;
esac
SEC
chmod +x "$H/bin/security"
env_run() { HOME="$H" USERPROFILE="$H" PATH="$H/bin:$PATH" AIOS_KEYCHAIN_SERVICE="aios-availability-test" "$@"; }
avail() { env_run bash "$SH" switch --availability 2>&1; }

ms_from_now() { $PY -c "import sys,time; print(int((time.time()+float(sys.argv[1]))*1000))" "$1"; }
blob() { printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","refreshTokenExpiresAt":%s}}' "$SECRET" "$SECRET" "$(ms_from_now 2592000)"; }
for e in "$A" "$B"; do
  d="$H/.claude/identities/$e"; mkdir -p "$d"; blob > "$d/keychain.json"
  printf '{"emailAddress":"%s"}' "$e" > "$d/oauthAccount.json"; printf 'uid-%s' "$e" > "$d/userID.txt"
done
printf '{"oauthAccount":{"emailAddress":"%s"},"userID":"uid-%s"}' "$A" "$A" > "$H/.claude.json"
blob > "$H/live.json"; cp "$H/live.json" "$H/.claude/.credentials.json"
printf '{"version":1,"accounts":[{"email":"%s","alias":"one"},{"email":"%s"}]}' "$A" "$B" > "$H/.aios/accounts.json"

# check <python expression over `rows`> <json> <label>
check() {
  if $PY -c "import json,sys; rows=json.loads(sys.argv[1]); sys.exit(0 if ($1) else 1)" "$2" 2>/dev/null; then ok "$3"; else no "$3" "${2:0:400}"; fi
}

echo "== 1. the watcher's thresholds, and where the button goes =="
J="$(avail)"
check 'len(rows)==2 and all(r["rotate_at"]=={"five_hour":98,"seven_day":98} for r in rows)' "$J" "every row says the watcher rotates at 98/98 by default"
check 'all(r["swap_offer_at"]=={"five_hour":95,"seven_day":95} for r in rows)' "$J" "and the button is offered 3 points before, in both windows"
check 'all(r["rotation_paused_until"] is None for r in rows)' "$J" "no pause: null"

echo "== 2. the shape the surfaces parse, and nothing else new =="
OLD='["email","alias","plan","rotation","reason","state","detail","capped_until","five_hour_pct","seven_day_pct","seven_day_pct_read","weekly_renews_at","weekly_renewed_since_reading","refresh_expires_at","refresh_expires_source","reading_recorded_at"]'
check 'isinstance(rows,list) and all(isinstance(r,dict) and isinstance(r.get("email"),str) and isinstance(r.get("state"),str) for r in rows)' "$J" "still a list of objects with email and state (the surfaces' parseAvailability)"
check "all(set(r)==set($OLD)|{'rotate_at','swap_offer_at','rotation_paused_until'} for r in rows)" "$J" "every row carries exactly the keys it had before plus the three new ones"
case "$J" in *"$SECRET"*) no "prints no token" "$J" ;; *) ok "prints no token" ;; esac

echo "== 3. an override is the watcher's own, read the same way =="
J="$(CLAUDE_QUOTA_5H=90 avail)"
check 'all(r["rotate_at"]=={"five_hour":90,"seven_day":98} and r["swap_offer_at"]=={"five_hour":87,"seven_day":95} for r in rows)' "$J" "CLAUDE_QUOTA_5H=90: rotate at 90, offer at 87; 7d unchanged"
J="$(CLAUDE_QUOTA_7D=abc avail)"
check 'all(r["rotate_at"]["seven_day"]==98 and r["swap_offer_at"]["seven_day"]==95 for r in rows)' "$J" "an invalid override falls back to the default, as it does for the watcher"
J="$(CLAUDE_QUOTA_5H=2 avail)"
check 'all(r["swap_offer_at"]["five_hour"]==1 for r in rows)' "$J" "a threshold of 2 offers at 1, never at 0 or below"
W="$(CLAUDE_QUOTA_5H=90 env_run $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _watch; print(_watch.thresholds())' "$ROOT/hooks/claude-identity")"
[ "$W" = "(90, 98)" ] && ok "CONTROL: the watcher itself reads (90, 98) from the same override" || no "watcher disagrees" "$W"

echo "== 4. the operator's pause =="
FUT="$($PY -c 'import time; print(int(time.time()) + 7200)')"
printf '%s\n' "$FUT" > "$H/.claude/quota-watch.paused"
J="$(avail)"
check "all(r['rotation_paused_until']==$FUT for r in rows)" "$J" "a pause two hours out is reported, in epoch seconds"
printf '%s\n' "$($PY -c 'import time; print(int(time.time()) - 60)')" > "$H/.claude/quota-watch.paused"
J="$(avail)"
check 'all(r["rotation_paused_until"] is None for r in rows)' "$J" "an expired pause is no pause (the watcher ignores it too)"
printf 'not-a-date\n' > "$H/.claude/quota-watch.paused"
J="$(avail)"
check 'all(r["rotation_paused_until"] is None for r in rows)' "$J" "a malformed pause is no pause"
for bad in inf nan 1e400 -inf; do
  printf '%s\n' "$bad" > "$H/.claude/quota-watch.paused"
  J="$(avail)"
  check 'all(r["rotation_paused_until"] is None for r in rows)' "$J" "a marker reading '$bad' is malformed: no pause, and the answer is still JSON"
done
W="$(printf 'inf\n' > "$H/.claude/quota-watch.paused"; env_run $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _watch; print(_watch.paused_until())' "$ROOT/hooks/claude-identity")"
[ "$W" = "0" ] && ok "and the watcher ignores an infinite marker rather than pausing forever" || no "the watcher pauses forever on inf" "$W"
: > "$H/.claude/quota-watch.paused"
J="$(avail)"
check 'all(r["rotation_paused_until"] is None for r in rows)' "$J" "an empty marker seconds old (a pause being written) is not reported as a pause"
rm -f "$H/.claude/quota-watch.paused"

echo
echo "availability-thresholds: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

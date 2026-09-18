#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A session launched with CLAUDE_CODE_OAUTH_TOKEN runs on the TOKEN's account,
# not on the seat (the account ~/.claude.json names, the one rotation swaps).
# Its usage numbers must never reach the seat's machinery.
#
# WHY. Every failure here is silent. A token tick in rate-limit-cache.json can
# hide the seat's cap from the watcher (or rotate the seat for a cap it does not
# have); a token sample filed under the seat corrupts the state rotation reads;
# an account observed but never captured, picked as a target, makes `switch`
# fail on every tick while a restorable alternative is never tried. None of
# these error -- the autopilot just stops protecting the operator.
#
# These run the SHIPPED scripts against a scratch config dir -- nothing touches
# the operator's own ~/.claude or Keychain.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
D=hooks/claude-identity
for f in "$D/_cache.py" "$D/_watch.py" "$D/claude-identity.sh" "$D/context-monitor.py"; do
  [ -f "$f" ] || { echo "::error::$f missing"; exit 1; }
done
D="$(cd "$D" && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SEAT=seat@example.com; TOK=other@example.com; SPARE=spare@example.com
FILES="keychain.json oauthAccount.json userID.txt"
PAYLOAD='{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":2000000000},"seven_day":{"used_percentage":7,"resets_at":2000000000}}}'

# A clean config dir whose seat is $SEAT. NO watch-tick: kick_watcher touches it
# before spawning, so its absence afterwards proves the watcher was not kicked.
fresh() {
  rm -rf "$TMP/cfg" && mkdir -p "$TMP/cfg"
  printf '{"oauthAccount":{"emailAddress":"%s"}}' "$SEAT" > "$TMP/cfg/.claude.json"
}
quiet() { date +%s > "$TMP/cfg/watch-tick"; }   # seat sessions: keep the real watcher from spawning
cache() {  # env assignments as args, then _cache.py on the payload
  printf '%s' "$PAYLOAD" | env -u CLAUDE_CODE_OAUTH_TOKEN -u AIOS_ACCOUNT_EMAIL \
    HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" "$@" python3 "$D/_cache.py"
}
field() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
capture() {  # $1 = email, $2 = file to leave out ("" = none)
  mkdir -p "$TMP/cfg/identities/$1"
  for f in $FILES; do [ "$f" = "${2:-}" ] || echo '{}' > "$TMP/cfg/identities/$1/$f"; done
}
# Load a shipped module from its file and print one expression over it. The
# expression is always a literal written in this file (never input), so eval is safe.
# Usage: [VAR=value ...] probe <module file> <expression over m>
PROBE='
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(eval(sys.argv[2]))'
probe() {
  local args=()
  while [ $# -gt 2 ]; do args+=("$1"); shift; done
  env -u CLAUDE_CODE_OAUTH_TOKEN -u AIOS_ACCOUNT_EMAIL ${args[@]+"${args[@]}"} python3 -c "$PROBE" "$1" "$2"
}

echo "-- 1. a token session with its account named: recorded under THAT account, seat untouched --"
fresh; cache CLAUDE_CODE_OAUTH_TOKEN=x AIOS_ACCOUNT_EMAIL="$TOK"
[ ! -e "$TMP/cfg/rate-limit-cache.json" ] && ok "rate-limit-cache.json not written" \
  || no "token session wrote the seat cache" "a token tick there can hide the seat's cap from the watcher"
L="$TMP/cfg/identities/$TOK/last-limits.json"
[ "$(field "$L" five_hour_pct) $(field "$L" five_hour_resets_at) $(field "$L" seven_day_pct) $(field "$L" seven_day_resets_at)" = "42 2000000000 7 2000000000" ] \
  && ok "all four limits recorded under the token's account" \
  || no "token account's last-limits.json missing or incomplete" "the watcher judges rotation targets from every one of these fields"
[ ! -e "$TMP/cfg/identities/$SEAT" ] && ok "nothing filed under the seat" \
  || no "the seat's identity dir was written" "the seat's state must only ever hold the seat's numbers"
[ ! -e "$TMP/cfg/watch-tick" ] && ok "the watcher was not kicked" \
  || no "a token tick kicked the watcher" "the watcher acts on the seat; nothing a token session reports is about the seat"

echo "-- 2. a token session WITHOUT its account named: dropped, never guessed onto the seat --"
fresh; cache CLAUDE_CODE_OAUTH_TOKEN=x
[ ! -e "$TMP/cfg/rate-limit-cache.json" ] && [ ! -e "$TMP/cfg/identities" ] && [ ! -e "$TMP/cfg/watch-tick" ] \
  && ok "nothing written anywhere, watcher not kicked" \
  || no "an unattributed token sample was written" "it would land on the seat, which is not the account that consumed it"

echo "-- 3. AIOS_ACCOUNT_EMAIL without a token is ignored: that session IS on the seat --"
fresh; quiet; cache AIOS_ACCOUNT_EMAIL="$TOK"
[ "$(field "$TMP/cfg/rate-limit-cache.json" email)" = "$SEAT" ] && ok "cache attributed to the seat" \
  || no "a stray AIOS_ACCOUNT_EMAIL re-labelled a seat session" "the seat would then never rotate"

echo "-- 4. a normal session is unchanged --"
fresh; quiet; cache
[ "$(field "$TMP/cfg/rate-limit-cache.json" email)" = "$SEAT" ] && [ "$(field "$TMP/cfg/rate-limit-cache.json" five_hour_pct)" = "42" ] \
  && ok "seat cache written as before" || no "normal session no longer writes the seat cache"

echo "-- 5. rotation only targets an account it can RESTORE --"
fresh
printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n3. `%s`\n' "$SEAT" "$TOK" "$SPARE" > "$TMP/USER.md"
pick() { probe HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" \
  "$D/_watch.py" 'm.pick_target("seat@example.com", 98, 98)[0]'; }
mkdir -p "$TMP/cfg/identities/$TOK"
echo '{"five_hour_pct":1,"seven_day_pct":1}' > "$TMP/cfg/identities/$TOK/last-limits.json"   # observed only
capture "$SPARE"
[ "$(pick)" = "$SPARE" ] && ok "an observed-but-uncaptured account is skipped for a restorable one" \
  || no "picked '$(pick)' (want $SPARE)" "switch to an uncaptured account fails every tick and the spare is never tried"
for missing in $FILES; do
  rm -f "$TMP/cfg/identities/$TOK/keychain.json" "$TMP/cfg/identities/$TOK/oauthAccount.json" "$TMP/cfg/identities/$TOK/userID.txt"
  capture "$TOK" "$missing"
  [ "$(pick)" = "$SPARE" ] && ok "missing $missing → not a target" || no "missing $missing → picked '$(pick)'" "restore dies without it"
done
capture "$TOK"
[ "$(pick)" = "$TOK" ] && ok "once captured, list order applies again" || no "picked '$(pick)' (want $TOK)"

echo "-- 5b. with NOTHING captured yet, a capped seat declines quietly instead of alerting every tick --"
fresh
printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$SEAT" "$TOK" > "$TMP/USER2.md"
python3 -c 'import json,sys,time;json.dump({"email":"seat@example.com","captured_at":int(time.time()),"five_hour_pct":99,"seven_day_pct":1},open(sys.argv[1],"w"))' \
  "$TMP/cfg/rate-limit-cache.json"
HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER2.md" python3 "$D/_watch.py" /nonexistent/claude-identity.sh
grep -q "no alternative account is captured yet" "$TMP/cfg/quota-watch.log" 2>/dev/null && [ ! -e "$TMP/cfg/swap-log.jsonl" ] \
  && ok "logged as 'not captured', no declined-rotation record or alert" \
  || no "an uncaptured-only pool took the capacity path" "that path notifies on every tick -- every few seconds near the cap -- for a setup step, not a capacity problem"

echo "-- 6. list marks 'saved' only what restore can use --"
fresh
lst() { HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" AIOS_KEYCHAIN_SERVICE="aios-token-test-$$" \
  bash "$D/claude-identity.sh" list 2>&1; }
capture "$SPARE"
for missing in $FILES; do
  rm -rf "$TMP/cfg/identities/$TOK"; capture "$TOK" "$missing"
  lst | grep -F "$TOK" | grep -q "not saved" && ok "missing $missing → 'not saved'" \
    || no "missing $missing reads as saved" "restore dies without it"
done
out=$(lst)
printf '%s\n' "$out" | grep -F "$SPARE" | grep -q "saved" && ! printf '%s\n' "$out" | grep -F "$SPARE" | grep -q "not saved" \
  && ok "full capture reads 'saved'" || no "full capture not shown as saved" "$out"

echo "-- 6b. whoami separates the seat from a token session --"
w=$(env -u AIOS_ACCOUNT_EMAIL HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" CLAUDE_CODE_OAUTH_TOKEN=x AIOS_ACCOUNT_EMAIL="$TOK" bash "$D/claude-identity.sh" whoami 2>&1)
printf "%s" "$w" | grep -q "runs on a token.*$TOK" && ok "whoami names the token account next to the seat" || no "whoami in a token session reads the seat as its own" "$w"

echo "-- 7. the statusline names the account actually consumed; only seat sessions see seat swaps --"
cp "$TMP/cfg/.claude.json" "$TMP/.claude.json"
chip() { probe HOME="$TMP" "$@" "$D/context-monitor.py" 'm.get_account_display()'; }
chip CLAUDE_CODE_OAUTH_TOKEN=x AIOS_ACCOUNT_EMAIL="$TOK" | grep -q "👤 other" && ok "token session shows the token's account" \
  || no "token session chip does not name the token's account"
chip CLAUDE_CODE_OAUTH_TOKEN=x | grep -q "token?" && ok "unnamed token session says so" \
  || no "unnamed token session shows the seat" "the one answer certainly wrong for it"
chip AIOS_ACCOUNT_EMAIL="$TOK" | grep -q "👤 seat" && ok "no token: chip shows the seat" \
  || no "stray AIOS_ACCOUNT_EMAIL re-labelled the chip"
mkdir -p "$TMP/.claude"
python3 -c 'import json,sys,time;json.dump({"ts":int(time.time()),"from":"seat@example.com","to":"spare@example.com"},open(sys.argv[1],"w"))' \
  "$TMP/.claude/swap-notification.json"
banner() { probe HOME="$TMP" "$@" "$D/context-monitor.py" 'm.get_swap_banner()'; }
banner | grep -q "🔄" && ok "seat session shows a recent seat swap (control)" \
  || no "seat swap banner missing" "without the control the next check proves nothing"
banner CLAUDE_CODE_OAUTH_TOKEN=x | grep -q "🔄" \
  && no "token session shows the seat-swap banner" "that session did not change account" \
  || ok "token session does not show the seat-swap banner"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

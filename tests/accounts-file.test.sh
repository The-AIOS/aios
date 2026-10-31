#!/usr/bin/env bash
# accounts-file.test.sh — the account list as a data file, and what it decides.
#
# Everything here runs against a fabricated HOME. On macOS a `security` stand-in goes
# first on PATH, so no assertion can reach the real Keychain, and a switch writes to a
# fixture file. No real credential or real account list is read.
#
# Regression origins:
#   - The list was prose in USER.md, read by three parsers. A reworded line dropped an
#     account silently, and "kept but not rotated" could not be stated.
#   - A rotation could land on an account whose refresh token had expired, which ends
#     at a login screen with nobody there. Nothing warned until the rotation happened.
#   - `--list` judged the active account from its saved copy, which only moves on a
#     swap or a capture, so a healthy account in use read as expired.
set -uo pipefail
export AIOS_QUOTA_NOTIFY=0   # drives real watcher code: no banners on this machine's desktop
unset USER_MD_PATH CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SH="$ROOT/hooks/claude-identity/claude-identity.sh"
ACC="$ROOT/hooks/claude-identity/_accounts.py"
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

BASE="$(mktemp -d "${TMPDIR:-/tmp}/acct-XXXXXX")"
trap 'rm -rf "$BASE"' EXIT
SECRET="sentinel-token-must-never-appear"
A=first@example.com B=second@example.com C=third@example.com

# A fresh fabricated HOME. Sets H, and the stand-in store for both credential backends.
sandbox() {
  H="$BASE/h$((${N:-0}))"; N=$(( ${N:-0} + 1 ))
  mkdir -p "$H/.claude/identities" "$H/.aios" "$H/bin"
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
env_run() { HOME="$H" USERPROFILE="$H" PATH="$H/bin:$PATH" AIOS_KEYCHAIN_SERVICE="aios-accounts-test" "$@"; }
sw() { env_run bash "$SH" switch "$@"; }
acc() { env_run $PY "$ACC" "$@"; }

ms_from_now() { $PY -c "import sys,time; print(int((time.time()+float(sys.argv[1]))*1000))" "$1"; }
blob() { printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","refreshTokenExpiresAt":%s}}' "$SECRET" "$SECRET" "$1"; }
DAY=86400

capture() {  # capture <email> <expiry-offset-secs | none>
  local d="$H/.claude/identities/$1"; mkdir -p "$d"
  if [ "$2" = none ]; then printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s"}}' "$SECRET" "$SECRET" > "$d/keychain.json"
  else blob "$(ms_from_now "$2")" > "$d/keychain.json"; fi
  printf '{"emailAddress":"%s"}' "$1" > "$d/oauthAccount.json"
  printf 'uid-%s' "$1" > "$d/userID.txt"
}
seat() {  # seat <email> <live-expiry-offset-secs>
  printf '{"oauthAccount":{"emailAddress":"%s"},"userID":"uid-%s"}' "$1" "$1" > "$H/.claude.json"
  blob "$(ms_from_now "$2")" > "$H/live.json"
  cp "$H/live.json" "$H/.claude/.credentials.json"
}
list_file() {  # list_file <json>
  printf '%s' "$1" > "$H/.aios/accounts.json"
}
three() { list_file "{\"version\":1,\"accounts\":[{\"email\":\"$A\",\"alias\":\"one\"},{\"email\":\"$B\",\"alias\":\"two\"},{\"email\":\"$C\"}]}"; }
field() { $PY -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2"; }

echo "== 1. first use imports the USER.md list =="
sandbox
# The import reads USER.md beside the code, so this runs a COPY of the hooks under a
# fixture root. It is the only section that does.
ROOTX="$H/root"; mkdir -p "$ROOTX/hooks"; cp -R "$ROOT/hooks/claude-identity" "$ROOTX/hooks/"; cp "$ROOT/hooks/aios-health.py" "$ROOTX/hooks/" 2>/dev/null
cat > "$ROOTX/USER.md" <<EOF
# USER

## Anthropic accounts (quota management)

> Why the order is what it is: a note with an accent, canción, and a reason.

1. \`$B\` — alias **two** · prose after it
2. \`$A\` — no alias here
3. \`$C\` — alias **three words here**

## Next section
1. \`notanaccount@example.com\`
EOF
before="$(cat "$ROOTX/USER.md")"
XACC="$ROOTX/hooks/claude-identity/_accounts.py"
out="$(env_run $PY "$XACC" rotation)"
[ "$out" = "$B
$A
$C" ] && ok "imported in USER.md's order, and not past its section" || no "wrong import" "$out"
[ -f "$H/.aios/accounts.json" ] && ok "the data file was written" || no "no data file" ""
[ "$(cat "$ROOTX/USER.md")" = "$before" ] && ok "USER.md was not written" || no "USER.md changed" ""
[ "$(field "$H/.aios/accounts.json" 'd["accounts"][0]["alias"]')" = "two" ] && ok "alias imported" || no "alias lost" ""
[ "$(field "$H/.aios/accounts.json" 'd["accounts"][2]["alias"]')" = "three words here" ] && ok "multi-word alias imported" || no "alias mangled" ""
hist="$(field "$H/.aios/accounts.json" 'd["history"][0]["note"]')"
has "the section's prose is kept in history" "canción, and a reason" "$hist"
has "the numbered lines are kept in history too" "prose after it" "$hist"
has "the import is logged" '"action": "import"' "$(cat "$H/.aios/accounts-log.jsonl")"
sed -i.bak 's/^1\. `'"$B"'`.*/1. `moved@example.com`/' "$ROOTX/USER.md"
out="$(env_run $PY "$XACC" rotation | head -1)"
[ "$out" = "$B" ] && ok "once the file exists, USER.md is not read" || no "USER.md still read" "$out"
sandbox
empty="$(env_run $PY "$ACC" rotation)"
[ -z "$empty" ] && [ ! -f "$H/.aios/accounts.json" ] && ok "no list anywhere: empty, and no file invented" || no "invented a list" "$empty"

echo "== 2. parallel actors =="
sandbox
ROOTX="$H/root"; mkdir -p "$ROOTX/hooks"; cp -R "$ROOT/hooks/claude-identity" "$ROOTX/hooks/"
printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$A" "$B" > "$ROOTX/USER.md"
XACC="$ROOTX/hooks/claude-identity/_accounts.py"
for i in 1 2 3 4 5 6 7 8; do ( env_run $PY "$XACC" rotation > "$H/par$i" 2>&1 ) & done; wait
n="$(grep -c '"action": "import"' "$H/.aios/accounts-log.jsonl")"
[ "$n" = 1 ] && ok "eight concurrent first uses import once" || no "imported $n times" ""
bad=0; for i in 1 2 3 4 5 6 7 8; do [ "$(tr '\n' ' ' < "$H/par$i")" = "$A $B " ] || bad=$((bad+1)); done
[ "$bad" = 0 ] && ok "and every one of them read the whole list" || no "$bad readers saw something else" "$(cat "$H/par1")"
sandbox; seat "$A" "$DAY"
for i in 1 2 3 4 5 6 7 8 9 10; do ( sw --add "acct$i@example.com" >/dev/null 2>&1 ) & done; wait
n="$(field "$H/.aios/accounts.json" 'len(d["accounts"])')"
[ "$n" = 10 ] && ok "ten concurrent --add: no update lost" || no "lost updates" "$n of 10 survived"

echo "== 3. a malformed list stops everything, loudly =="
sandbox; seat "$A" "$DAY"
check_bad() {  # check_bad <label> <json> <word in the reason>
  list_file "$2"
  local out rc
  out="$(sw --list 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then ok "$1: refused"; else no "$1: accepted" "$out"; fi
  has "$1: says why" "$3" "$out"
}
check_bad "broken JSON" '{"version":1,' "not valid JSON"
check_bad "wrong version" '{"version":9,"accounts":[]}' "version"
check_bad "duplicate email" "{\"version\":1,\"accounts\":[{\"email\":\"$A\"},{\"email\":\"$A\"}]}" "twice"
check_bad "alias colliding with another" "{\"version\":1,\"accounts\":[{\"email\":\"$A\",\"alias\":\"x\"},{\"email\":\"$B\",\"alias\":\"x\"}]}" "twice"
check_bad "mistyped key" "{\"version\":1,\"accounts\":[{\"email\":\"$A\",\"rotaton\":false}]}" "unknown key"
check_bad "rotation not a boolean" "{\"version\":1,\"accounts\":[{\"email\":\"$A\",\"rotation\":\"no\"}]}" "true or false"
check_bad "alias that reads as a flag" "{\"version\":1,\"accounts\":[{\"email\":\"$A\",\"alias\":\"-x\"}]}" "alias"
check_bad "not an email" '{"version":1,"accounts":[{"email":"nobody"}]}' "email"
list_file '{"version":1,'
env_run $PY "$WATCH" "$SH" >/dev/null 2>&1
[ "$(field "$H/.aios/health/quota-watch.json" 'd["state"]')" = fail ] && ok "the watcher's health goes red" || no "health stayed quiet" "$(cat "$H/.aios/health/quota-watch.json" 2>&1)"
has "and names the file" "accounts.json" "$(field "$H/.aios/health/quota-watch.json" 'd["detail"]')"
status="$(printf '{}' | env_run $PY "$ROOT/hooks/claude-identity/context-monitor.py" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "the statusline still renders" || no "statusline broke" "$status"

echo "== 4. pick_target skips an expired account =="
pick() {  # prints target|reason
  env_run $PY - "$WATCH" "$1" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
t, why = w.pick_target(sys.argv[2], 98, 98)
print(f"{t}|{why}")
PYEOF
}
sandbox; three; capture "$A" "$DAY"; capture "$B" "-$DAY"; capture "$C" "$DAY"
out="$(pick "$A")"
has "the expired slot is passed over for the next one" "$C|" "$out"
capture "$B" "$DAY"
has "CONTROL: the same slot, unexpired, is chosen" "$B|" "$(pick "$A")"
capture "$B" none
has "CONTROL: a credential stating no expiry stays a candidate" "$B|" "$(pick "$A")"
capture "$B" "-$DAY"; capture "$C" "-$DAY"
out="$(pick "$A")"
has "all expired: no target" "None|" "$out"
has "and it says expired, not capped" "expired" "$out"
hasnt "and does not claim a capacity problem" "still capped" "$out"

echo "== 5. the watcher warns before rotation needs it =="
tick() { env_run $PY "$WATCH" "$SH" >/dev/null 2>&1; }
state() { field "$H/.aios/health/quota-watch.json" 'd["state"]'; }
detail() { field "$H/.aios/health/quota-watch.json" 'd["detail"]'; }
sandbox; three; seat "$A" "$DAY"; capture "$B" "-$DAY"; capture "$C" "$DAY"
tick
[ "$(state)" = warn ] && ok "next fallback expired: warn" || no "no warning" "$(state): $(detail)"
has "names the account" "$B" "$(detail)"
tick
n="$(grep -c 'WARNING' "$H/.claude/quota-watch.log")"
[ "$n" = 1 ] && ok "the alarm fires once, not on every tick" || no "fired $n times" ""
capture "$B" "$DAY"
tick
[ "$(state)" = ok ] && ok "CONTROL: renewed, it clears" || no "did not clear" "$(state): $(detail)"
capture "$C" "-$DAY"
tick
[ "$(state)" = ok ] && ok "an expired account further down is not the next fallback" || no "false alarm" "$(detail)"
sandbox; three; seat "$A" "$DAY"; capture "$C" "$DAY"
tick
[ "$(state)" = warn ] && has "next fallback not captured, another is: warn" "not captured" "$(detail)" || no "no warning" "$(detail)"
sandbox; three; seat "$A" "$DAY"
tick
[ "$(state)" = ok ] && ok "none captured yet: a setup in progress, not an alarm" || no "nagged a new install" "$(detail)"

sandbox; three; seat "$A" "$DAY"; capture "$A" "-$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
tick
[ "$(state)" = ok ] && ok "the active account's old saved copy is ignored" || no "alarm from the active account's copy" "$(detail)"
has "and it is not the reason for any choice" "$B|" "$(pick "$A")"

echo "== 5b. an empty list is never silent, where a rotation existed =="
sandbox; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"
tick
[ "$(state)" = fail ] && ok "two captured, no file, no USER.md list: fail" || no "0 accounts in silence" "$(state): $(detail)"
has "and it says what to do" "claude-switch --add" "$(detail)"
has "and it is logged" "no account list" "$(cat "$H/.claude/quota-watch.log")"
sandbox; three; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"
sw --disable "$C" >/dev/null 2>&1; rm -f "$H/.aios/accounts.json"
rm -rf "$H/.claude/identities/$B"
tick
[ "$(state)" = fail ] && ok "the file was deleted (a change had been logged): fail" || no "deleted list went unnoticed" "$(state): $(detail)"
sandbox; seat "$A" "$DAY"; capture "$A" "$DAY"
tick
[ "$(state)" = ok ] && ok "CONTROL: one account, never a rotation: stays quiet" || no "red health for a one-account install" "$(state): $(detail)"
out="$(sw --list 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "--list on an empty list stops and says how" "claude-switch --add" "$out" || no "--list said nothing" "$out"

echo "== 6. --list reads the live credential for the active account =="
sandbox; three
capture "$A" "-$DAY"            # the saved copy of the ACTIVE account is old...
seat "$A" "$((30 * DAY))"       # ...and what is in use is healthy
capture "$B" "-$DAY"            # a saved account that really is expired
capture "$C" "$DAY"
out="$(sw --list 2>&1)"
line() { printf '%s\n' "$out" | grep -F "$1"; }
hasnt "the active account does not read as expired" "expired" "$(line "$A")"
has "the saved one that is expired does" "expired" "$(line "$B")"
hasnt "CONTROL: a saved one that is fine does not" "expired" "$(line "$C")"
seat "$A" "-$DAY"
out="$(sw --list 2>&1)"
has "CONTROL: a truly expired live credential does read as expired" "expired" "$(line "$A")"
hasnt "--list prints no token" "$SECRET" "$out"
has "an account with no alias keeps its slot" "3. $C" "$(line "$C")"
hasnt "and is not read as out of rotation" "not in rotation" "$(line "$C")"
rm -f "$H/live.json" "$H/.claude/.credentials.json"
out="$(sw --list 2>&1)"
has "an unreadable live credential says so, never the saved date" "unreadable" "$(line "$A")"

echo "== 7. --order, --enable, --disable =="
sandbox; three; seat "$C" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
out="$(sw --order two,one,"$C" 2>&1)"
has "shows the fallback before" "before: $A" "$out"
has "shows the fallback after" "after:  $B" "$out"
[ "$(acc rotation | head -1)" = "$B" ] && ok "applied, and aliases resolved" || no "not applied" "$(acc rotation)"
row="$(tail -1 "$H/.aios/accounts-log.jsonl")"
has "logged with both fallbacks" "\"fall_before\": \"$A\"" "$row"
has "logged with the new order" "\"fall_after\": \"$B\"" "$row"
hasnt "the log holds no token" "$SECRET" "$(cat "$H/.aios/accounts-log.jsonl")"
snap="$(cat "$H/.aios/accounts.json")"
out="$(sw --order one,two 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "an order missing an account is refused" "every account" "$out" || no "accepted a partial order" "$out"
out="$(sw --order one,one,"$C" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "a duplicate is refused" || no "accepted a duplicate" "$out"
[ "$(cat "$H/.aios/accounts.json")" = "$snap" ] && ok "a refused change leaves the file alone" || no "file changed" ""
sw --disable two --reason "kept, not rotated" >/dev/null 2>&1
[ "$(acc rotation | tr '\n' ' ')" = "$A $C " ] && ok "--disable takes it out of rotation" || no "still in" "$(acc rotation)"
[ "$(acc resolve two)" = "$B" ] && ok "and its alias still resolves" || no "alias lost" ""
has "--list still shows it, with the reason" "kept, not rotated" "$(sw --list 2>&1 | grep -F "$B")"
has "the watcher does not pick it" "$A|" "$(pick "$C")"
sw --order "$C",one >/dev/null 2>&1 && ok "--order needs only the accounts in rotation" || no "refused" ""
capture "$B" "-$DAY"
out="$(sw --enable two 2>&1)"
has "--enable on an expired account warns" "expired" "$out"
[ "$(acc rotation | grep -c "$B")" = 1 ] && ok "and still applies" || no "not enabled" ""
hasnt "--enable cleared the reason" "kept, not rotated" "$(cat "$H/.aios/accounts.json")"

echo "== 8. switch: aliases, and manual rotation past expired =="
sandbox; three; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
out="$(sw nosuchalias 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "an unknown alias is refused" "no account or alias" "$out" || no "accepted" "$out"
sw two >/dev/null 2>&1
[ "$(field "$H/.claude.json" 'd["oauthAccount"]["emailAddress"]')" = "$B" ] && ok "an alias switches" || no "alias did not switch" "$(cat "$H/.claude.json")"
sw "$A" >/dev/null 2>&1
capture "$B" "-$DAY"
[ "$(acc next "$A" 2>/dev/null)" = "$C" ] && ok "bare rotation passes over the expired account" || no "landed on it" "$(acc next "$A")"
has "and says what it skipped" "$B" "$(acc next "$A" 2>&1 >/dev/null)"
has "whoami agrees" "$C" "$(env_run bash "$SH" whoami 2>&1 | grep Next)"

echo "== 9. old mode: USER_MD_PATH =="
sandbox; three
printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$C" "$B" > "$H/fixture.md"
out="$(USER_MD_PATH="$H/fixture.md" acc rotation | tr '\n' ' ')"
[ "$out" = "$C $B " ] && ok "that file is the list, over the data file" || no "wrong source" "$out"
out="$(USER_MD_PATH="$H/fixture.md" acc order "$B,$C" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "changes are refused, with the way out" "USER_MD_PATH" "$out" || no "changed anyway" "$out"
sandbox
printf '## Anthropic accounts\n\n1. `%s`\n' "$C" > "$H/fixture.md"
USER_MD_PATH="$H/fixture.md" acc rotation >/dev/null
[ ! -f "$H/.aios/accounts.json" ] && ok "nothing is imported from it" || no "imported from a fixture" ""
out="$(AIOS_ACCOUNTS_FILE="$H/other.json" USER_MD_PATH="$H/fixture.md" acc rotation)"
[ -z "$out" ] && ok "AIOS_ACCOUNTS_FILE wins over it" || no "fixture won" "$out"

echo "== 10. the statusline takes its alias from the list =="
sandbox; three
out="$(env_run $PY - "$ROOT/hooks/claude-identity/context-monitor.py" "$B" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cm", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m._account_label(sys.argv[2]))
PYEOF
)"
[ "$out" = two ] && ok "alias from the data file" || no "wrong label" "$out"

echo "== 11. availability, and the stored expiry =="
limits() {  # limits <email> <7d pct> <reset offset secs>
  $PY - "$H/.claude/identities/$1/last-limits.json" "$2" "$3" <<'PYEOF'
import json, sys, time
now = time.time()
json.dump({"recorded_at": int(now - 7200), "five_hour_pct": 1, "five_hour_resets_at": now + 3600,
           "seven_day_pct": float(sys.argv[2]), "seven_day_resets_at": now + float(sys.argv[3])}, open(sys.argv[1], "w"))
PYEOF
}
row() { $PY -c "import json,sys; r={x['email']:x for x in json.load(sys.stdin)}; print(r[sys.argv[1]][sys.argv[2]])" "$1" "$2"; }
sandbox; three; seat "$A" "$((30 * DAY))"; capture "$A" "-$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
limits "$B" 99 "$DAY"; limits "$C" 99 "-$DAY"
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$A" state)" = active ] && ok "the seat reads active" || no "seat" "$J"
[ "$(printf '%s' "$J" | row "$B" state)" = capped ] && ok "over the threshold, before its reset: capped" || no "not capped" "$J"
has "and says until when" "until" "$(printf '%s' "$J" | row "$B" detail)"
[ "$(printf '%s' "$J" | row "$C" state)" = available ] && ok "over the threshold, past its reset: available" || no "old number read as capped" "$J"
[ "$(printf '%s' "$J" | row "$C" seven_day_pct)" = 0 ] && ok "and past its renewal date, it reads 0%" || no "kept the old number" "$J"
has "and says when it renewed" "renewed" "$(printf '%s' "$J" | row "$C" detail)"
want="$(printf '%s' "$J" | row "$C" weekly_renews_at)"
$PY - "$want" "$H/.claude/identities/$C/last-limits.json" <<'PYEOF' && ok "its next renewal is the same date, a week on" || no "wrong next renewal" "$want"
import json, sys, time
next_, anchor = float(sys.argv[1]), json.load(open(sys.argv[2]))["seven_day_resets_at"]
sys.exit(0 if abs((next_ - anchor) - 7 * 86400) < 2 and next_ > time.time() else 1)
PYEOF
$PY - "$H/.claude/identities/$C/last-limits.json" <<'PYEOF'
import json, sys, time
d = json.load(open(sys.argv[1])); d["seven_day_resets_at"] = time.time() - 30 * 86400; d["seven_day_pct"] = 80; json.dump(d, open(sys.argv[1], "w"))
PYEOF
J="$(sw --availability 2>&1)"
$PY -c "import json,sys,time; r={x['email']:x for x in json.load(sys.stdin)}[sys.argv[1]]; sys.exit(0 if time.time() < r['weekly_renews_at'] <= time.time()+7*86400 and r['seven_day_pct']==0 else 1)" "$C" <<<"$J" && ok "weeks later, it still projects to the coming week" || no "projection off" "$J"
limits "$C" 40 "$DAY"
J="$(sw --availability 2>&1)"
x="$(printf '%s' "$J" | row "$C" seven_day_pct)"; [ "${x%.0}" = 40 ] && ok "CONTROL: inside its window, the number stands" || no "zeroed a live number" "$J"
has "with its renewal date" "renews" "$(printf '%s' "$J" | row "$C" detail)"
has "--list shows the renewal per account" "renews" "$(sw --list 2>&1 | grep -F "$C")"
limits "$C" 99 "-$DAY"
has "--list says it per account" "until" "$(sw --list 2>&1 | grep -F "$B")"
capture "$B" "-$DAY"
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$B" state)" = expired ] && ok "expired wins over capped" || no "capped hid an expired token" "$J"
hasnt "--availability prints no token" "$SECRET" "$J"
S="$H/.aios/accounts-state.json"
[ -f "$S" ] && ok "dates are stored" || no "no store" ""
hasnt "and the store holds no token" "$SECRET" "$(cat "$S")"
[ "$(field "$S" 'd["'"$B"'"]["refresh_source"]')" = saved ] && ok "an idle account's date comes from its saved copy" || no "wrong source" "$(cat "$S")"
sandbox; three; seat "$A" "$((30 * DAY))"; capture "$A" "-$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
J="$(sw --availability 2>&1)"; S="$H/.aios/accounts-state.json"
[ "$(field "$S" '"refresh_expires_at" in d.get("'"$A"'", {})')" = False ] && ok "the active account's old saved copy is not stored" || no "stored a stale date" "$(cat "$S")"
sw --list >/dev/null 2>&1
[ "$(field "$S" 'd["'"$A"'"]["refresh_source"]')" = live ] && ok "--list stores the active account's live date" || no "live date not stored" "$(cat "$S")"
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$A" refresh_expires_source)" = live ] && ok "and availability reports it" || no "not reported" "$J"
rm -f "$H/live.json" "$H/.claude/.credentials.json"
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$A" refresh_expires_source)" = live ] && ok "asking needs no access to a credential" || no "needed the credential" "$J"
sandbox; three; capture "$A" "$DAY"; printf '{"oauthAccount":{"emailAddress":"%s"}}' "$A" > "$H/.claude.json"
printf '## Anthropic accounts\n\n1. `%s`\n' "$C" > "$H/fixture.md"; rm -f "$H/.aios/accounts.json"
USER_MD_PATH="$H/fixture.md" acc sync-expiry "$C"
USER_MD_PATH="$H/fixture.md" acc expiry --email "$A" --record "$A" >/dev/null
[ ! -f "$H/.aios/accounts-state.json" ] && ok "old mode stores nothing, so a fixture cannot touch a real store" || no "fixture wrote a store" ""

sandbox; three; capture "$A" "$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"; seat "$A" "$DAY"
$PY - "$H/.claude/rate-limit-cache.json" "$A" <<'PYEOF'
import json, sys, time
now = int(time.time())
json.dump({"email": sys.argv[2], "captured_at": now, "five_hour_pct": 5, "five_hour_resets_at": now + 3600,
           "seven_day_pct": 10, "seven_day_resets_at": now + 5 * 86400}, open(sys.argv[1], "w"))
PYEOF
env_run $PY "$WATCH" "$SH" >/dev/null 2>&1
S="$H/.aios/accounts-state.json"
[ "$(field "$S" 'd["'"$A"'"].get("weekly_renews_at", 0) > 0')" = True ] && ok "a tick stores the active account's renewal date" || no "not stored" "$(cat "$S" 2>&1)"
rm -f "$H/.claude/identities/$A/last-limits.json"
J="$(sw --availability 2>&1)"
$PY -c "import json,sys,time; r={x['email']:x for x in json.load(sys.stdin)}[sys.argv[1]]; sys.exit(0 if r['weekly_renews_at'] and r['weekly_renews_at']>time.time() else 1)" "$A" <<<"$J" && ok "and it outlives the reading" || no "lost with the reading" "$J"

$PY - "$H/.claude/rate-limit-cache.json" "$A" <<'PYEOF'
import json, sys, time
now = int(time.time())
json.dump({"email": sys.argv[2], "captured_at": now, "five_hour_pct": 5, "five_hour_resets_at": now + 3600,
           "seven_day_pct": 10, "seven_day_resets_at": now + 2 * 86400}, open(sys.argv[1], "w"))
PYEOF
before="$(field "$S" 'd["'"$A"'"]["weekly_renews_at"]')"
printf '{"ts":%s,"from":"x@example.com","action":"rotate","rc":0}\n' "$(( $(date +%s) - 5 ))" > "$H/.claude/swap-log.jsonl"
env_run $PY "$WATCH" "$SH" >/dev/null 2>&1
[ "$(field "$S" 'd["'"$A"'"]["weekly_renews_at"]')" = "$before" ] && ok "inside the post-swap cooldown a reading may be another account's: no date is stored" || no "stored a date during cooldown" "$(cat "$S")"
rm -f "$H/.claude/swap-log.jsonl"
limit_with_stored() {  # the reading's reset is $2 from now, the stored date $3, the reading itself $4 (default a minute ago)
  $PY - "$H/.claude/identities/$1/last-limits.json" "$S" "$1" "$2" "$3" "${4:--60}" <<'PYEOF'
import json, sys, time
now = time.time()
r = None if sys.argv[4] == "null" else now + float(sys.argv[4])
json.dump({"recorded_at": int(now + float(sys.argv[6])), "five_hour_pct": 1, "five_hour_resets_at": now + 3600, "seven_day_pct": 99,
           "seven_day_resets_at": r}, open(sys.argv[1], "w"))
d = json.load(open(sys.argv[2])); d.setdefault(sys.argv[3], {})["weekly_renews_at"] = now + float(sys.argv[5])
json.dump(d, open(sys.argv[2], "w"))
PYEOF
}
limit_with_stored "$B" "$DAY" "-$DAY"
J="$(sw --availability 2>&1)"
x="$(printf '%s' "$J" | row "$B" seven_day_pct)"
[ "$(printf '%s' "$J" | row "$B" state)" = capped ] && [ "${x%.0}" = 99 ] && ok "the reading's own date beats the stored one" || no "stored date won" "$J"
limit_with_stored "$B" null "-$DAY" "-$((3 * DAY))"
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$B" state)" = available ] && [ "$(printf '%s' "$J" | row "$B" seven_day_pct)" = 0 ] && ok "a reading with no reset, taken before the stored date, renewed with it" || no "capped until unknown" "$J"
has "and the rotation agrees" "$B|" "$(pick "$A")"
limit_with_stored "$B" null "-$((3 * DAY))" "-60"
J="$(sw --availability 2>&1)"; x="$(printf '%s' "$J" | row "$B" seven_day_pct)"
[ "$(printf '%s' "$J" | row "$B" state)" = capped ] && [ "${x%.0}" = 99 ] && ok "a high reading taken AFTER the stored date stays capped, without contradicting itself" || no "lifted a real cap" "$J"
hasnt "and the rotation does not pick it" "$B|" "$(pick "$A")"
$PY - "$H/.claude/identities/$B/last-limits.json" <<'PYEOF'
import json, sys, time
json.dump({"seven_day_pct": 99, "five_hour_pct": 1}, open(sys.argv[1], "w"))
PYEOF
J="$(sw --availability 2>&1)"; x="$(printf '%s' "$J" | row "$B" seven_day_pct)"
[ "$(printf '%s' "$J" | row "$B" state)" = capped ] && [ "${x%.0}" = 99 ] && ok "a reading with no dates at all stays capped, without contradicting itself" || no "contradiction" "$J"
limits "$B" 10 "$DAY"; sw --disable two >/dev/null 2>&1
J="$(sw --availability 2>&1)"
[ "$(printf '%s' "$J" | row "$B" state)" = out-of-rotation ] && ok "an account out of rotation does not read as available" || no "read as available" "$J"
sw --enable two >/dev/null 2>&1
printf '{"%s":"not an object"}' "$B" > "$S"; printf '{"recorded_at":"x","seven_day_pct":"99","seven_day_resets_at":1e999,"five_hour_pct":null}' > "$H/.claude/identities/$B/last-limits.json"
J="$(sw --availability 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "odd values in the state and reading files do not stop --availability" || no "crashed" "$J"
sw --list >/dev/null 2>&1 && ok "nor --list" || no "--list crashed" ""

echo "== 11b. what a lost or unreadable list does =="
hooks_copy() { ROOTX="$H/root"; mkdir -p "$ROOTX/hooks"; cp -R "$ROOT/hooks/claude-identity" "$ROOTX/hooks/"; cp "$ROOT/hooks/aios-health.py" "$ROOTX/hooks/" 2>/dev/null; XACC="$ROOTX/hooks/claude-identity/_accounts.py"; XWATCH="$ROOTX/hooks/claude-identity/_watch.py"; XSH="$ROOTX/hooks/claude-identity/claude-identity.sh"; }
sandbox; hooks_copy; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"; capture "$C" "$DAY"
printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n3. `%s`\n' "$A" "$B" "$C" > "$ROOTX/USER.md"
env_run $PY "$XACC" rotation >/dev/null
env_run $PY "$XACC" disable "$B" --current "$A" >/dev/null
rm -f "$H/.aios/accounts.json"
out="$(env_run $PY "$XACC" rotation)"
[ -z "$out" ] && [ ! -f "$H/.aios/accounts.json" ] && ok "a lost list is not revived from USER.md's older section" || no "revived" "$out"
env_run $PY "$XWATCH" "$XSH" >/dev/null 2>&1
[ "$(field "$H/.aios/health/quota-watch.json" 'd["state"]')" = fail ] && ok "and health says so" || no "stayed quiet" "$(cat "$H/.aios/health/quota-watch.json")"

sandbox; hooks_copy
printf '## Anthropic accounts\n\n1. `%s`\n2. %s — no backticks\n\n## Next\n' "$A" "$B" > "$ROOTX/USER.md"
out="$(env_run $PY "$XACC" rotation 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "a line that cannot be read stops the import, and names it" "$B" "$out" || no "imported part of a list" "$out"
[ ! -f "$H/.aios/accounts.json" ] && ok "and nothing is written" || no "wrote a partial list" ""
printf '## Anthropic accounts\n\n1. `%s`\n2. ~~`%s`~~ retired\n' "$A" "$B" > "$ROOTX/USER.md"
out="$(env_run $PY "$XACC" rotation 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "$A" ] && ok "a struck-through line is a retired account, not an unreadable one" || no "stopped on a retired line" "$out"
rm -f "$H/.aios/accounts.json" "$H/.aios/accounts-log.jsonl"
printf '## Anthropic accounts\n\n1. `nobody`\n2. `%s`\n' "$A" > "$ROOTX/USER.md"
out="$(env_run $PY "$XACC" rotation 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -f "$H/.aios/accounts.json" ] && ok "a list that fails validation is not written" || no "wrote an invalid list" "$out"

notifier() { for n in osascript notify-send; do printf '#!/bin/sh\necho x >> "%s/notified"\n' "$H" > "$H/bin/$n"; chmod +x "$H/bin/$n"; done; }
notified() { [ -f "$H/notified" ] && grep -c x "$H/notified" || echo 0; }
sandbox; three; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "-$DAY"; capture "$C" "$DAY"; notifier
AIOS_QUOTA_NOTIFY=1 env_run $PY "$WATCH" "$SH" >/dev/null 2>&1; AIOS_QUOTA_NOTIFY=1 env_run $PY "$WATCH" "$SH" >/dev/null 2>&1
[ "$(notified)" = 1 ] && ok "a broken next fallback notifies once across ticks" || no "notified $(notified) times" ""
sandbox; list_file '{"version":1,'; seat "$A" "$DAY"; notifier
AIOS_QUOTA_NOTIFY=1 env_run $PY "$WATCH" "$SH" >/dev/null 2>&1; AIOS_QUOTA_NOTIFY=1 env_run $PY "$WATCH" "$SH" >/dev/null 2>&1
[ "$(notified)" = 1 ] && ok "a malformed list notifies too, once" || no "notified $(notified) times" ""

echo "== 11c. the commands' edges =="
sandbox; list_file "{\"version\":1,\"accounts\":[{\"email\":\"$A\"},{\"email\":\"$B\"}]}"; seat "$A" "$DAY"; capture "$A" "$DAY"; capture "$B" "$DAY"
sw --disable "$A" >/dev/null 2>&1
has "disabling the active account of two leaves a destination" "$B|" "$(pick "$A")"
[ "$(acc next "$A" 2>/dev/null)" = "$B" ] && ok "and a bare rotation finds it" || no "no destination" ""
sw "$B" >/dev/null 2>&1
out="$(sw 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && has "alone in rotation, a bare rotation says so" "no account to rotate to" "$out" || no "rotated to nothing" "$out"
snap="$(cat "$H/.aios/accounts.json")"
out="$(sw --add nope 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$H/.aios/accounts.json")" = "$snap" ] && ok "--add with no real email is refused, and nothing written" || no "wrote an invalid list" "$out"
for bad in -x a,b; do
  out="$(sw --add "new-$bad@example.com" --alias "$bad" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && [ "$(cat "$H/.aios/accounts.json")" = "$snap" ] && ok "alias [$bad] is refused" || no "alias [$bad] accepted" "$out"
done
[ "$(acc resolve unlisted@example.com)" = "unlisted@example.com" ] && ok "a captured account not in the list can still be switched to by email" || no "refused" ""

echo "== 12. what ships =="
hasnt "the example file parses as a valid list" "error" "$(AIOS_ACCOUNTS_FILE="$ROOT/hooks/claude-identity/accounts.example.json" $PY "$ACC" rotation 2>&1)"
[ -z "$(cd "$ROOT" && git check-ignore hooks/claude-identity/_accounts.py 2>/dev/null)" ] && ok "_accounts.py is not git-ignored" || no "ignored" ""
grep -q 'claude-switch()' "$ROOT/hooks/claude-identity/install-wrappers.sh" && ok "install-wrappers.sh defines claude-switch" || no "missing" ""
grep -q 'function claude-switch' "$ROOT/hooks/claude-identity/install-wrappers.ps1" && ok "install-wrappers.ps1 defines claude-switch" || no "missing" ""

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

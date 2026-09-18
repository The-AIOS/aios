#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# With several accounts, the watcher is only as good as its answer to "whose
# numbers are these?", and the files it shares with every session must never
# be read half-written.
#
# WHY. Both failures are silent. A sample of account A taken before an A->B swap
# is still inside the cache's freshness window when the cooldown ends, so it can
# rotate B away for A's cap; recorded during the cooldown, it files A's usage
# under B. And two sessions writing the same file through one fixed temp name
# can publish a torn JSON -- which headroom() reads as "no state, assume fresh",
# turning a capped account into a rotation target.
#
# Runs the SHIPPED modules against a scratch config dir; nothing touches the
# operator's own ~/.claude, and no rotation can run (no second captured account).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
W="$(cd hooks/claude-identity && pwd)/_watch.py"
[ -f "$W" ] || { echo "::error::$W missing"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
A=a@example.com; B=b@example.com

# Seat = $1; cache = sample of $2 at 50% captured $3 seconds ago; optional
# swap-log row $4 seconds ago. Then run one watcher tick.
tick() {
  rm -rf "$TMP/cfg"; mkdir -p "$TMP/cfg"
  printf '{"oauthAccount":{"emailAddress":"%s"}}' "$1" > "$TMP/cfg/.claude.json"
  printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$A" "$B" > "$TMP/USER.md"
  python3 -c 'import json,sys,time;json.dump({"email":sys.argv[2],"captured_at":int(time.time())-int(sys.argv[3]),"five_hour_pct":50,"seven_day_pct":1},open(sys.argv[1],"w"))' \
    "$TMP/cfg/rate-limit-cache.json" "$2" "$3"
  [ -z "${4:-}" ] || python3 -c 'import json,sys,time;open(sys.argv[1],"w").write(json.dumps({"ts":int(time.time())-int(sys.argv[2]),"action":"rotate","rc":0,"reason":"5h at 99%","five_hour_pct":99})+"\n")' \
    "$TMP/cfg/swap-log.jsonl" "$4"
  HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" python3 "$W" /nonexistent/claude-identity.sh
}
recorded() { [ -f "$TMP/cfg/identities/$1/last-limits.json" ]; }
logged() { grep -q "$1" "$TMP/cfg/quota-watch.log" 2>/dev/null; }

echo "-- 1. a sample speaks only for the seat it was taken on --"
tick "$A" "$A" 5
recorded "$A" && ok "control: a current sample of the seat is recorded" \
  || no "control failed: the seat's own sample was not recorded" "without it the checks below prove nothing"
tick "$B" "$A" 5
! recorded "$A" && ! recorded "$B" && logged "sample predates the last switch" \
  && ok "a sample naming another account than the seat is skipped" \
  || no "a sample of A was acted on while the seat is B" "after a swap -- manual ones included -- A's numbers would decide about B"

echo "-- 2. a sample older than the last swap is skipped, even when the email matches (A->B->A) --"
tick "$A" "$A" 1200 600
! recorded "$A" && logged "predates the last swap" && ok "pre-swap sample skipped" \
  || no "a pre-swap sample was acted on" "it is still inside the 30-min freshness window when the 15-min cooldown ends"

echo "-- 3. inside the cooldown nothing is recorded: the sample may carry the previous account's numbers --"
tick "$A" "$A" 5 60
! recorded "$A" && logged "cooldown active" && ok "cooldown tick records nothing" \
  || no "a cooldown sample was recorded" "it would file one account's usage under the other"
tick "$A" "$A" 5 1200
recorded "$A" && ok "after the cooldown, samples are recorded again" || no "post-cooldown sample not recorded"

echo "-- 4. concurrent writers never publish a torn file --"
# Writer A is mid-write when writer B writes the same destination end to end.
# With one fixed temp name B truncates A's temp, publishes it, and A goes on
# writing into what is now the live file; A's rename then fails.
r=$(CLAUDE_CONFIG_DIR="$TMP/cfg" python3 -c '
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
dst = os.path.join(sys.argv[2], "shared.json")
real_dump = json.dump
state = {"nested": False}
def dump(obj, f, **k):
    if obj.get("who") == "A" and not state["nested"]:
        state["nested"] = True
        m.write_json_atomic(dst, {"who": "B", "pad": "x" * 200})
        print("B-sees", json.load(open(dst))["who"])
    real_dump(obj, f, **k)
m.json.dump = dump
try:
    m.write_json_atomic(dst, {"who": "A"})
    print("final", json.load(open(dst))["who"], oct(os.stat(dst).st_mode & 0o777))
except Exception as e:
    print("error", type(e).__name__)
print("temps", len([n for n in os.listdir(sys.argv[2]) if n.endswith(".tmp")]))
' "$W" "$TMP" 2>&1 | tr '\n' ' ')
case "$r" in
  *"B-sees B"*"final A 0o600"*"temps 0"*) ok "both writers publish whole files, 0600, no temp left behind" ;;
  *) no "interleaved writers → '$r'" "want: B's file readable while A writes, A's file final, mode 0600, no stray temp" ;;
esac

echo "-- 5. the watcher only swaps through a switch that can refuse, and a refusal is not a swap --"
# A stub stands in for claude-identity.sh: it records its call and answers as told.
stub_tick() {  # $1 = stub stdout, $2 = stub exit code
  rm -rf "$TMP/cfg"; mkdir -p "$TMP/cfg/identities/$B"
  for f in keychain.json oauthAccount.json userID.txt; do echo '{}' > "$TMP/cfg/identities/$B/$f"; done
  printf '{"oauthAccount":{"emailAddress":"%s"}}' "$A" > "$TMP/cfg/.claude.json"
  printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$A" "$B" > "$TMP/USER.md"
  python3 -c 'import json,sys,time;json.dump({"email":sys.argv[2],"captured_at":int(time.time()),"five_hour_pct":99,"seven_day_pct":1},open(sys.argv[1],"w"))' \
    "$TMP/cfg/rate-limit-cache.json" "$A"
  printf '#!/bin/sh\necho "$AIOS_SWITCH_EXPECT_FROM $*" >> "%s/calls"\necho "%s"\nexit %s\n' "$TMP" "$1" "$2" > "$TMP/stub.sh"
  chmod +x "$TMP/stub.sh"; rm -f "$TMP/calls"
  HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" python3 "$W" "$TMP/stub.sh"
}
stub_tick "✓ switched to $B" 0
grep -q "^$A switch $B$" "$TMP/calls" 2>/dev/null && ok "the watcher tells switch which seat its decision was about" \
  || no "switch called as '$(cat "$TMP/calls" 2>/dev/null)'" "without AIOS_SWITCH_EXPECT_FROM a late switch rotates a seat that already moved"
stub_tick "another account switch is in progress — nothing changed" 75
[ ! -s "$TMP/cfg/swap-log.jsonl" ] && logged "another switch is in progress" && ok "a busy/moved seat (75) writes no swap row" \
  || no "a refused switch was logged as a swap" "a row would arm or reset the cooldown for a swap that never happened"
stub_tick "already on $B" 0
[ ! -s "$TMP/cfg/swap-log.jsonl" ] && logged "no swap happened" && ok "'already on' is not a swap" \
  || no "'already on' was logged as a swap" "it re-arms the cooldown and notifies a swap that never happened"

echo "-- 6. two switches never overlap on the seat --"
# File backend (a uname shim), so no Keychain is involved. The holder blocks
# INSIDE its critical section -- on its first read of the live credential --
# through a `cat` shim and two FIFOs, so the interleaving is forced, not timed.
# Every wait has a deadline: a broken lock must FAIL this test, never hang it.
I="$(cd hooks/claude-identity && pwd)/claude-identity.sh"
S="$TMP/sw"
deadline() {  # deadline <secs> <cmd...>: run cmd, kill it after <secs>; rc 124 on timeout
  local secs=$1; shift
  "$@" & local p=$!
  # `trap - EXIT`: a killed subshell runs the EXIT trap it inherited, which
  # here is `rm -rf "$TMP"` -- the watchdog would delete the test's own fixture.
  ( trap - EXIT; for _ in $(seq 1 "$secs"); do kill -0 "$p" 2>/dev/null || exit 0; sleep 1; done; kill -9 "$p" 2>/dev/null ) &
  local w=$!
  wait "$p"; local rc=$?
  wait "$w" 2>/dev/null   # never kill it: a subshell killed before its `trap - EXIT` runs the inherited rm -rf
  [ "$rc" -ge 128 ] && return 124 || return "$rc"
}
fixture() {  # seat A with its credential; B captured
  rm -rf "$S"; mkdir -p "$S/bin" "$S/cfg/identities/$B"
  printf '#!/bin/sh\necho Linux\n' > "$S/bin/uname"
  cat > "$S/bin/cat" <<'SHIM'
#!/bin/sh
if [ -n "${BLOCK_ON:-}" ] && [ "${1:-}" = "$BLOCK_ON" ] && [ ! -e "$READY.done" ]; then
  : > "$READY.done"                        # block on the FIRST read only
  echo in > "$READY"; read _ < "$GO"
fi
exec /bin/cat "$@"
SHIM
  chmod +x "$S/bin/uname" "$S/bin/cat"
  printf '{"oauthAccount":{"emailAddress":"%s"},"userID":"uid-a"}' "$A" > "$S/cfg/.claude.json"
  printf '{"claudeAiOauth":{"accessToken":"tok-a"}}' > "$S/cfg/.credentials.json"
  printf '{"claudeAiOauth":{"accessToken":"tok-b"}}' > "$S/cfg/identities/$B/keychain.json"
  printf '{"emailAddress":"%s"}' "$B" > "$S/cfg/identities/$B/oauthAccount.json"
  echo uid-b > "$S/cfg/identities/$B/userID.txt"
  printf '## Anthropic accounts\n\n1. `%s`\n2. `%s`\n' "$A" "$B" > "$S/USER.md"
  mkfifo "$S/ready" "$S/go"
}
sw() { PATH="$S/bin:$PATH" HOME="$S" CLAUDE_CONFIG_DIR="$S/cfg" USER_MD_PATH="$S/USER.md" bash "$I" switch "$@"; }
readfifo() { read _ < "$1"; }
writefifo() { echo go > "$1"; }
contend() {  # contend <label> <switch args...>: a holder is parked inside the lock; the contender must be refused
  local label=$1; shift
  fixture
  BLOCK_ON="$S/cfg/.credentials.json" READY="$S/ready" GO="$S/go" sw "$B" > "$S/holder.out" 2>&1 &
  local holder=$!
  if ! deadline 20 readfifo "$S/ready"; then
    kill -9 "$holder" 2>/dev/null; no "$label: the holder never reached the lock" "$(cat "$S/holder.out")"; return 1
  fi
  deadline 20 sw "$@" > "$S/contender.out" 2>&1; local rc=$?
  [ "$rc" = 75 ] && ok "$label is refused while a swap runs (75)" \
    || no "$label during a swap → exit $rc" "$(cat "$S/contender.out")"
  deadline 20 writefifo "$S/go"
  ( trap - EXIT; for _ in $(seq 1 20); do kill -0 "$holder" 2>/dev/null || exit 0; sleep 1; done; kill -9 "$holder" 2>/dev/null ) &
  local watchdog=$!
  wait "$holder"; local hrc=$?
  wait "$watchdog" 2>/dev/null
  [ "$hrc" = 0 ] && ok "$label: the holder completes" || no "$label: holder → exit $hrc" "$(cat "$S/holder.out")"
}
contend "a second switch" "$B"
grep -q tok-a "$S/cfg/identities/$A/keychain.json" 2>/dev/null && ok "A's saved credential is still A's" \
  || no "A's saved credential was overwritten" "the outgoing account's own credential is gone -- the failure this lock exists for"
grep -q tok-b "$S/cfg/.credentials.json" && ok "the seat holds B" || no "seat does not hold B"
contend "a capture" --capture
grep -q tok-a "$S/cfg/identities/$A/keychain.json" 2>/dev/null && ok "the capture did not save B's credential as A's" \
  || no "a capture during a swap saved B's credential as A's"

echo "-- 7. a decision made on an older seat is refused, even when the email matches again --"
fixture
gen() { cat "$S/cfg/.switch.gen" 2>/dev/null || echo 0; }
g0=$(gen)
deadline 20 sw "$B" > /dev/null 2>&1 && [ "$(gen)" = $((g0 + 1)) ] && ok "a completed swap bumps the seat generation" \
  || no "generation after a swap: '$(gen)' (was $g0)"
deadline 20 sw "$A" > /dev/null 2>&1                       # A -> B -> A: the email reads A again
AIOS_SWITCH_EXPECT_FROM="$A" AIOS_SWITCH_EXPECT_GEN="$g0" deadline 20 sw "$B" > "$S/late.out" 2>&1; rc=$?
[ "$rc" = 75 ] && grep -q tok-a "$S/cfg/.credentials.json" && ok "a switch decided before A->B->A is refused" \
  || no "stale decision → exit $rc" "the email matches, so only the generation can tell the decision is old"
AIOS_SWITCH_EXPECT_FROM="$B" deadline 20 sw "$B" > /dev/null 2>&1; rc=$?
[ "$rc" = 75 ] && ok "a switch decided for another seat is refused" || no "wrong-seat decision → exit $rc"
deadline 20 sw "$A" > /dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "the lock is free once every holder has exited" || no "lock still held → exit $rc"

echo "-- 8. a swap that dies between its two writes is finished safely --"
fixture
AIOS_TEST_CRASH_AFTER_CRED=1 deadline 20 sw "$B" > /dev/null 2>&1
[ -e "$S/cfg/.switch.pending" ] && grep -q tok-b "$S/cfg/.credentials.json" && grep -q "$A" "$S/cfg/.claude.json" \
  && ok "control: the crash left B's credential under A's metadata, and a pending marker" \
  || no "control: the crash did not leave the expected torn seat" "without it the checks below prove nothing"
deadline 20 sw --capture > "$S/cap.out" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q tok-a "$S/cfg/identities/$A/keychain.json" && ok "--capture refuses while a swap is pending" \
  || no "--capture during a pending swap → exit $rc" "it would save B's credential as A's"
deadline 20 sw "$B" > "$S/fin.out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$S/cfg/.switch.pending" ] && grep -q "$B" "$S/cfg/.claude.json" && grep -q tok-a "$S/cfg/identities/$A/keychain.json" \
  && ok "the next switch finishes the job without capturing the half-written seat as A" \
  || no "finishing the interrupted swap → exit $rc" "$(cat "$S/fin.out")"

echo "-- 9. a metadata write that fails AFTER landing keeps the swap --"
fixture
AIOS_TEST_FAIL_AFTER_PUBLISH=1 deadline 20 sw "$B" > "$S/pub.out" 2>&1
grep -q tok-b "$S/cfg/.credentials.json" && grep -q "$B" "$S/cfg/.claude.json" && [ ! -e "$S/cfg/.switch.pending" ] \
  && ok "credential and metadata agree on B" \
  || no "the swap was half rolled back" "rolling the credential back under published metadata creates the mix: $(cat "$S/pub.out")"

echo "-- 10. a cache sample carries the seat generation it was taken under --"
rm -rf "$TMP/gen"; mkdir -p "$TMP/gen/cfg"
printf '{"oauthAccount":{"emailAddress":"%s"}}' "$A" > "$TMP/gen/cfg/.claude.json"
date +%s > "$TMP/gen/cfg/watch-tick"
GENFILE=$(HOME="$TMP/gen" CLAUDE_CONFIG_DIR="$TMP/gen/cfg" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _fs; print(_fs.seat_state_base() + ".gen")' "$(dirname "$W")")
mkdir -p "$(dirname "$GENFILE")"; echo 7 > "$GENFILE"
printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":1}}}' \
  | env -u CLAUDE_CODE_OAUTH_TOKEN HOME="$TMP/gen" CLAUDE_CONFIG_DIR="$TMP/gen/cfg" python3 "$(dirname "$W")/_cache.py"
g=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("seat_gen"))' "$TMP/gen/cfg/rate-limit-cache.json" 2>/dev/null)
[ "$g" = 7 ] && ok "the sample records the generation it was taken under" \
  || no "sample seat_gen = '$g' (want 7)" "without it the watcher cannot tell a sample that straddled a swap"
case "$GENFILE" in "$TMP"/*) ;; *) no "the generation file resolved outside the fixture: $GENFILE" ;; esac

echo "-- 11. the watcher discards a sample from another seat generation, or when the seat is unreadable --"
tick "$A" "$A" 5
recorded "$A" && ok "control: a current-generation sample is recorded" || no "control failed"
tick "$A" "$A" 5; rm -rf "$TMP/cfg/identities"
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["seat_gen"]=41;json.dump(d,open(p,"w"))' "$TMP/cfg/rate-limit-cache.json"
HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" python3 "$W" /nonexistent/claude-identity.sh
! recorded "$A" && logged "seat generation 41" && ok "a sample from another generation is skipped" \
  || no "a sample from another seat generation was acted on" "a swap landed while it was being written"
tick "$A" "$A" 5; rm -rf "$TMP/cfg/identities"; rm -f "$TMP/cfg/.claude.json"
HOME="$TMP" CLAUDE_CONFIG_DIR="$TMP/cfg" USER_MD_PATH="$TMP/USER.md" python3 "$W" /nonexistent/claude-identity.sh
! recorded "$A" && logged "seat unreadable" && ok "no readable seat → no decision" \
  || no "the watcher acted without knowing the seat"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

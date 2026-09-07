#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bus-dead-letters.py reports the TWO ways a bus request fails, and never fires
# on the two ways it legitimately waits.
#
# The second shape was added 2026-09-07 and is the one nothing else can see: a
# request nobody ever CLAIMED. Retirement to `.undelivered` needs a surface to
# perform it, and a surface that quit performs nothing — so a plain `*.json` sits
# there forever, unreported by every check that only reads `.undelivered`.
# Measured that day: a request addressed to a surface whose pid had been dead
# three weeks sat completely invisible, while an identical one addressed to the
# live surface was picked up in ~1s.
#
# THE FALSE-POSITIVE HALF IS THE POINT, and it gets a control each. This check
# reads a directory the protocol writes to constantly, so a version that flags a
# fresh request (~1s of normal life) or a `.holding` file (a claimed request
# legitimately waiting out HOLD_STALE_MS, 45 min) would fire on healthy state
# every run — and `close-day.md` already warns in writing that a check which
# always fires is a check the operator stops reading. The `.holding` rename is
# precisely what makes reporting safe, so both controls assert SILENCE.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
S=hooks/bus-dead-letters.py
[ -f "$S" ] || { echo "::error::$S missing"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: no python3 (the commands that call this require it too). NOT a pass."; exit 0; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
run(){ python3 "$S" "$1" 2>&1; }
old(){ touch -t 202001010900 "$1"; }   # comfortably past the grace period

echo "-- an empty inbox is silent, at exit 0 --"
mkdir -p "$T/empty"
out=$(run "$T/empty"); rc=$?
[ "$out" = "bus-dead-letters: none" ] && ok "empty → the exact contracted line" || no "empty printed '$out'"
[ "$rc" = "0" ] && ok "exit 0 (finding nothing is not a failure)" || no "exit $rc on an empty inbox"

echo "-- an inbox that does not exist is silent too, not an error --"
out=$(run "$T/does-not-exist"); rc=$?
[ "$rc" = "0" ] && ok "missing inbox → exit 0" || no "missing inbox exited $rc" "a plain clone with no surface has no inbox; that is normal, not broken"
case "$out" in *none*) ok "missing inbox → 'none'" ;; *) no "missing inbox printed '$out'" ;; esac

echo "-- CONTROL: a FRESH request must not be flagged --"
mkdir -p "$T/fresh"; echo '{"name":"justwritten","task":"x"}' > "$T/fresh/justwritten.json"
out=$(run "$T/fresh")
case "$out" in *unclaimed*) no "a request written seconds ago was flagged" "pickup takes ~1s; flagging that makes this fire on healthy state every run" ;; *) ok "fresh request → silent" ;; esac

echo "-- CONTROL: a claimed request WAITING (.holding) must not be flagged, however old --"
mkdir -p "$T/held"; echo '{"name":"held","task":"x"}' > "$T/held/held.json.holding"; old "$T/held/held.json.holding"
out=$(run "$T/held")
case "$out" in *unclaimed*|*dead-letter:*) no "a .holding file was flagged" "that is a live wait (up to HOLD_STALE_MS 45m) — flagging it condemns healthy protocol state" ;; *) ok ".holding → silent" ;; esac

echo "-- the real case: an unclaimed request past the grace period --"
mkdir -p "$T/stuck"; echo '{"name":"stuck","task":"x","surface":"glass"}' > "$T/stuck/stuck.json"; old "$T/stuck/stuck.json"
out=$(run "$T/stuck")
case "$out" in *"bus-unclaimed:"*) ok "unclaimed request is reported" ;; *) no "unclaimed request NOT reported: '$out'" "this is the shape nothing else in the framework can see" ;; esac
case "$out" in *to=stuck*)  ok "names the target" ;; *) no "does not name the target" ;; esac
case "$out" in *age=*)      ok "carries an age (so the operator can judge it)" ;; *) no "no age reported" ;; esac

echo "-- a send verb is distinguished from a spawn --"
mkdir -p "$T/verb"; echo '{"action":"send","name":"peer","prompt":"hi"}' > "$T/verb/peer.json"; old "$T/verb/peer.json"
out=$(run "$T/verb")
case "$out" in *action=send*) ok "action=send reported as such" ;; *) no "send not distinguished: '$out'" "re-dropping a send and a spawn are different decisions" ;; esac

echo "-- both shapes coexist, and neither hides the other --"
mkdir -p "$T/both"
echo '{"name":"stuck2","task":"x"}' > "$T/both/stuck2.json"; old "$T/both/stuck2.json"
echo '{"name":"dead","_undelivered":{"reason":"target absent","at":"11:00"}}' > "$T/both/dead.json.undelivered"
out=$(run "$T/both")
case "$out" in *"bus-unclaimed:"*) ok "unclaimed still reported alongside a dead letter" ;; *) no "unclaimed line lost when a dead letter is present" ;; esac
case "$out" in *"bus-dead-letter:"*) ok "dead letter still reported alongside an unclaimed one" ;; *) no "dead-letter line lost when an unclaimed one is present" ;; esac
case "$out" in *none*) no "'none' printed while anomalies exist" "the contract's silence line must never appear with findings" ;; *) ok "no 'none' line when there are findings" ;; esac

echo "-- an unreadable file is reported BY NAME, never skipped --"
mkdir -p "$T/bad"; printf 'not json at all' > "$T/bad/broken.json"; old "$T/bad/broken.json"
out=$(run "$T/bad"); rc=$?
case "$out" in *broken.json*) ok "unreadable file named" ;; *) no "unreadable file not named: '$out'" "a request you cannot parse is still a task owed" ;; esac
case "$out" in *unreadable*) ok "carries the parse reason" ;; *) no "no reason given for the unreadable file" ;; esac
[ "$rc" = "0" ] && ok "still exit 0 on an unreadable file" || no "exit $rc" "the callers treat non-zero as a broken command, not as findings"

echo "-- the grace period is a real threshold, not decoration --"
G=$(grep -oE 'UNCLAIMED_AFTER_S = [0-9]+' "$S" | grep -oE '[0-9]+')
[ -n "$G" ] && [ "$G" -ge 60 ] && ok "grace period is ${G}s (well past the ~1s pickup)" || no "grace period is '${G:-unset}'" "under a minute would flag normal pickup latency"
[ -n "$G" ] && [ "$G" -lt 600 ] && ok "grace period is under RETIRE_TTL_MS (600s) — raised before the protocol retires it" || no "grace period ${G:-?}s is not under the 600s retire TTL" "reporting after retirement adds nothing; the point is to catch it first"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

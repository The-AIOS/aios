#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one. Same probe
# hooks/claude-identity/claude-identity.sh and mcps/setup.sh already use.
# $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# bus-dead-letters.py reports the THREE ways a bus request fails, and never fires
# on the ways it legitimately waits.
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
S=hooks/pipeline/bus-dead-letters.py
[ -f "$S" ] || { echo "::error::$S missing"; exit 1; }
[ -n "$PYBIN" ] || { echo "SKIP: no working python (the commands that call this require it too). NOT a pass."; exit 0; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
run(){ $PYBIN "$S" "$1" 2>&1; }
old(){ touch -t 202001010900 "$1"; }   # comfortably past the grace period
# A claim's age is counted from the later of mtime and ctime, and no test can backdate ctime.
# So for the claim cases the SCRIPT'S clock is moved an hour ahead instead (AIOS_BUS_NOW).
later(){ AIOS_BUS_NOW=$(( $(date +%s) + 3600 )) $PYBIN "$S" "$1" 2>&1; }

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

echo "-- THE THIRD SHAPE: a request taken and never published (a claim abandoned half-way) --"
# A surface takes a request by renaming it to `<name>.json.claiming-<surface>-<pid>`, stamps it
# there, and only then publishes it as `.holding`. That private name is neither `*.json` nor
# `*.holding` nor `*.undelivered`, so no check above reads it: a process that dies between those
# renames leaves a request nothing reports, unless a surface that knows the name is running.
DEAD=$($PYBIN -c 'import subprocess,sys; p=subprocess.Popen([sys.executable,"-c","pass"]); p.wait(); print(p.pid)')
LIVE=$($PYBIN -c 'import os; print(os.getppid())')
mkdir -p "$T/claim"
echo '{"action":"send","name":"worker","prompt":"hi"}' > "$T/claim/worker.json.claiming-app-$DEAD"; old "$T/claim/worker.json.claiming-app-$DEAD"
out=$(later "$T/claim"); rc=$?
case "$out" in *"bus-claim-abandoned:"*) ok "an abandoned claim is reported" ;; *) no "abandoned claim NOT reported: '$out'" "no other check reads this name; without it the request is lost with nothing said" ;; esac
case "$out" in *to=worker*)        ok "names the target" ;; *) no "does not name the target: '$out'" ;; esac
case "$out" in *action=send*)      ok "names the action" ;; *) no "does not name the action: '$out'" ;; esac
case "$out" in *age=*)             ok "carries an age" ;; *) no "no age reported: '$out'" ;; esac
case "$out" in *"claimer=app:$DEAD"*) ok "names the surface and pid that took it" ;; *) no "does not name the claimer: '$out'" ;; esac
case "$out" in *none*) no "'none' printed while an abandoned claim exists" ;; *) ok "no 'none' line when there is an abandoned claim" ;; esac
[ "$rc" = "0" ] && ok "still exit 0" || no "exit $rc on an abandoned claim"
case "$out" in *"(gone)"*) ok "a claimer that has exited is reported as gone" ;; *) no "dead pid $DEAD not reported as gone: '$out'" ;; esac
echo '{"name":"paused","task":"x"}' > "$T/claim/paused.json.claiming-glass-$LIVE"; old "$T/claim/paused.json.claiming-glass-$LIVE"
out=$(later "$T/claim")
case "$out" in *"claimer=glass:$LIVE (still running)"*) ok "a claim whose pid is alive is still reported, and says the pid is running" ;; *) no "live pid $LIVE: '$out'" "a paused claimer or a reused pid leaves the request waiting with no limit; ten minutes of that is worth saying" ;; esac
# The probe must deliver nothing. On Windows `os.kill(pid, 0)` terminates the process, so the
# script goes through the framework's one side-effect-free check; this is what would notice.
$PYBIN -c "import sys; sys.path.insert(0,'hooks/claude-identity'); from _fs import pid_alive; sys.exit(0 if pid_alive($LIVE) else 1)" \
  && ok "the probed process is still alive after being probed" || no "the process that was probed is gone" "the liveness probe must deliver nothing"
grep -q 'os\.kill' "$S" && no "$S calls os.kill" "on Windows signal 0 terminates the process; liveness goes through claude-identity/_fs.py" || ok "the script never calls os.kill itself"

echo "-- CONTROL: a claim in progress must not be flagged --"
# A claim is three filesystem calls. One caught mid-way is healthy state, however old the REQUEST
# was when it was taken: a rename keeps the request's mtime, so age is counted from the rename.
mkdir -p "$T/claimfresh"
echo '{"name":"midclaim","task":"x"}' > "$T/claimfresh/midclaim.json.claiming-app-$DEAD"
out=$(run "$T/claimfresh")
case "$out" in *claim-abandoned*) no "a claim written seconds ago was flagged" ;; *) ok "a fresh claim → silent" ;; esac
out=$(AIOS_BUS_NOW=$(( $(date +%s) + 3600 )) $PYBIN "$S" "$T/claimfresh" 2>&1)
case "$out" in *claim-abandoned*) ok "and the same claim an hour later IS reported: the silence above was the grace, not a blind spot" ;; *) no "the control proves nothing: the same file an hour later is still silent: '$out'" ;; esac
echo '{"name":"waited","task":"x"}' > "$T/claimfresh/waited.json"; old "$T/claimfresh/waited.json"
mv "$T/claimfresh/waited.json" "$T/claimfresh/waited.json.claiming-app-$DEAD"
if [ "$($PYBIN -c 'import os; print(os.name)')" = "nt" ]; then
  ok "Windows: no rename time is kept by the filesystem API this script can read; skipped, stated"
else
  out=$(run "$T/claimfresh")
  case "$out" in *claim-abandoned*) no "a request that waited long and was JUST taken was flagged" "its mtime is old, its rename is seconds old: age must come from the later of the two" ;; *) ok "an old request taken a moment ago → silent" ;; esac
fi

echo "-- CONTROL: only a request name is a claim --"
mkdir -p "$T/notclaim"
echo 'x' > "$T/notclaim/notes.claiming-app-1";            old "$T/notclaim/notes.claiming-app-1"
echo 'x' > "$T/notclaim/w.json.claiming-app-notapid";      old "$T/notclaim/w.json.claiming-app-notapid"
echo 'x' > "$T/notclaim/w.json.claiming-";                 old "$T/notclaim/w.json.claiming-"
out=$(later "$T/notclaim")
[ "$out" = "bus-dead-letters: none" ] && ok "names that are not <request>.json.claiming-<surface>-<pid> are ignored" || no "a non-claim name was reported: '$out'"

echo "-- an abandoned claim that cannot be read is reported BY NAME --"
mkdir -p "$T/claimbad"; printf '{"name":"half' > "$T/claimbad/half.json.claiming-app-$DEAD"; old "$T/claimbad/half.json.claiming-app-$DEAD"
out=$(later "$T/claimbad")
case "$out" in *"half.json.claiming-app-$DEAD"*unreadable*) ok "unreadable claim named, with the reason" ;; *) no "unreadable claim: '$out'" ;; esac

echo "-- the three shapes coexist, and the script only reads --"
mkdir -p "$T/all"
echo '{"name":"stuck3","task":"x"}' > "$T/all/stuck3.json"; old "$T/all/stuck3.json"
echo '{"name":"dead3","_undelivered":{"reason":"target absent","at":"11:00"}}' > "$T/all/dead3.json.undelivered"
echo '{"name":"taken3","task":"x"}' > "$T/all/taken3.json.claiming-app-$DEAD"; old "$T/all/taken3.json.claiming-app-$DEAD"
before=$(ls -1 "$T/all" | sort | tr '\n' ' ')
out=$(later "$T/all")
for want in "bus-unclaimed:" "bus-dead-letter:" "bus-claim-abandoned:"; do
  case "$out" in *"$want"*) ok "reports $want beside the other two" ;; *) no "$want lost when the other shapes are present: '$out'" ;; esac
done
[ "$(ls -1 "$T/all" | sort | tr '\n' ' ')" = "$before" ] && ok "nothing was moved, renamed or deleted" || no "the inbox changed: $(ls -1 "$T/all" | tr '\n' ' ')" "putting a claim back is the surfaces' job; a paused claimer would then fulfil it twice"

echo "-- the claim grace is longer than a surface's own recovery pass --"
C=$(grep -oE '^CLAIMING_AFTER_S = [0-9]+' "$S" | grep -oE '[0-9]+')
[ -n "$C" ] && [ "$C" -gt 300 ] && ok "claim grace is ${C}s, past the 300s on which a surface restores an abandoned claim itself" || no "claim grace is '${C:-unset}'" "at 300s or under, this reports what a running surface is about to fix"

echo "-- both commands tell the session what an abandoned claim is --"
for f in plugins/aios/commands/today.md plugins/aios/commands/close-day.md; do
  grep -q 'bus-claim-abandoned:' "$f" && ok "$f handles the bus-claim-abandoned line" || no "$f does not mention bus-claim-abandoned" "the script would print a line the command gives no meaning to"
  grep 'bus-claim-abandoned:' "$f" | grep -qi 'never rename' && ok "$f says when the file must never be renamed back" || no "$f does not warn against renaming the claim back" "a paused claimer that resumes would fulfil the request a second time"
  grep 'bus-claim-abandoned:' "$f" | grep -q '(gone)' && grep 'bus-claim-abandoned:' "$f" | grep -q 'still running' && ok "$f tells the gone claimer from the running one" || no "$f does not distinguish (gone) from (still running)" "re-dropping is only safe when the claimer is gone"
done

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

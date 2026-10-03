#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi
if ! $PYBIN -c 'import fcntl' >/dev/null 2>&1; then
  echo "SKIP: no fcntl (POSIX-only lock path)" >&2
  exit 0
fi

# tests/rc-reconnect.test.sh
#
# Guards hooks/claude-identity/rc-reconnect + _watch.py's account-change trigger.
#
# WHAT THIS IS PROTECTING
# -----------------------
# Changing the active Anthropic account can drop Remote Control across every live
# session. Nothing errors — the sessions keep running, their argv still says
# `--remote-control`, and they simply stop being reachable. The operator finds
# out by trying. So the failure this guards is a SILENT one, which is exactly the
# kind a test has to hold, because nothing else will report it.
#
# Two properties are load-bearing and neither is visible by reading the diff:
#
#   1. REFUSE WITH NO LIVE SURFACE. The spawn-inbox directory persists forever
#      once created, so its existence proves nothing. A request written with no
#      fulfiller running is not dead-lettered — it sits unclaimed, and nothing
#      watches for unclaimed. Writing N files nobody reads looks exactly like
#      success, which is why it must be refused rather than attempted.
#
#   2. EXACTLY ONE FAN-OUT PER CHANGE. The statusLine kick and the scheduled run
#      can both observe the same account change, and near a cap the kick tightens
#      to seconds. Without a lock, each observer reads the old state, decides the
#      account changed, and fans out — one reconnect storm per change.
#
# THE CONTROL IS THE POINT.
# The concurrency case ships with an UNLOCKED control that must produce more than
# one fan-out. Without it, a passing locked run proves nothing: it is satisfied
# just as well by a race that never occurred. The control removes the lock and
# slows `os.read`, which opens the window at precisely the
# point the lock was protecting — between reading the previous account and
# writing the new one. The two variants then differ in one thing only.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/hooks/claude-identity/rc-reconnect"
WATCH="$ROOT/hooks/claude-identity/_watch.py"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$(( pass + 1 )); }
bad() { echo "  FAIL  $1"; fail=$(( fail + 1 )); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 -- expected '$3', got '$2'"; fi; }

FIX="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/aios-rc.$$")"
mkdir -p "$FIX"
cleanup() { rm -rf "$FIX"; }
trap cleanup EXIT

export CLAUDE_CONFIG_DIR="$FIX/cfg"
export AIOS_HOME="$FIX/aios"
export AIOS_QUOTA_NOTIFY=0   # the watcher must never raise a real desktop notification from a test
mkdir -p "$CLAUDE_CONFIG_DIR/sessions" "$AIOS_HOME/spawn-inbox" "$AIOS_HOME/surfaces"

# A session registry entry: $1 name, $2 pid, $3 status, $4 "no" = Remote Control NOT attached
# (attached entries carry bridgeSessionId, as Claude Code writes it while Remote Control is on)
mksession() {
  $PYBIN -c "
import json,sys
d={'name':sys.argv[1],'pid':int(sys.argv[2]),'status':sys.argv[3],'kind':'interactive'}
if sys.argv[5] != 'no': d['bridgeSessionId']='session_'+sys.argv[1]
json.dump(d, open(sys.argv[4],'w'))
" "$1" "$2" "$3" "$CLAUDE_CONFIG_DIR/sessions/$1.json" "${4:-yes}"
}
reqs() { ls "$AIOS_HOME/spawn-inbox"/*.json 2>/dev/null | wc -l | tr -d ' '; }
clear_reqs() { rm -f "$AIOS_HOME/spawn-inbox"/*.json; }

# A pid that is alive for the whole run, and one that is certainly not.
sleep 300 & LIVE_PID=$!
DEAD_PID=$(  $PYBIN -c "print(2**22 - 7)" )

echo "== 1. no live surface: refuse, and write NOTHING =="
mksession "alpha" "$LIVE_PID" "idle"
out=$("$SCRIPT" 2>&1); rc=$?
chk "exits 1" "$rc" "1"
chk "wrote no requests" "$(reqs)" "0"
case "$out" in *UNCLAIMED*) ok "names the unclaimed failure mode" ;; *) bad "does not explain why -- got: $out" ;; esac

echo "== 2. dead surface file is not a live surface =="
$PYBIN -c "
import json,sys; json.dump({'pid':int(sys.argv[1])}, open(sys.argv[2],'w'))
" "$DEAD_PID" "$AIOS_HOME/surfaces/ghost.json"
"$SCRIPT" >/dev/null 2>&1; chk "still exits 1" "$?" "1"
chk "still wrote nothing" "$(reqs)" "0"

echo "== 3. live surface: one request per LIVE session, none for stale entries =="
$PYBIN -c "
import json,sys; json.dump({'pid':int(sys.argv[1])}, open(sys.argv[2],'w'))
" "$$" "$AIOS_HOME/surfaces/app.json"
mksession "beta"  "$LIVE_PID" "busy"
mksession "zombie" "$DEAD_PID" "idle"
"$SCRIPT" >/dev/null 2>&1; chk "exits 0" "$?" "0"
chk "two live sessions -> two requests" "$(reqs)" "2"
got=$(ls "$AIOS_HOME/spawn-inbox"/ | grep -c zombie || true)
chk "no request for the stale registry entry" "$got" "0"
body=$(cat "$(ls "$AIOS_HOME/spawn-inbox"/*.json | head -1)")
case "$body" in *'"action": "send"'*|*'"action":"send"'*) ok "uses the send verb" ;; *) bad "wrong verb -- $body" ;; esac
case "$body" in *"/remote-control"*) ok "carries the slash command" ;; *) bad "missing prompt -- $body" ;; esac

# ── the defect the two assertions above CANNOT see ──────────────────────────
# Run bare, `/remote-control` re-attaches under an AUTO-GENERATED name (the
# prefix defaults to the hostname) instead of inheriting the session's launch
# `--name`. A bare fan-out therefore reconnects every session and leaves them
# mutually indistinguishable — reachable but unidentifiable, which is worse
# than disconnected because it looks like it worked.
#
# Every assertion above passes with the bare form. They check that a request
# was written and that its prompt contains the command: they measure the
# REQUEST, never the EFFECT. Found by hand against a live session, which is
# the only place the difference was visible.
for s in alpha beta; do
  hit=$(grep -l "\"name\": \"$s\"\|\"name\":\"$s\"" "$AIOS_HOME/spawn-inbox"/*.json 2>/dev/null | head -1)
  if [ -z "$hit" ]; then bad "no request addressed to $s"; continue; fi
  case "$(cat "$hit")" in
    *"/remote-control $s"*) ok "$s: prompt carries its OWN name, not the bare command" ;;
    *) bad "$s: prompt bare or naming the wrong session -- $(cat "$hit")" ;;
  esac
done

echo "== 3b. each request names the surface that HOSTS the session =="
# LIVE_PID is a child of this shell, and this shell is the "app" surface's pid.
hit=$(grep -l '"name": "alpha"' "$AIOS_HOME/spawn-inbox"/*.json | head -1)
case "$(cat "$hit")" in *'"surface": "app"'*) ok "a session under the App is routed to the App" ;; *) bad "not routed to its host -- $(cat "$hit")" ;; esac
chk "no half-written temp left in the inbox" "$(ls -a "$AIOS_HOME/spawn-inbox" | grep -c '\.tmp$' || true)" "0"

echo "== 4. --dry-run writes nothing =="
clear_reqs
"$SCRIPT" --dry-run >/dev/null 2>&1
chk "dry-run wrote nothing" "$(reqs)" "0"

echo "== 5. --skip leaves that session alone =="
clear_reqs
"$SCRIPT" --skip alpha >/dev/null 2>&1
chk "skipped one of two" "$(reqs)" "1"

echo "== 5b. a session WITHOUT Remote Control is never exposed by a re-attach =="
clear_reqs
mksession "private" "$LIVE_PID" "idle" no
"$SCRIPT" >/dev/null 2>&1
chk "two attached sessions re-attached, the unattached one left alone" "$(reqs)" "2"
chk "no request for the unattached session" "$(ls "$AIOS_HOME/spawn-inbox"/ | grep -c private || true)" "0"
clear_reqs; "$SCRIPT" --all >/dev/null 2>&1
chk "--all includes it" "$(reqs)" "3"
clear_reqs; "$SCRIPT" --only private,alpha >/dev/null 2>&1
chk "--only sends exactly the named sessions, attached or not" "$(reqs)" "2"
rm -f "$CLAUDE_CONFIG_DIR/sessions/private.json"

echo "== 5c. a session no surface hosts gets no surface field (any surface may take it) =="
clear_reqs
mksession "outside" 1 "idle"
"$SCRIPT" --only outside >/dev/null 2>&1
hit=$(ls "$AIOS_HOME/spawn-inbox"/*.json 2>/dev/null | head -1)
if [ -n "$hit" ] && ! grep -q '"surface"' "$hit"; then ok "unhosted session: request carries no surface"; else bad "unhosted session -- $(cat "$hit" 2>/dev/null)"; fi
rm -f "$CLAUDE_CONFIG_DIR/sessions/outside.json"; clear_reqs

# ── the account-change trigger ──────────────────────────────────────────────
# A stub rc-reconnect that records each invocation, so a fan-out is countable.
# Copy the WHOLE directory, not just _watch.py: it imports its sibling `_fs`,
# and a lone copy dies at import with ModuleNotFoundError. Then overwrite
# rc-reconnect with the counting stub — the point is to count invocations
# without writing real bus requests.
STUBDIR="$FIX/stub"
cp -R "$(dirname "$WATCH")" "$STUBDIR"
cat > "$STUBDIR/rc-reconnect" <<EOF
#!/usr/bin/env bash
echo "fired \$*" >> "$FIX/fired.log"
EOF
chmod +x "$STUBDIR/rc-reconnect"
fired() { [ -f "$FIX/fired.log" ] && wc -l < "$FIX/fired.log" | tr -d ' ' || echo 0; }

set_account() {
  $PYBIN -c "
import json,sys; json.dump({'email':sys.argv[1]}, open(sys.argv[2],'w'))
" "$1" "$CLAUDE_CONFIG_DIR/rate-limit-cache.json"
}
trigger() {
  $PYBIN -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('w', sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.reconnect_if_account_changed(sys.argv[1])
" "$STUBDIR/_watch.py" 2>>"$FIX/trigger.err"
}

echo "== 6. first run ADOPTS the account, does not fan out =="
rm -f "$FIX/fired.log" "$CLAUDE_CONFIG_DIR/rc-reconnect.state"
set_account "one@example.com"
trigger
chk "no fan-out on first sight" "$(fired)" "0"
chk "state recorded" "$(cat "$CLAUDE_CONFIG_DIR/rc-reconnect.state" 2>/dev/null)" "one@example.com"

echo "== 7. same account again is not a change =="
trigger; chk "still no fan-out" "$(fired)" "0"

echo "== 8. a CHANGED account fires exactly once =="
set_account "two@example.com"
trigger; chk "fired" "$(fired)" "1"
case "$(cat "$FIX/fired.log")" in *"--only alpha,beta"*) ok "the watcher passes exactly the attached sessions" ;; *) bad "watcher args -- $(cat "$FIX/fired.log")" ;; esac
trigger; chk "does not re-fire on the next tick" "$(fired)" "1"

echo "== 8b. sessions attached BEFORE the change are re-attached even if the registry no longer says so =="
# The drop may clear bridgeSessionId. The watcher's record from the previous tick is what
# remembers who was attached.
rm -f "$FIX/fired.log"
mksession "alpha" "$LIVE_PID" "idle" no; mksession "beta" "$LIVE_PID" "busy" no
set_account "two-b@example.com"
trigger
case "$(cat "$FIX/fired.log" 2>/dev/null)" in *"--only alpha,beta"*) ok "re-attached from the previous tick's record" ;; *) bad "lost the pre-change set -- $(cat "$FIX/fired.log" 2>/dev/null)" ;; esac

echo "== 8c. nothing was attached: an account change sends nothing =="
rm -f "$FIX/fired.log"
set_account "two-c@example.com"
trigger
chk "no fan-out when no session had Remote Control" "$(fired)" "0"
mksession "alpha" "$LIVE_PID" "idle"; mksession "beta" "$LIVE_PID" "busy"
trigger   # refresh the attached record before the concurrency cases

echo "== 9. CONCURRENCY: one change seen by 8 observers =="
N=8
rm -f "$FIX/fired.log"
$PYBIN -c "
import sys; open(sys.argv[1],'w').write('two@example.com')
" "$CLAUDE_CONFIG_DIR/rc-reconnect.state"
set_account "three@example.com"
# `wait` with no arguments waits for EVERY background job, including the
# long-lived process standing in for a live session pid — which hangs the run.
# Wait on the observers by pid, and only them.
obs=""
for _ in $(seq $N); do trigger & obs="$obs $!"; done
wait $obs
locked=$(fired)
chk "locked: exactly one fan-out from $N observers" "$locked" "1"

echo "== 9b. CONTROL: the same race with the lock removed MUST misbehave =="
# Patching flock to a sleeping no-op removes the lock AND opens the
# read-compare-write window at exactly the point the lock protected. If this
# control ever passes with 1, the test above is certifying a race that is no
# longer reproducible and must be re-examined before it is trusted.
rm -f "$FIX/fired.log"
$PYBIN -c "
import sys; open(sys.argv[1],'w').write('three@example.com')
" "$CLAUDE_CONFIG_DIR/rc-reconnect.state"
set_account "four@example.com"
obs=""
for _ in $(seq $N); do
  $PYBIN -c "
import importlib.util, sys, fcntl, os, time
# Remove the lock, and open the window where it actually was: BETWEEN the read
# of the previous account and the write of the new one. A delay placed before
# the read (the first version of this control) serialises the observers by
# their own start times and reproduces nothing — it reported 1 and would have
# certified the locked case on the strength of a race that never ran.
fcntl.flock = lambda *a, **k: None
_read = os.read
def _slow(fd, n):
    b = _read(fd, n); time.sleep(0.25); return b
os.read = _slow
spec = importlib.util.spec_from_file_location('w', sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
w.reconnect_if_account_changed(sys.argv[1])
" "$STUBDIR/_watch.py" 2>>"$FIX/trigger.err" &
  obs="$obs $!"
done
wait $obs
unlocked=$(fired)
if [ "$unlocked" -gt 1 ]; then
  ok "control: $unlocked fan-outs without the lock (race is real; the lock is what fixes it)"
else
  bad "control produced $unlocked -- the race did not reproduce, so case 9 proves nothing"
fi

kill "$LIVE_PID" 2>/dev/null
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

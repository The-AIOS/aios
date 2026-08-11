#!/usr/bin/env bash
# adoption-detector.test.sh — catch a rotation the live session never picked up.
#
# This guards the one premise the autopilot cannot enforce. Rotating the
# credential is our code; a RUNNING session adopting it is Claude Code's own
# behaviour — it stat()s the credential store on the API request path and purges
# its token caches when mtime changes. Measured, but not a contract we control.
#
# If an upstream change removed it, the failure would be MUTE: the swap succeeds,
# the log says "rotated", and the session keeps burning the capped account until
# it hits the exact wall the autopilot exists to prevent. Nothing would go red.
#
# The signal is cheap: we only rotate to an account with real capacity, so the
# reported percentage MUST fall after a successful swap. Still high minutes
# later means it never landed.
#
# Scenario 4 is the one that keeps this honest in the other direction — a cache
# older than the swap must NOT raise, or the detector fires on every rotation
# before the first post-swap reading even exists.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$ROOT/hooks/claude-identity/_watch.py"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ad-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# swap_at <secs_ago> <pct_before>   — seed a successful rotation in the log
swap_at(){
  python3 - "$WORK/swap-log.jsonl" "$1" "$2" <<'PYEOF'
import json, sys, time
json_row = {"ts": int(time.time()) - int(sys.argv[2]), "action": "rotate", "rc": 0,
            "from": "old@example.com", "five_hour_pct": float(sys.argv[3])}
open(sys.argv[1], "w").write(json.dumps(json_row) + "\n")
PYEOF
}

# run_check <cache_age_secs_ago> <pct_now>
run_check(){
  rm -f "$WORK/rotation-alert.json"
  # PATH without notify-send/osascript so the probe cannot pop a real toast.
  CLAUDE_CONFIG_DIR="$WORK" PATH="/nonexistent" /usr/bin/python3 - "$WATCH" "$1" "$2" <<'PYEOF'
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
cache = {"captured_at": time.time() - float(sys.argv[2]),
         "five_hour_pct": float(sys.argv[3]), "email": "new@example.com"}
w.check_adoption(cache)
PYEOF
}

alert_exists(){ [ -f "$WORK/rotation-alert.json" ]; }

echo "adoption-detector: $WATCH"

# 1. Inside the grace period: too early to judge, must stay quiet.
swap_at 30 99
run_check 5 99
if ! alert_exists; then ok "silent inside the grace period"; else
  no "silent inside the grace period" "alerted before the session could react"; fi

# 2. Past grace, usage fell -> adopted, no alert.
swap_at 300 99
run_check 5 20
if ! alert_exists; then ok "no alert when usage fell after the swap"; else
  no "no alert when usage fell after the swap" "false positive on a healthy rotation"; fi

# 3. Past grace, usage still high -> the session never adopted.
swap_at 300 99
run_check 5 99
if alert_exists && grep -q "did not adopt" "$WORK/rotation-alert.json"; then
  ok "alerts when usage did not fall after the swap"
else
  no "alerts when usage did not fall after the swap" \
     "$( [ -f "$WORK/rotation-alert.json" ] && cat "$WORK/rotation-alert.json" || echo 'no alert file')"; fi

# 4. A cache OLDER than the swap is the pre-swap photo — judging on it would
#    fire on every single rotation before the first fresh reading exists.
swap_at 300 99
run_check 600 99
if ! alert_exists; then ok "ignores a cache older than the swap"; else
  no "ignores a cache older than the swap" "judged on the pre-swap reading"; fi

# 5. Past the window entirely: stop looking rather than alert forever.
swap_at 5000 99
run_check 5 99
if ! alert_exists; then ok "stops looking past the observation window"; else
  no "stops looking past the observation window" "still alerting hours later"; fi

# 6. A recovered rotation must CLEAR a previous alert, not leave a stale one
#    that trains the operator to ignore the file.
swap_at 300 99
run_check 5 99
alert_exists || no "setup for clear-on-recovery" "expected an alert first"
swap_at 300 99
run_check 5 10
if ! alert_exists; then ok "clears a previous alert once a rotation lands"; else
  no "clears a previous alert once a rotation lands" "stale alert survives recovery"; fi

# 7. A `declined` row is not a rotation and must never be judged for adoption.
python3 - "$WORK/swap-log.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps(
    {"ts": int(time.time()) - 300, "action": "declined", "rc": None,
     "five_hour_pct": 99}) + "\n")
PYEOF
run_check 5 99
if ! alert_exists; then ok "a declined rotation is never judged for adoption"; else
  no "a declined rotation is never judged for adoption" "nothing was swapped"; fi

# 8. The alert must survive a missing notifier — on Linux `osascript` does not
#    exist, and the original code swallowed that, dropping every notification.
if grep -q 'notify-send' "$WATCH" && grep -q 'sys.platform == "darwin"' "$WATCH"; then
  ok "notify picks a notifier per platform instead of assuming osascript"
else
  no "notify picks a notifier per platform instead of assuming osascript" \
     "off macOS every notification is silently dropped"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

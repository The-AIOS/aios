#!/usr/bin/env bash
# quota-rotation-target.test.sh — rotate only to an account that actually has capacity.
#
# Regression origin: rotation was a bare `switch`, which advances one position in
# the USER.md list and wraps. With exactly two accounts — the common case —
# exhausting B rotates straight back to A, whose 5h window has not rolled yet.
# The session lands on a dead account AND then sits out the cooldown there, which
# is strictly worse than not rotating. The data to avoid it was already in hand
# and discarded: rate_limits carries resets_at per window.
#
# Scenario 4 is the one that matters most and is the least obvious: a `declined`
# row must NOT arm the cooldown. Declining means we looked and stayed put, so
# nothing changed and there is nothing to debounce — counting it would blind the
# watcher for COOLDOWN_SECS at precisely the moment it most needs to keep looking.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$ROOT/hooks/claude-identity/_watch.py"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/qrt-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/USER.md" <<'EOF'
## Anthropic accounts

1. `home@example.com` — preferred
2. `overflow@example.com` — overflow

## Something else
3. `notanaccount@example.com`
EOF

# Drive the module directly: these are pure decision functions, so exercising
# them beats trying to fake a whole live rotation.
probe() {  # probe <python-body>
  HOME="$WORK" USER_MD_PATH="$WORK/USER.md" python3 - "$WATCH" <<PYEOF
import importlib.util, sys, json, os, time
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
$1
PYEOF
}

seed_state() {  # seed_state <email> <pct5> <resets_at_offset_secs>
  mkdir -p "$WORK/.claude/identities/$1"
  python3 - "$WORK/.claude/identities/$1/last-limits.json" "$2" "$3" <<'PYEOF'
import json, sys, time
json.dump({"email":"x","recorded_at":int(time.time()),
           "five_hour_pct":float(sys.argv[2]),
           "five_hour_resets_at":time.time()+float(sys.argv[3]),
           "seven_day_pct":0,"seven_day_resets_at":None},
          open(sys.argv[1],"w"))
PYEOF
}

echo "quota-rotation-target: $WATCH"

# 1. Only the numbered list under the right heading counts as accounts.
out="$(probe 'print(",".join(w.parse_accounts()))')"
if [ "$out" = "home@example.com,overflow@example.com" ]; then
  ok "parses the account list and stops at the next section"
else
  no "parses the account list and stops at the next section" "got: $out"; fi

# 2. A capped alternative whose window has NOT rolled is refused.
seed_state overflow@example.com 99 3600
out="$(probe 'print(w.pick_target("home@example.com", 98, 98))')"
if printf '%s' "$out" | grep -q "None" && printf '%s' "$out" | grep -q "still capped"; then
  ok "declines when the only alternative is still capped"
else
  no "declines when the only alternative is still capped" "got: $out"; fi

# 3. Same account, window already rolled -> it becomes a candidate again.
seed_state overflow@example.com 99 -60
out="$(probe 'print(w.pick_target("home@example.com", 98, 98))')"
if printf '%s' "$out" | grep -q "overflow@example.com"; then
  ok "accepts a capped account once its window has rolled over"
else
  no "accepts a capped account once its window has rolled over" "got: $out"; fi

# 4. THE ONE THAT BITES: a `declined` row must not arm the cooldown.
mkdir -p "$WORK/.claude"
python3 - "$WORK/.claude/swap-log.jsonl" <<'PYEOF'
import json, time, sys
now = int(time.time())
rows = [
    {"ts": now - 5000, "action": "rotate",   "rc": 0},   # long ago, real swap
    {"ts": now - 10,   "action": "declined", "rc": None},# just now, changed nothing
]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PYEOF
out="$(probe 'print(w.recently_swapped())')"
if printf '%s' "$out" | grep -q "False"; then
  ok "a 'declined' row does not arm the cooldown"
else
  no "a 'declined' row does not arm the cooldown" "got: $out (a decline changed nothing)"; fi

# 5. A real recent swap still does arm it — the guard must not be gutted.
python3 - "$WORK/.claude/swap-log.jsonl" <<'PYEOF'
import json, time, sys
now = int(time.time())
open(sys.argv[1], "w").write(json.dumps({"ts": now - 10, "action": "rotate", "rc": 0}) + "\n")
PYEOF
out="$(probe 'print(w.recently_swapped())')"
if printf '%s' "$out" | grep -q "True"; then
  ok "a real recent swap still arms the cooldown"
else
  no "a real recent swap still arms the cooldown" "got: $out"; fi

# 6. A FAILED swap (rc != 0) is not a swap either.
python3 - "$WORK/.claude/swap-log.jsonl" <<'PYEOF'
import json, time, sys
now = int(time.time())
open(sys.argv[1], "w").write(json.dumps({"ts": now - 10, "action": "rotate", "rc": 1}) + "\n")
PYEOF
out="$(probe 'print(w.recently_swapped())')"
if printf '%s' "$out" | grep -q "False"; then
  ok "a failed swap does not arm the cooldown"
else
  no "a failed swap does not arm the cooldown" "got: $out"; fi

# 7. Corrupt lines must not abort the scan — the good row behind them still wins.
python3 - "$WORK/.claude/swap-log.jsonl" <<'PYEOF'
import json, time, sys
now = int(time.time())
lines = ["{not json at all", json.dumps({"ts": now - 10, "action": "rotate", "rc": 0}), "]["]
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PYEOF
out="$(probe 'print(w.recently_swapped())')"
if printf '%s' "$out" | grep -q "True"; then
  ok "malformed swap-log lines are skipped, not fatal"
else
  no "malformed swap-log lines are skipped, not fatal" "got: $out"; fi

# 8. Never-seen account is available — otherwise the feature is dead on day one.
rm -rf "$WORK/.claude/identities"
out="$(probe 'print(w.headroom("overflow@example.com", 98, 98))')"
if printf '%s' "$out" | grep -q "True"; then
  ok "an account with no recorded state is assumed fresh"
else
  no "an account with no recorded state is assumed fresh" "got: $out"; fi

# 9. One account configured cannot rotate anywhere, and says so.
cat > "$WORK/USER.md" <<'EOF'
## Anthropic accounts

1. `only@example.com`
EOF
out="$(probe 'print(w.pick_target("only@example.com", 98, 98))')"
if printf '%s' "$out" | grep -q "None" && printf '%s' "$out" | grep -q ">= 2 accounts"; then
  ok "a single-account setup declines with a legible reason"
else
  no "a single-account setup declines with a legible reason" "got: $out"; fi

# 10. record_state -> headroom round-trips through what the cache actually gives us.
cat > "$WORK/USER.md" <<'EOF'
## Anthropic accounts

1. `home@example.com`
2. `overflow@example.com`
EOF
out="$(probe '
cache = {"five_hour_pct": 99, "five_hour_resets_at": time.time()+3600,
         "seven_day_pct": 10, "seven_day_resets_at": None}
w.record_state("overflow@example.com", cache)
print(w.headroom("overflow@example.com", 98, 98))
print(oct(os.stat(w.state_path("overflow@example.com")).st_mode & 0o777))')"
if printf '%s' "$out" | grep -q "False" && printf '%s' "$out" | grep -q "0o600"; then
  ok "recorded limits are read back and the file is 0600"
else
  no "recorded limits are read back and the file is 0600" "got: $out"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

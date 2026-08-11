#!/usr/bin/env bash
# quota-tick-interval.test.sh — the evaluation interval tightens near the cap.
#
# Regression origin: _cache.py rate-limited its _watch.py kick to once per 30s,
# flat. Claude Code adopts a swapped credential on its next API request — but
# that speed is unreachable if the threshold is only EVALUATED every 30 seconds.
# With parallel subagents burning fast, the cap gets crossed inside that blind
# window and the rotation lands after the wall it existed to prevent.
#
# Scenario 5 is the guard that matters beyond this change: the kick must pass the
# WORSE of the two usage numbers. Passing only the 5h figure would leave a 7d
# cap crawling at the slow interval, which is the same blind window wearing a
# different hat.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_PY="$ROOT/hooks/claude-identity/_cache.py"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

echo "quota-tick-interval: $CACHE_PY"

probe(){ python3 - "$CACHE_PY" <<PYEOF
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
$1
PYEOF
}

# 1-2. Slow lane while there is headroom; fast lane inside the hot zone.
out="$(probe 'print(c.tick_interval(0), c.tick_interval(50))')"
if [ "$out" = "30 30" ]; then ok "stays cheap with headroom"; else
  no "stays cheap with headroom" "got: $out"; fi

out="$(probe 'print(c.tick_interval(90), c.tick_interval(99))')"
if [ "$out" = "3 3" ]; then ok "tightens inside the hot zone"; else
  no "tightens inside the hot zone" "got: $out"; fi

# 3. The boundary is inclusive and lands on the fast side.
out="$(probe 'print(c.tick_interval(c.HOT_ZONE_PCT - 0.1), c.tick_interval(c.HOT_ZONE_PCT))')"
if [ "$out" = "30 3" ]; then ok "hot zone boundary is inclusive"; else
  no "hot zone boundary is inclusive" "got: $out"; fi

# 4. Junk must degrade to the CHEAP lane, never to a spawn-every-render loop.
out="$(probe 'print(c.tick_interval(None), c.tick_interval("abc"), c.tick_interval(""))')"
if [ "$out" = "30 30 30" ]; then ok "unusable input degrades to the slow lane"; else
  no "unusable input degrades to the slow lane" "got: $out"; fi

# 5. The call site must feed it the worst of the two windows, not just the 5h.
if grep -A2 'kick_watcher(' "$CACHE_PY" | grep -q 'max(' \
   && grep -A2 'kick_watcher(' "$CACHE_PY" | grep -q 'seven_day_pct'; then
  ok "kick passes the worst of the 5h and 7d numbers"
else
  no "kick passes the worst of the 5h and 7d numbers" \
     "a 7d cap would crawl at the slow interval"; fi

# 6. The fast lane must actually be faster — a config typo making them equal
#    would pass every test above while silently restoring the old behaviour.
out="$(probe 'print(c.WATCH_TICK_SECS_HOT < c.WATCH_TICK_SECS)')"
if [ "$out" = "True" ]; then ok "the hot interval is strictly shorter"; else
  no "the hot interval is strictly shorter" "got: $out"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

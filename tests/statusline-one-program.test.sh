#!/usr/bin/env bash
# The status line is one program (#292). context-monitor.py alone must write the rate-limit cache
# that the AIOS App, Glass and the quota autopilot read, and must start the quota watcher only when
# two or more accounts are in rotation: with one, there is nothing to rotate to, and starting it
# cost a process and a log line every 30 seconds. Usage: bash tests/statusline-one-program.test.sh
# [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
export AIOS_QUOTA_NOTIFY=0   # never a desktop banner from a test (watch-notify-isolation)
M="hooks/claude-identity/context-monitor.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "statusline-one-program"
PAYLOAD='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"/tmp"},"rate_limits":{"five_hour":{"used_percentage":41,"resets_at":1},"seven_day":{"used_percentage":12,"resets_at":2}}}'

render(){  # $1 = home dir; renders once with an isolated HOME and config dir
  printf '%s' "$PAYLOAD" | HOME="$1" USERPROFILE="$1" CLAUDE_CONFIG_DIR="$1/.claude" \
    AIOS_ACCOUNTS_FILE="$1/.aios/accounts.json" AIOS_KEYCHAIN_SERVICE="aios-accounts-test" USER_MD_PATH="$1/none.md" python3 "$M" >/dev/null 2>&1
}
accounts(){  # $1 = home, $2.. = emails in rotation
  h="$1"; shift; mkdir -p "$h/.aios"
  python3 - "$h/.aios/accounts.json" "$@" <<'PY'
import json, sys
json.dump({"version": 1, "accounts": [{"email": e} for e in sys.argv[2:]]}, open(sys.argv[1], "w"))
PY
}

H1=$(mktemp -d "${TMPDIR:-/tmp}/sl1.XXXXXX"); mkdir -p "$H1/.claude"
accounts "$H1" one@example.com
render "$H1"
C="$H1/.claude/rate-limit-cache.json"
[ -f "$C" ] && ok "the status line alone writes the rate-limit cache" || no "no cache written by context-monitor.py"
[ -f "$C" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["five_hour_pct"]==41 and d["seven_day_pct"]==12 else 1)' "$C" \
  && ok "the cache carries the payload's 5-hour and weekly numbers" || no "cache numbers wrong"
[ ! -f "$H1/.claude/watch-tick" ] && ok "one account: the watcher is not started" || no "one account still kicked the watcher"

H2=$(mktemp -d "${TMPDIR:-/tmp}/sl2.XXXXXX"); mkdir -p "$H2/.claude"
accounts "$H2" one@example.com two@example.com
render "$H2"
[ -f "$H2/.claude/watch-tick" ] && ok "two accounts: the watcher is started" || no "two accounts did not kick the watcher"
sleep 1   # let the detached watcher start and settle before the temp home is left behind

python3 - "$M" <<'PY' && ok "the status line reads the seat generation before the payload" || no "generation read after the payload: a sample straddling a swap would pass"
import sys; s = open(sys.argv[1], encoding="utf-8").read()
g, r = s.find("_cache.current_gen()"), s.find("sys.stdin.read()")
sys.exit(0 if 0 <= g < r else 1)
PY
grep -q 'def rotation_has_two' hooks/claude-identity/_cache.py && ok "_cache.py gates the watcher on two accounts" || no "no rotation gate in _cache.py"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

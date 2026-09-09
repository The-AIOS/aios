#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The operator pause marker must suspend rotation, and must NEVER be able to
# disable the autopilot permanently by accident.
#
# WHY. A pause is the one operator-facing capability whose failure mode is
# silence: if a stale, empty or mistyped marker were honoured, quota rotation
# would stay off and nothing would say so -- the operator would simply start
# hitting caps with an autopilot they believe is running. So the contract is
# fail-toward-running: anything not a FUTURE timestamp is ignored AND removed.
#
# These call the SHIPPED paused_until() by importing _watch.py, rather than
# re-implementing its parsing here. A test that restates the logic it checks
# passes while the real function drifts.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
W=hooks/claude-identity/_watch.py
R=hooks/claude-identity/README.md
for f in "$W" "$R"; do [ -f "$f" ] || { echo "::error::$f missing"; exit 1; }; done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Import the real module with CLAUDE_CONFIG_DIR pointed at a scratch dir, so
# nothing touches the operator's own ~/.claude.
probe() { # $1 = file contents ("" = no file); prints "<until> <file_exists>"
  local body="$1"
  rm -f "$TMP/quota-watch.paused"
  [ "$body" = "__none__" ] || printf '%s' "$body" > "$TMP/quota-watch.paused"
  CLAUDE_CONFIG_DIR="$TMP" python3 - "$W" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
u = m.paused_until()
print(f"{1 if u else 0} {1 if os.path.exists(m.PAUSE_FILE) else 0}")
PY
}

echo "-- 1. a FUTURE marker pauses, and is kept --"
r=$(probe "$(python3 -c 'import time;print(int(time.time())+3600)')")
[ "$r" = "1 1" ] && ok "future epoch pauses and the marker survives" || no "future epoch → '$r' (want '1 1')" "a live pause must hold and not delete itself"
r=$(probe "$(python3 -c 'import datetime,time;print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(hours=1)).isoformat())')")
[ "$r" = "1 1" ] && ok "future ISO-8601 pauses too (documented as accepted)" || no "future ISO → '$r' (want '1 1')" "the README documents both forms"

echo "-- 2. anything that is NOT a future timestamp fails toward RUNNING, and self-clears --"
# Each of these is a way an operator can leave a marker that must not disable the autopilot.
for label in "past epoch:$(python3 -c 'import time;print(int(time.time())-60)')" "garbage:not-a-date" "empty:" "whitespace: "; do
  name=${label%%:*}; body=${label#*:}
  r=$(probe "$body")
  [ "$r" = "0 0" ] && ok "$name → not paused, marker removed" \
    || no "$name → '$r' (want '0 0')" "a marker that is not a future timestamp must be ignored AND removed, or a typo disables quota protection silently"
done
r=$(probe "__none__")
[ "$r" = "0 0" ] && ok "no marker → not paused" || no "no marker → '$r' (want '0 0')"

echo "-- 3. the pause is reachable from the docs, with the real path --"
grep -qF 'quota-watch.paused' "$R" && ok "README names the marker file" \
  || no "the capability is undocumented" "an undocumented operator feature in shared code is a personalization"
grep -qiE 'Pausing the autopilot' "$R" && ok "it has a findable section heading" || no "no section for it"
grep -qF 'CLAUDE_CONFIG_DIR' "$R" && ok "documents the path honours CLAUDE_CONFIG_DIR" \
  || no "documents a hardcoded path" "_watch.py resolves CONFIG_DIR from CLAUDE_CONFIG_DIR first"
grep -qiE 'expired \*?or\* ?malformed|malformed' "$R" && ok "documents the fail-toward-running behaviour" \
  || no "auto-expiry/self-clearing undocumented" "the operator cannot rely on what is not written down"
# the code's own path must match what the doc claims
grep -qF '"quota-watch.paused"' "$W" && ok "code and doc name the same file" || no "the code's filename does not match the doc"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

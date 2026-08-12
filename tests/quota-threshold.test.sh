#!/usr/bin/env bash
# quota-threshold.test.sh — the rotation threshold reaches the process that enforces it.
#
# Regression origin: `claude-identity.sh` defined THRESHOLD_5H/THRESHOLD_7D, and
# nothing consumed them. They were never exported, no function in that file read
# them, and the hot path (statusLine -> _cache.py -> _watch.py) never sources the
# shell at all — so `_watch.py`'s own default was the value in force, always. An
# operator who edited the shell got no effect AND no error: set 92, and a 96%
# reading logged "no swap". Two declarations of one value, and the one you could
# find was the one that did nothing.
#
# The fix makes _watch.py the single owner and adds `--threshold`, answered BY the
# consumer so it cannot drift from what actually runs.
#
# Scenarios 1-2 MUST fail against the pre-fix implementation (no --threshold at
# all, and a built-in default that ignored the shell). 4-7 guard the reporting
# label: a rejected override must report the DEFAULT as the value in force, never
# "environment" — mislabelling that is the same class of bug this fix exists for.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$ROOT/hooks/claude-identity/_watch.py"
SHELL_ENTRY="$ROOT/hooks/claude-identity/claude-identity.sh"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Every case runs with a scratch CLAUDE_CONFIG_DIR so a developer's real
# quota-watch.log is never touched by the suite.
run_threshold(){
  local dir; dir="$(mktemp -d "${TMPDIR:-/tmp}/qt-XXXXXX")"
  env -u CLAUDE_QUOTA_5H -u CLAUDE_QUOTA_7D CLAUDE_CONFIG_DIR="$dir" "$@" \
    python3 "$WATCH" --threshold 2>/dev/null
  local rc=$?
  rm -rf "$dir"
  return $rc
}

echo "quota-threshold: $WATCH"

# 1. The consumer can report what it enforces at all.
out="$(run_threshold)"
if [ -n "$out" ]; then ok "--threshold is answerable"; else
  no "--threshold is answerable" "produced no output"; fi

# 2. With no override, the documented default (98) is what is in force.
if printf '%s' "$out" | grep -q '5h: 98%' && printf '%s' "$out" | grep -q '7d: 98%'; then
  ok "no override -> documented default 98"
else
  no "no override -> documented default 98" "got: $out"; fi

# 3. An override actually lands (the whole point of the bug).
out="$(run_threshold env CLAUDE_QUOTA_5H=92 CLAUDE_QUOTA_7D=91)"
if printf '%s' "$out" | grep -q '5h: 92%' && printf '%s' "$out" | grep -q '7d: 91%'; then
  ok "env override reaches the enforcing process"
else
  no "env override reaches the enforcing process" "got: $out"; fi

# 4-6. Junk must be REJECTED, and must not be reported as if it took effect.
for bad in abc 0 150; do
  out="$(run_threshold env CLAUDE_QUOTA_5H="$bad")"
  if printf '%s' "$out" | grep -q '5h: 98%' \
     && ! printf '%s' "$out" | grep -qE '5h: 98%.*\(environment\)'; then
    ok "CLAUDE_QUOTA_5H=$bad -> falls back to 98 and says so"
  else
    no "CLAUDE_QUOTA_5H=$bad -> falls back to 98 and says so" "got: $out"; fi
done

# 7. The two windows are independent — a bad 5h must not drag 7d with it.
out="$(run_threshold env CLAUDE_QUOTA_5H=abc CLAUDE_QUOTA_7D=90)"
if printf '%s' "$out" | grep -q '7d: 90%'; then
  ok "a rejected 5h does not clobber a valid 7d"
else
  no "a rejected 5h does not clobber a valid 7d" "got: $out"; fi

# 8. The operator-facing path agrees with the process-facing one. This is the
#    assertion that would have caught the original bug: the shell must not be
#    able to report a number the watcher does not enforce.
via_shell="$(CLAUDE_QUOTA_5H=92 bash "$SHELL_ENTRY" watch --threshold 2>/dev/null)"
via_python="$(CLAUDE_QUOTA_5H=92 python3 "$WATCH" --threshold 2>/dev/null)"
if [ -n "$via_shell" ] && [ "$via_shell" = "$via_python" ]; then
  ok "shell and watcher report the same effective threshold"
else
  no "shell and watcher report the same effective threshold" \
     "shell=[$via_shell] python=[$via_python]"; fi

# 9. The dead second declaration must not come back.
if ! grep -qE '^[[:space:]]*THRESHOLD_(5H|7D)=' "$SHELL_ENTRY"; then
  ok "no second threshold declaration in the shell"
else
  no "no second threshold declaration in the shell" \
     "$(grep -nE '^[[:space:]]*THRESHOLD_(5H|7D)=' "$SHELL_ENTRY")"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# tests/close-day-out-of-session.test.sh
#
# A task the operator finished outside every session (a reply sent from the mail client) must
# close, not carry. Reported from a live vault: a sent reply carried ×2 → ×4 through two
# /close-day and two /today, and was flagged as avoidance. CLAUDE.md promised two checks that
# did not exist ("per /close-day's publish-evidence rule", "close-day guarantees staleness never
# exceeds a day"). This asserts the check exists in /close-day, runs before the carry triage,
# does nothing when no source is connected, and that CLAUDE.md promises only what it does.
# The same assertions are run against v0.8.12, which must fail them.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# check CLOSE_DAY CLAUDE_MD -> prints one line per broken property. Empty = the rule holds.
check(){
  local cd=$1 cm=$2 a b
  grep -q '^## Done-outside-a-session check' "$cd" || echo "close-day has no done-outside-a-session check"
  a=$(grep -n '^## Done-outside-a-session check' "$cd" | head -1 | cut -d: -f1)
  b=$(grep -n '^## Carry-reason triage prompt' "$cd" | head -1 | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || echo "the check does not come before the carry triage"
  grep -q 'in:sent' "$cd" || echo "no sent-mail lookup"
  grep -qi 'reply / respond' "$cd" || echo "outward actions are not defined"
  grep -q 'No source connected, or the lookup fails' "$cd" || echo "no rule for a missing source"
  grep -q 'done outside a session:' "$cd" || echo "a match does not record its evidence"
  grep -q 'publish-evidence' "$cm" && echo "CLAUDE.md still cites a publish-evidence rule"
  grep -q 'close-day guarantees staleness never exceeds a day' "$cm" && echo "CLAUDE.md still guarantees what nothing enforces"
  return 0
}

echo "── the current command and CLAUDE.md ──"
out=$(check "$ROOT/plugins/aios/commands/close-day.md" "$ROOT/CLAUDE.md")
[ -z "$out" ] && ok "close-day checks carried outward actions first, and CLAUDE.md promises only that" || no "the out-of-session rule does not hold" "$out"

echo "── an outward action nobody could check carries as unverified (#237) ──"
uv=""
grep -q '_(carried ×N, unverified, from: …)_' "$ROOT/plugins/aios/commands/close-day.md" || uv="$uv; close-day does not mark an unchecked outward action unverified"
grep -q 'An `unverified` carry is asked a different question' "$ROOT/plugins/aios/commands/close-day.md" || uv="$uv; the ×6 triage reads an unverified carry as avoidance"
grep -q '`unverified` carries' "$ROOT/plugins/aios/commands/today.md" || uv="$uv; /today flags unverified carries with ⚠️"
[ -z "$uv" ] && ok "unverified carries are marked, asked 'done already?', and never flagged as avoidance" || no "the unverified carry rule does not hold" "${uv#; }"
if git -C "$ROOT" cat-file -e v0.8.13:plugins/aios/commands/close-day.md 2>/dev/null; then
  git -C "$ROOT" show v0.8.13:plugins/aios/commands/close-day.md | grep -q '_(carried ×N, unverified' \
    && no "control: v0.8.13 already had the rule" "the check cannot see the change" \
    || ok "control: v0.8.13 lacks it, so the check can see the change"
fi

echo "── control: v0.8.12 fails the same check ──"
if git -C "$ROOT" cat-file -e v0.8.12:plugins/aios/commands/close-day.md 2>/dev/null; then
  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  git -C "$ROOT" show v0.8.12:plugins/aios/commands/close-day.md > "$T/close-day.md"
  git -C "$ROOT" show v0.8.12:CLAUDE.md > "$T/CLAUDE.md"
  out=$(check "$T/close-day.md" "$T/CLAUDE.md")
  n=$(printf '%s\n' "$out" | grep -c .)
  [ "$n" -ge 3 ] && ok "v0.8.12 fails it ($n broken properties), so the check can see the bug" || no "the check passes the old command" "$out"
else
  echo "  - skip: tag v0.8.12 not reachable (shallow clone)"
fi

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# tests/commands-snapshot-helper.test.sh
#
# Every command that tells a session to archive an observed-context file must send it
# through `hooks/aios-snapshot`, and none may prescribe the hand-rolled protocol the helper
# replaced (copy, then pick the "next free letter" by hand). CLAUDE.md § Session End moved
# the rule to the helper; two commands kept the old text, so a session following the
# command instead of CLAUDE.md ran the non-atomic protocol the helper exists to retire —
# the fix landed where it was written, not where it was consumed.
#
# Run:  bash tests/commands-snapshot-helper.test.sh
#       COMMANDS_DIR=<dir> bash tests/commands-snapshot-helper.test.sh   (audit another copy)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMDS="${COMMANDS_DIR:-$ROOT/plugins/aios/commands}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

printf 'commands archive observed context through hooks/aios-snapshot\n'

[ -x "$ROOT/hooks/aios-snapshot" ] && ok "hooks/aios-snapshot exists and is executable" || no "hooks/aios-snapshot missing or not executable"

# 1. a command that names the DATED destination (`…/{YYYY-MM}/{YYYY-MM-DD}-…`, which only a
#    writer uses — readers name the month folder) must also name the helper
for f in "$CMDS"/*.md; do
  n=$(basename "$f")
  grep -q 'observed-snapshots/{YYYY-MM}/{YYYY-MM-DD}' "$f" || continue
  if grep -q 'aios-snapshot' "$f"; then ok "$n: names the dated snapshot destination AND the helper"
  else no "$n: names the dated snapshot destination but never hooks/aios-snapshot" "a session following it will hand-roll the copy"; fi
done

# 2. no command prescribes the by-hand letter protocol. EVERY occurrence of "next free letter"
#    must be the helper's own phrasing ("took the …" / "takes the …") — judged per occurrence,
#    not per line, so a manual fallback appended to a permitted sentence still fails.
manual_letter_hits(){ # prints each occurrence that is NOT the helper's phrasing
  grep -oE '.{0,12}next free letter' "$1" | grep -v -E '(took|takes) the next free letter'
}
hits=""
for f in "$CMDS"/*.md; do
  grep -q 'next free letter' "$f" || continue
  [ -n "$(manual_letter_hits "$f")" ] && hits="$hits $(basename "$f")"
done
[ -z "$hits" ] && ok "no command prescribes a by-hand 'next free letter' step" || no "by-hand 'next free letter' still prescribed in:$hits"

# 2b. the rule itself, against fixtures — so a loosened regex cannot pass silently
FX=$(mktemp -d "${TMPDIR:-/tmp}/snaphelper.XXXXXX"); trap 'rm -rf "$FX"' EXIT
printf 'The helper takes the next free letter.\n' > "$FX/ok.md"
printf 'The helper takes the next free letter. If it fails, copy the file manually to the next free letter.\n' > "$FX/mixed.md"
printf 'Different content -> pick the next free letter (b, c, ...).\n' > "$FX/manual.md"
printf 'Something else takes the next free letter for you.\n' > "$FX/other-subject.md"
[ -z "$(manual_letter_hits "$FX/ok.md")" ]        && ok "2b. rule: the helper's own phrasing passes" || no "2b. rule rejects the helper's own phrasing"
[ -n "$(manual_letter_hits "$FX/mixed.md")" ]     && ok "2c. rule: a manual fallback after a permitted sentence is caught" || no "2c. rule lets a manual fallback hide behind a permitted sentence"
[ -n "$(manual_letter_hits "$FX/manual.md")" ]    && ok "2d. rule: the by-hand protocol is caught" || no "2d. rule misses the by-hand protocol"
[ -z "$(manual_letter_hits "$FX/other-subject.md")" ] && ok "2e. rule is lexical, not semantic: another subject with the helper's phrasing passes (documented limit)" || no "2e. rule unexpectedly rejected the helper's phrasing"

# 3. the two commands this guards, by name
for n in close-day housekeeping; do
  grep -q 'hooks/aios-snapshot "vault/00 - notes/context/observed/' "$CMDS/$n.md" \
    && ok "$n.md: invokes the helper with the observed path" \
    || no "$n.md: does not invoke hooks/aios-snapshot on an observed file"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

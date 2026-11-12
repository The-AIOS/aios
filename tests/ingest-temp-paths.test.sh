#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:ingest works in a folder of its own per run, never a fixed /tmp path (#297)
#
# WHY THIS EXISTS
# ingest.md converted every source into /tmp/ingest-source.md and transcribed into
# /tmp/ingest-transcript.txt. Two ingests at once (two sessions, or a session and a
# scheduled job) wrote and read the same file, so one could file the other's source
# while everything looked normal.
#
# WHAT IT HOLDS
#   * no fixed /tmp/ingest-* path anywhere in the command
#   * the command creates a per-run folder with mktemp -d, uses it for the conversion
#     and the transcript, and removes it when the ingest is done
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
F=plugins/aios/commands/ingest.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
hits=$(grep -n '/tmp/ingest-' "$F" || true)
[ -z "$hits" ] && ok "no fixed /tmp/ingest-* path is left" || no "fixed paths remain" "$hits"
grep 'mktemp -d' "$F" >/dev/null && ok "each run makes its own folder with mktemp -d" || no "no per-run folder is created"
grep -F '"$INGEST_DIR/source.md"' "$F" >/dev/null && ok "the conversion writes into the run's folder" || no "the conversion does not use the run's folder"
grep -F '"$INGEST_DIR/transcript.txt"' "$F" >/dev/null && ok "the transcript goes into the run's folder" || no "the transcript does not use the run's folder"
grep -F 'remove that folder with `rm -rf`' "$F" >/dev/null && ok "the folder is removed when the ingest is done" || no "the run's folder is never removed"
grep -F 'does not carry over' "$F" >/dev/null && ok "it warns that the variable does not survive between tool calls" || no "no warning that each tool call starts a fresh shell"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

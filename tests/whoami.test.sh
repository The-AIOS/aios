#!/usr/bin/env bash
# tests/whoami.test.sh
#
# hooks/context/whoami is the session-start identity check. The old CLAUDE.md line grepped the transcript
# inline, with `$CLAUDE_CODE_SESSION_ID` in the command, and Claude Code asks permission for any
# command whose variables it must expand first: every session start prompted, even allowlisted.
# The helper must resolve the same name, and CLAUDE.md must prescribe no `$` in that check.
# Which record and which source win, and that the Python hooks agree: tests/session-name.test.sh.
set -u
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
W=hooks/context/whoami
[ -x "$W" ] || { echo "::error::$W missing or not executable"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/projects/-some-project"
TR="$T/projects/-some-project/abc-123.jsonl"
printf '{"type":"user"}\n{"type":"agent-name","agentName":"first-name","sessionId":"abc-123"}\n{"type":"agent-name","agentName":"renamed","sessionId":"abc-123"}\n' > "$TR"
run(){ env -u CLAUDE_AGENT_NAME -u CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR="$T" "$@" bash "$W"; }

echo "── the name is the LAST agent-name record of the transcript, also when the env var is set ──"
[ "$(run CLAUDE_CODE_SESSION_ID=abc-123)" = renamed ] && ok "a renamed session is known by its last name" || no "wrong transcript name" "$(run CLAUDE_CODE_SESSION_ID=abc-123)"
[ "$(run CLAUDE_AGENT_NAME=first-name CLAUDE_CODE_SESSION_ID=abc-123)" = renamed ] && ok "the transcript wins over a launch-time env var the rename left behind" || no "the stale env var won" "$(run CLAUDE_AGENT_NAME=first-name CLAUDE_CODE_SESSION_ID=abc-123)"

echo "── the env var is the fallback: no session id, no transcript, or no record in it ──"
[ "$(run CLAUDE_AGENT_NAME=lawyer)" = lawyer ] && ok "no session id → the env var" || no "env var ignored without a session id"
[ "$(run CLAUDE_AGENT_NAME=lawyer CLAUDE_CODE_SESSION_ID=zzz-999)" = lawyer ] && ok "no transcript yet → the env var" || no "env var ignored without a transcript"
printf '{"type":"user"}\n' > "$T/projects/-some-project/norec-1.jsonl"
[ "$(run CLAUDE_AGENT_NAME=lawyer CLAUDE_CODE_SESSION_ID=norec-1)" = lawyer ] && ok "a transcript with no record → the env var" || no "env var ignored when the transcript has no record"
[ "$(run CLAUDE_AGENT_NAME=lawyer 'CLAUDE_CODE_SESSION_ID=*')" = lawyer ] && ok "a glob in the session id reads no transcript → the env var" || no "a glob id read a transcript"

echo "── nothing to find is a plain CLI session: empty output, exit 0 ──"
out=$(run CLAUDE_CODE_SESSION_ID=zzz-999); rc=$?
[ -z "$out" ] && [ "$rc" = 0 ] && ok "no transcript → empty, exit 0" || no "printed '$out' / rc $rc"
out=$(run); [ -z "$out" ] && ok "no session id → empty" || no "printed '$out'"
out=$(run 'CLAUDE_CODE_SESSION_ID=*'); [ -z "$out" ] && ok "a glob in the session id matches nothing" || no "a glob id read a transcript: '$out'"

echo "── CLAUDE.md prescribes the helper, with no \$ in the identity check ──"
blk=$(awk '/^## Mandatory First Action/{f=1;next} /^## /&&f{exit} f' CLAUDE.md)
printf '%s' "$blk" | grep -q '`~/aios/hooks/context/whoami`' && ok "the first action runs hooks/context/whoami" || no "CLAUDE.md does not prescribe hooks/context/whoami"
printf '%s' "$blk" | grep -q 'CLAUDE_CODE_SESSION_ID' && no "the first action still expands the session id inline" || ok "no session-id expansion left in the first action"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

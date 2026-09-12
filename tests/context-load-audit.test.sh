#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hooks/context-load-audit.py — the instrument behind /aios:housekeeping's
# Bucket 30, tested against synthetic transcripts with known answers
#
# This exists because the FIRST version of this measurement was wrong, and wrong
# in the direction that gets trusted: it matched only `context/…/<file>.md`, so
# it missed every worker that did `cd <context dir> && grep '^### ' patterns.md`
# -- which is what workers actually do. It reported three workers at zero that
# had read the entire floor, and the clean number was believed.
#
# So the refusal cases come first (antifragile #110): the cd-relative read, and
# the control that must abort rather than reassure. A detector that cannot fail
# reports "all clear" just as convincingly when it is broken.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/context-load-audit.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME_FAKE="$TMP/home"; mkdir -p "$HOME_FAKE/.claude/projects/proj"

# Build a transcript: agent name + N tool_use events with the given commands.
mk(){ # $1 name · $2 sid · $3.. commands
  local name="$1" sid="$2"; shift 2
  local f="$HOME_FAKE/.claude/projects/proj/$sid.jsonl"
  printf '{"type":"agent-name","agentName":"%s","sessionId":"%s"}\n' "$name" "$sid" > "$f"
  local i=0
  for cmd in "$@"; do
    i=$((i+1))
    python3 - "$f" "$cmd" <<'PY'
import json, sys
f, cmd = sys.argv[1], sys.argv[2]
rec = {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":cmd}}]}}
open(f,"a").write(json.dumps(rec)+"\n")
PY
  done
  # pad to clear the --min-tools threshold
  while [ "$i" -lt 25 ]; do
    i=$((i+1))
    python3 - "$f" <<'PY'
import json, sys
rec={"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}}
open(sys.argv[1],"a").write(json.dumps(rec)+"\n")
PY
  done
}
run(){ HOME="$HOME_FAKE" python3 "$H" "$@" 2>&1; }

echo "── 1. REFUSAL: a cd-relative read must be COUNTED (the original bug) ──"
mk worker-cd cd000001 \
  'cd "/Users/x/aios/vault/00 - notes/context/observed" && for f in antifragile preferences patterns growth; do grep "^### " "$f.md"; done'
OUT="$(run --session cd000001 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
[ "$N" = 4 ] && ok "cd-then-bare-filename counts all 4 floor files" \
  || no "cd-relative read scored $N, expected 4" "this is the exact miss that reported live workers as zero"
T=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)[0]["titles_only"]))' 2>/dev/null || echo -1)
[ "$T" = 4 ] && ok "and is classified titles-only, not a full read" \
  || no "depth misclassified: titles_only=$T" "a floor degrading to nothing must not look like a full load"

echo "── 2. a full-path read is counted, and as a FULL read ──"
mk worker-path fu000002 \
  'cat "/Users/x/aios/vault/00 - notes/context/declared/personal_voice.md"' \
  'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
OUT="$(run --session fu000002 --min-tools 0 --json)"
F=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)[0]["full"]))' 2>/dev/null || echo -1)
[ "$F" = 2 ] && ok "full-path reads counted as full (2)" || no "full-path read scored $F, expected 2"

echo "── 3. REFUSAL: prose mentioning a path is NOT a read ──"
# A transcript quotes context paths constantly. Only a tool call is evidence.
f="$HOME_FAKE/.claude/projects/proj/pr000003.jsonl"
printf '{"type":"agent-name","agentName":"worker-prose","sessionId":"pr000003"}\n' > "$f"
python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
# assistant TEXT and a tool_result both mention the path; neither is a tool_use
open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":"I should read context/observed/patterns.md next"}]}})+"\n")
open(p,"a").write(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","content":"context/observed/antifragile.md"}]}})+"\n")
for _ in range(25):
    open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}})+"\n")
PY
OUT="$(run --session pr000003 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
[ "$N" = 0 ] && ok "prose and tool_result do not count as reads" \
  || no "scored $N from text alone" "mentioning a path is not opening it"

echo "── 4. CONTROL: with no scoring primary, it must ABORT, not reassure ──"
mk worker-zero ze000004 'echo "did no context reading at all"'
OUT="$(run --min-tools 0)"; RC=$?
if printf '%s' "$OUT" | grep -q 'ABORT'; then
  ok "no primary scored → aborts instead of reporting a clean number"
else
  no "reported worker numbers with no working control" "$(printf '%s' "$OUT" | head -3)"
fi

echo "── 5. with a scoring primary, it reports and flags the zero ──"
mk buddai pr000005 'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
OUT="$(run --min-tools 0)"
printf '%s' "$OUT" | grep -q 'control — primary sessions: 1/1' \
  && ok "primary recognised as the control" || no "primary not detected" "$(printf '%s' "$OUT" | head -2)"
printf '%s' "$OUT" | grep -q 'worker-zero' \
  && ok "the zero-context worker is named" || no "a worker at zero was not surfaced"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

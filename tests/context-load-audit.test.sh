#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one. Same probe
# hooks/claude-identity/claude-identity.sh and mcps/setup.sh already use.
# $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

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
# A fixture VAULT, so the DERIVED filename list has a source. The detector no longer
# ships a hand-written list (the first one named four files from a single operator's
# vault -- a canonical leak that also matched nothing anywhere else), so bare-filename
# reads after a `cd` can only be resolved from the vault in front of it.
FAKE_VAULT="$TMP/vaultroot"
mkdir -p "$FAKE_VAULT/vault/00 - notes/context/declared" \
         "$FAKE_VAULT/vault/00 - notes/context/observed"
for n in about_me personal_voice working_style; do
  printf '# %s\n' "$n" > "$FAKE_VAULT/vault/00 - notes/context/declared/$n.md"
done
for n in antifragile patterns preferences growth; do
  printf '# %s\n' "$n" > "$FAKE_VAULT/vault/00 - notes/context/observed/$n.md"
done
export AIOS_VAULT="$FAKE_VAULT"

# Build a transcript: agent name + N tool_use events with the given commands.
mk(){ # $1 name · $2 sid · $3.. commands
  local name="$1" sid="$2"; shift 2
  local f="$HOME_FAKE/.claude/projects/proj/$sid.jsonl"
  printf '{"type":"agent-name","agentName":"%s","sessionId":"%s"}\n' "$name" "$sid" > "$f"
  local i=0
  for cmd in "$@"; do
    i=$((i+1))
    $PYBIN - "$f" "$cmd" <<'PY'
import json, sys
f, cmd = sys.argv[1], sys.argv[2]
rec = {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":cmd}}]}}
open(f,"a").write(json.dumps(rec)+"\n")
PY
  done
  # pad to clear the --min-tools threshold
  while [ "$i" -lt 25 ]; do
    i=$((i+1))
    $PYBIN - "$f" <<'PY'
import json, sys
rec={"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}}
open(sys.argv[1],"a").write(json.dumps(rec)+"\n")
PY
  done
}
# NOTE: USERPROFILE is set alongside HOME on purpose. On Windows, Python's
# `Path.home()` / `expanduser('~')` read USERPROFILE and IGNORE HOME, so a test
# that isolates a Python hook with HOME alone does not isolate it at all — it
# silently reads the operator's REAL ~/.claude. That is worse than a failing
# test: it can pass or fail for reasons having nothing to do with the fixture.
# Harmless on macOS/Linux, where USERPROFILE is unused.
run(){ HOME="$HOME_FAKE" USERPROFILE="$HOME_FAKE" AIOS_VAULT="$FAKE_VAULT" $PYBIN "$H" "$@" 2>&1; }

echo "── 1. REFUSAL: a cd-relative read must be COUNTED (the original bug) ──"
mk worker-cd cd000001 \
  'cd "/Users/x/aios/vault/00 - notes/context/observed" && for f in antifragile preferences patterns growth; do grep "^### " "$f.md"; done'
OUT="$(run --session cd000001 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
[ "$N" = 4 ] && ok "cd-then-bare-filename counts all 4 floor files" \
  || no "cd-relative read scored $N, expected 4" "this is the exact miss that reported live workers as zero"
T=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(len(json.load(sys.stdin)[0]["titles_only"]))' 2>/dev/null || echo -1)
[ "$T" = 4 ] && ok "and is classified titles-only, not a full read" \
  || no "depth misclassified: titles_only=$T" "a floor degrading to nothing must not look like a full load"

echo "── 2. a full-path read is counted, and as a FULL read ──"
mk worker-path fu000002 \
  'cat "/Users/x/aios/vault/00 - notes/context/declared/personal_voice.md"' \
  'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
OUT="$(run --session fu000002 --min-tools 0 --json)"
F=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(len(json.load(sys.stdin)[0]["full"]))' 2>/dev/null || echo -1)
[ "$F" = 2 ] && ok "full-path reads counted as full (2)" || no "full-path read scored $F, expected 2"

echo "── 3. REFUSAL: prose mentioning a path is NOT a read ──"
# A transcript quotes context paths constantly. Only a tool call is evidence.
f="$HOME_FAKE/.claude/projects/proj/pr000003.jsonl"
printf '{"type":"agent-name","agentName":"worker-prose","sessionId":"pr000003"}\n' > "$f"
$PYBIN - "$f" <<'PY'
import json, sys
p = sys.argv[1]
# assistant TEXT and a tool_result both mention the path; neither is a tool_use
open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":"I should read context/observed/patterns.md next"}]}})+"\n")
open(p,"a").write(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","content":"context/observed/antifragile.md"}]}})+"\n")
for _ in range(25):
    open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}})+"\n")
PY
OUT="$(run --session pr000003 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
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

echo "── 6. the detector knows what CORRECT looks like under the rule it audits ──"
# A worker that runs the one-call floor has loaded the whole floor. Matching only file
# PATHS scores that worker at zero -- reporting correct behaviour as the WORST possible
# behaviour, so an after-vs-before comparison would show the new wiring as a regression.
grep -q 'context-floor' "$H" \
  && ok "the audit recognises the one-call floor command" \
  || no "a worker running context-floor.py would score ZERO" \
        "correct behaviour would be reported as the worst behaviour"
if grep -qE 'thinker-collaborations|coding-practices|psychometric-profile' "$H"; then
  no "the audit hardcodes personal context filenames" \
     "a canonical leak, and a list that matches nothing in another vault"
else
  ok "no hardcoded or personal context filenames in the detector"
fi
grep -q '_context_names' "$H" \
  && ok "context filenames are derived from the vault at runtime" \
  || no "filenames are not derived" "both folders vary per vault; a fixed list goes stale silently"

echo "── 7. FIT is measured, not just volume ──"
# "Was the answer good" is subjective. "Did a worker that published in the operator's name
# ever read the file that says how they write" is a fact on the transcript -- and it is the
# failure that does NOT announce itself, since the output reads fluent either way. That
# makes reinforced learning checkable rather than a matter of taste.
grep -q 'OUTWARD' "$H" \
  && ok "the audit detects outward-facing actions" \
  || no "no notion of outward-facing work" "then fit cannot be measured, only volume"
grep -q 'DECLARED_NAMES' "$H" \
  && ok "it tracks which declared/ files a worker read" \
  || no "declared reads are not separated" "the voice-without-voice-context case is invisible"
if grep -qE 'outward.*declared|declared.*outward' "$H"; then
  ok "it cross-references the two into a fit finding"
else
  no "outward actions and declared reads are never compared" \
     "each alone is a count; the FINDING is the pair"
fi
# And the declared list must be derived, like everything else here.
grep -q '_declared_names' "$H" \
  && ok "declared filenames are derived from the vault" \
  || no "declared names are hardcoded" "that list is empty on any vault that renamed them"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

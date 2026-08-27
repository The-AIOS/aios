#!/usr/bin/env bash
# tests/cold-start-interview.test.sh
#
# Guards AI-122's acceptance criteria for /aios:cold-start-interview.
#
# WHY A TEST AND NOT A REVIEW
# ---------------------------
# AI-122 re-times friction out of first-run without removing capability. Both halves of that are
# regressible by a single well-meaning edit:
#
#   · someone re-adds a connector question to Step 1 because it "belongs with the other identity
#     questions", and the #1 measured freak-out is back;
#   · someone tidies Step 11 away as "duplicated content", and the re-timing silently becomes a
#     feature deletion — which is the exact failure this design was shaped to avoid.
#
# So the criteria are asserted, not remembered.
#
# THE VOCABULARY CRITERION IS MEASURED ON SPOKEN COPY, DELIBERATELY.
# "The word MCP appears zero times before the closing section" cannot mean *zero times in the file*,
# because the file must be able to EXPLAIN that rule to the Claude executing it — and a test that
# forbids documenting its own rule is a test that gets deleted. So it counts occurrences inside
# fenced blocks (the words the operator actually reads) before Step 11, and separately reports the
# prose count so a reviewer can see it is meta rather than leakage.
#
# Run:  bash tests/cold-start-interview.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/plugins/aios/commands/cold-start-interview.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
# Both helpers RETURN 0 explicitly. Without it, `no "msg"` with no detail arg ends on a failed
# `[ -n "" ]` test and returns 1 — so an `a && no ... || ok ...` chain prints BOTH. That happened on
# this suite's first run: one check reported FAIL and PASS simultaneously.
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

echo "── 1. the file is present and structurally intact ──"
[ -f "$F" ] && ok "command file exists" || { no "missing"; exit 1; }
for step in '### Pre-step' '### Step 0' '### Step 1' '### Step 2' '### Step 3' '### Step 10' '### Step 11'; do
  grep -q "^$step" "$F" && ok "$step present" || no "$step missing"
done

echo "── 2. A1 · connector vocabulary — spoken copy is clean before Step 11 ──"
python3 - "$F" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False; prose=0
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if n<i11:
        if infence: fenced += len(pat.findall(l))
        else:        prose  += len(pat.findall(l))
print(f"SPOKEN={fenced} PROSE={prose}")
PY
read -r counts < <(python3 - "$F" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if infence and n<i11: fenced += len(pat.findall(l))
print(fenced)
PY
)
[ "$counts" = "0" ] && ok "zero 'MCP' in spoken copy before Step 11 (A1)" \
  || no "'MCP' appears $counts time(s) in spoken copy before Step 11"
grep -q 'the word is \*\*"connectors"\*\*\|Say "connectors", never "MCP"' "$F" \
  && ok "the replacement vocabulary is stated in the file" || no "vocabulary rule not stated"

echo "── 3. nothing was REMOVED — the re-timing destinations exist ──"
# Every capability pulled out of the critical path must have a named destination.
grep -q '^### Step 11 — Connectors' "$F" && ok "Step 11 (connectors) exists — the destination for Steps 6+7" \
  || no "Step 11 missing: the re-timing has nowhere to land, which makes it a deletion"
n_services=$(awk '/^### Step 11/,/^## Output/' "$F" | grep -cE '^[0-9]+\. \*\*')
[ "$n_services" -ge 10 ] && ok "all $n_services bundled services preserved in Step 11" \
  || no "only $n_services services listed — value props were lost, not moved"
grep -q 'does NOT end here' "$F" && ok "Step 10 hands off instead of ending the interview" \
  || no "the interview still ends at Step 10 — connectors would never be offered"
grep -qE 'Depth' "$F" && ok "the Depth tier is named (de-mandated, not deferred)" || no "Depth tier missing"
grep -q '5h/7d' "$F" && ok "the multi-account item still exists (re-timed to Day-7, not dropped)" \
  || no "the multi-account capability disappeared entirely"

echo "── 4. Step 1 stays short — the friction that started this ──"
q=$(awk '/^### Step 1 —/,/^### Step 2 —/' "$F" | grep -cE '^[0-9]+\. \*\*')
[ "$q" -le 2 ] && ok "Core Step 1 asks $q question(s) (≤2)" \
  || no "Step 1 is back to $q questions — a connector question has crept in"
# Only NUMBERED question lines count. Step 1 deliberately contains a table documenting that the
# Slack/GitHub question MOVED to Step 11 — and the first version of this check matched that table,
# reading the record of the removal as the removal being undone. A guard that cannot tell a thing
# from its changelog will fire on every honest edit.
if awk '/^### Step 1 —/,/^### Step 2 —/' "$F" | grep -E '^[0-9]+\. ' | grep -qiE 'slack|github|calendar \+ tasks'; then
  no "a connector question is back in Step 1 (numbered question line)"
else
  ok "no connector question among Step 1's numbered questions"
fi

echo "── 5. A2 · the vault connector is registered silently, never asked ──"
grep -q 'mcp-obsidian@latest' "$F" && ok "obsidian registration is present" || no "obsidian registration missing"
grep -q 'Never ask the operator about it' "$F" && ok "explicitly marked never-ask" || no "not marked never-ask"
awk '/^### Step 11/,/^## Output/' "$F" | grep -qi 'obsidian' \
  && no "obsidian is listed as a connector — it is infrastructure, must not appear" \
  || ok "obsidian is absent from the connectors list (infrastructure, not a connector)"

echo "── 6. both entry paths are handled ──"
grep -q 'ENTRY=app' "$F" && ok "app-vs-terminal entry detection present" || no "no entry detection"
grep -q 'Never mention SETUP.md to an App-path operator\|never send them to it' "$F" \
  && ok "app-path operators are never routed into SETUP.md" || no "SETUP.md routing rule missing"

echo "── 7. CONTROL — the criterion must be able to fail ──"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/csi.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
python3 - "$F" "$TMP/broken.md" <<'PY'
import sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
# inject a spoken-copy violation into Step 0's fenced block
for i,l in enumerate(L[:i11]):
    if l.strip().startswith('```') :
        L.insert(i+1, "  MCPs set up for your daily tools"); break
open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(L))
PY
bad=$(python3 - "$TMP/broken.md" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if infence and n<i11: fenced += len(pat.findall(l))
print(fenced)
PY
)
[ "$bad" -gt 0 ] && ok "CONTROL FIRES: a spoken 'MCP' before Step 11 is detected ($bad)" \
  || no "CONTROL DID NOT FIRE — section 2 cannot see a violation, so it proves nothing"


# ─────────────────────────────────────────────────────────────────────────────
# 4 · CROSS-SURFACE CONSISTENCY
#
# Four documents describe this same first run: README.md (the funnel), START-HERE.md
# (post-clone), SETUP.md (which Claude EXECUTES), and the interview itself. SETUP.md
# alone carries the sequence TWICE — once addressed to Claude, once to the operator.
#
# They drifted during this very change: the connectors step and the interview's
# duration were corrected in one copy and not the other, so a first-timer read a
# promise the executor no longer made. Nothing detected it; a human reread did.
# These assertions are that reread, made mechanical.
# ─────────────────────────────────────────────────────────────────────────────
SURFACES="README.md START-HERE.md SETUP.md CHEATSHEET.md TOOLS.md plugins/aios/commands/cold-start-interview.md"

# 4a — the retired contract must not survive anywhere. Whichever copy keeps it is
#      the one a newcomer might read.
for claim in '15-25 min' '~20 min' 'Steps 0-10' 'installs MCPs' 'pulls your Calendar + Tasks + Slack'; do
  hits=""
  for f in $SURFACES; do
    [ -f "$f" ] || continue
    grep -qF "$claim" "$f" && hits="$hits $f"
  done
  [ -z "$hits" ] && ok "retired claim absent from every surface: \"$claim\"" \
    || no "retired claim still live: \"$claim\"" "in:$hits — a surface promising the old flow is worse than no surface"
done

# 4b — SETUP.md is the file the entry prompt actually runs. It must not fire the
#      connectors pass, nor ask the two questions that moved. Matching only a LIVE
#      invocation: the file must stay free to explain, in prose, why it doesn't.
# NOTE: the block is an HTML <details>, NOT a '>' blockquote. The first version of
#       this guard matched '^> ### .*Reading this as Claude' and selected ZERO lines,
#       so it passed by measuring nothing — reintroducing the exact invocation did not
#       make it fire. The line-count assertion below is what makes that visible.
CLAUDE_BLOCK=$(awk '/<summary>.*Reading this as Claude/,/<\/details>/' SETUP.md)
CB_STEPS=$(printf '%s\n' "$CLAUDE_BLOCK" | grep -cE '^[0-9]+\. ')
[ "${CB_STEPS:-0}" -ge 8 ] \
  && ok "the Claude-facing block is locatable and has $CB_STEPS numbered steps" \
  || no "cannot locate the Claude-facing block in SETUP.md (found ${CB_STEPS:-0} steps)" \
       "every assertion scoped to it would pass by measuring nothing"

# The step that REPLACED the invocation says "Do NOT invoke `/aios:mcps-setup` here"
# and is itself a numbered line, so a naive '^[0-9]+\. .*invoke' fires on the fix.
# Strip negated lines first: a guard that cannot tell a thing from its own changelog
# fires on every honest edit, and gets muted.
if printf '%s\n' "$CLAUDE_BLOCK" \
     | grep -E '^[0-9]+[a-z]?\. ' \
     | grep -viE 'do not|don.t|never|no longer|used to' \
     | grep -qF 'invoke `/aios:mcps-setup`'; then
  no "SETUP.md still invokes /aios:mcps-setup as a numbered step" "connectors belong to interview Step 11, after the first /today"
else
  ok "SETUP.md does not invoke the connectors pass during setup"
fi
grep -qF 'Do you use more than one Anthropic account?' SETUP.md \
  && no "SETUP.md still asks the multi-account question" "unanswerable on day one; the Day-7 check-in owns it" \
  || ok "SETUP.md no longer asks the multi-account question"

# 4c — removal without a named destination is how re-timing decays into deletion.
#      SETUP must point at where each moved thing went.
grep -qF 'Step 11' SETUP.md \
  && ok "SETUP.md names interview Step 11 as the connectors' destination" \
  || no "SETUP.md drops connectors with no destination" "a reader cannot tell 'later' from 'gone'"
grep -qiE 'Day-7|Day 7' SETUP.md \
  && ok "SETUP.md names the Day-7 check-in as the multi-account destination" \
  || no "SETUP.md drops the multi-account question with no destination" ""

# 4d — the interview's own self-description is read by every session that lists
#      commands. It drifted too, and it is the least likely copy to be reread.
grep -qE '5-minute Core|~5 ?min' "$F" \
  && ok "the interview's description states the Core contract it actually offers" \
  || no "the interview's description does not state its own Core contract" "the description is what a session sees before opening the file"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

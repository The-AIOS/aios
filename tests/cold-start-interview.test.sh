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

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

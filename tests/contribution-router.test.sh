#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CONTRIBUTING.md must route a contributor to the right repo, and CHEATSHEET.md
# must answer the operating questions without becoming a second copy of the
# specs it points at.
#
# WHY THIS EXISTS. Canonical's contribution graph was one-way: both surface repos
# told contributors when a change belonged to canonical, and canonical told nobody
# the reverse — while being the repo every install funnels into and the one
# `/aios:update` tracks. So a Glass or App bug got filed here by default, and the
# only routing rule anyone had written was a LAYER rule ("agent/skill/command ->
# canonical"), which helps only if you already know your layer. It fails in the one
# case where misrouting actually happens: a documented thing that does not work.
#
# The checks below are deliberately about STRUCTURE and NON-DUPLICATION, not
# wording. Two failure modes are in scope:
#   1. a route that goes stale (a repo renamed, a doc that stops naming all three)
#   2. canonical growing a second copy of a sibling's setup instructions, which is
#      the drift class this repo has removed from three separate places
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
sk(){ printf '  SKIP %s\n     %s\n' "$1" "${2:-}"; }
C=CONTRIBUTING.md
H=CHEATSHEET.md
[ -f "$C" ] || { echo "::error::$C missing"; exit 1; }
[ -f "$H" ] || { echo "::error::$H missing"; exit 1; }

echo "-- 1. all three repos are named as contribution targets --"
for r in aios aios-glass aios-app; do
  grep -qF "The-AIOS/$r" "$C" && ok "CONTRIBUTING names The-AIOS/$r" \
    || no "CONTRIBUTING does not name The-AIOS/$r" "the graph was one-way for exactly this reason: the siblings link here and this file linked nowhere"
done
grep -qiE 'fork.{0,20}branch.{0,20}pull request|fork → branch → pull request' "$C" \
  && ok "the contribution path is stated once for all three" \
  || no "the fork/branch/PR path is not stated for the surface repos" "an operator told to 'contribute to Glass' with no mechanism has been pointed at a door with no handle"

echo "-- 2. the 'extension' collision is disambiguated --"
# The file uses "extension layer" to mean custom/, while Glass IS an extension.
if grep -qi 'extension' "$C"; then
  grep -qiE 'extension.{0,80}means two|always means .*custom|IDE extension' "$C" \
    && ok "the two meanings of 'extension' are separated" \
    || no "'extension' is used for both custom/ and Glass with no disambiguation" "a contributor reading 'the extension layer lives in custom/' then hearing 'the Glass extension' has no way to know those are unrelated"
else
  sk "extension disambiguation" "the word no longer appears; nothing to disambiguate"
fi

echo "-- 3. the router routes by SYMPTOM, not only by layer --"
grep -qiE 'what you observed|symptom' "$C" \
  && ok "the router is framed by what the contributor observed" \
  || no "the router is layer-only" "a layer rule presumes you know your layer; it fails on 'a documented thing does not work', which is where misrouting happens"
grep -qiE 'executes it.{0,40}describes it|surface that \*\*executes\*\*' "$C" \
  && ok "the executes-vs-describes rule is present" \
  || no "the anchor router entry is missing" "the doc is canonical and the behaviour may not be — that distinction IS the router"
grep -qiE 'file against canonical|we route it' "$C" \
  && ok "there is a default for the unsure contributor" \
  || no "no default when the router does not decide" "a router with no fallback converts uncertainty into an unfiled issue, which costs the fix"

echo "-- 4. canonical does NOT duplicate the siblings' setup instructions --"
# The prohibition from the keyed item: their setup/gates are theirs, and a second
# copy drifts. Canonical's job is the door, not the doorway.
dup=0
for pat in 'npm install' 'npm run dist' 'electron-builder' 'vsce ' 'ovsx ' 'pnpm install'; do
  grep -qF "$pat" "$C" 2>/dev/null && { dup=$((dup+1)); printf '     DUPLICATED: %s\n' "$pat"; }
done
[ "$dup" = "0" ] && ok "no sibling build/setup commands copied into canonical" \
  || no "$dup sibling setup command(s) copied here" "their CONTRIBUTING owns those; a second copy drifts the day they change it"
grep -qiE 'read theirs|their own .?CONTRIBUTING' "$C" \
  && ok "canonical points at the siblings' own guides" \
  || no "canonical does not hand off to the siblings' guides"

echo "-- 5. CHEATSHEET is a PHRASEBOOK: it teaches what to SAY, not what to type --"
# The operator's correction, and it reframes the file: someone running the desktop app never
# types a command — they ask a session, which does the work including the parts needing a
# terminal, a second session, or a file edited on their behalf. So the highest-value content
# is what to SAY. A command table cannot teach that, and none of these capabilities announce
# themselves: you have to know they exist to ask for them.
grep -q 'Just say it' "$H" && ok "the phrasebook section exists" || no "CHEATSHEET has no phrasebook" "a command reference cannot teach a non-technical operator what their session can do"
sayc=$(grep -c 'Say something like' "$H")
[ "${sayc:-0}" -ge 3 ] && ok "prompts are phrased as things to say ($sayc tables)" \
  || no "only $sayc 'say something like' table(s)" "rows written as 'do this' assume a terminal; the point is the words"
grep -qiE 'pick the right tier yourself' "$H" \
  && ok "covers letting the session choose the tier" \
  || no "no 'you pick the tier' example" "often the best move — the session knows the task's cognitive load better than the operator does at that moment"
for cap in 'voice gate' 'atlas' 'Ingest this' 'deep research'; do
  grep -qi "$cap" "$H" && ok "phrasebook covers: $cap" || no "phrasebook omits: $cap"
done
grep -qiE 'USER.md|INTENT.md' "$H" && ok "covers personalization and autonomy by prompt" \
  || no "no prompts for USER.md / INTENT.md" "an operator who does not know these are editable by asking will hand-edit them or never change them"
grep -qiE 'take it from here|autonomy is supposed to grow' "$H" \
  && ok "tells the operator autonomy is meant to move" \
  || no "autonomy reads as fixed" "a trust contract nobody knows is negotiable is a ceiling"

echo "-- 6. every agent and skill the phrasebook names actually EXISTS --"
# A phrasebook full of prompts that resolve to nothing is worse than no phrasebook. These are
# extracted from the file and checked against the tree, so a rename breaks the build rather
# than an operator's morning.
# EXTRACTED FROM THE DOCUMENT, never a list kept here. The first version walked a
# hardcoded list of agent names and `continue`d on any it did not find — so renaming an
# agent in the doc made the check SKIP it, and a mutation replacing a real agent with an
# invented one passed. The check was testing its own list. Third instance of that shape in
# one day; the fix is always the same: read the artifact under test.
miss=0; checked=0
# Single-word names count too (`lawyer`, `accountant`) — the first pattern required a
# hyphen and silently skipped them, which is how a threshold of 6 failed on a doc that
# summons eight. The "the `x`" framing below is what discriminates a summonable name from
# an ordinary code span, so the extraction can afford to be wide.
NAMES=$(grep -oE '`[a-z][a-z0-9-]{2,}`' "$H" | tr -d '`' | sort -u)
for n in $NAMES; do
  # A backticked hyphenated token is a claim only if it is presented as an agent or a skill.
  hit_a=$(find agents -name "$n.md" -print -quit 2>/dev/null)
  hit_s=""; [ -f "skills/aios/$n/SKILL.md" ] && hit_s=1
  # tokens that are neither are ordinary prose or paths — ignore unless the doc frames them
  # as something to summon
  if grep -qiE "(the|our|a) \`$n\`" "$H" 2>/dev/null; then
    checked=$((checked+1))
    [ -n "$hit_a" ] || [ -n "$hit_s" ] || { miss=$((miss+1)); printf '     NAMED BUT MISSING: %s (no agent or skill by that name)\n' "$n"; }
  fi
done
[ "$checked" -ge 6 ] && ok "checked $checked summoned names, extracted from the doc" \
  || no "only $checked names extracted" "the extraction is matching too little to be a real check — fix the pattern, do not hardcode a list"
[ "$miss" = "0" ] && ok "every agent/skill the phrasebook tells you to summon exists" \
  || no "$miss named capability/ies do not exist" "a prompt that resolves to nothing teaches the operator the docs lie"

echo "-- 7. it still ROUTES rather than restating, and sits above the terminal path --"
grep -qiE 'running|alive' "$H" && ok "carries the surface-liveness caveat" || no "omits the liveness caveat"
grep -qiE 'you wanted a subagent' "$H" && ok "carries the wrong-primitive tell" || no "no primitive-choice tell"
grep -qF 'orchestration-ladder' "$H" && ok "routes to the ladder skill" || no "does not route to the ladder"
grep -qF 'agents/_index.md' "$H" && ok "routes to the agent registry" || no "does not route to the registry"
wl=$(grep -n 'from a terminal' "$H" | head -1 | cut -d: -f1)
ql=$(grep -n 'Just say it' "$H" | head -1 | cut -d: -f1)
if [ -n "$wl" ] && [ -n "$ql" ]; then
  [ "$ql" -lt "$wl" ] && ok "the phrasebook precedes the terminal table (line $ql < $wl)" \
    || no "the terminal table comes first (line $wl < $ql)" "opening a new App operator's quick-reference with shell commands teaches them the AIOS is a terminal product that happens to have an app"
  grep -qiE 'advanced path|plain clone with no surface' "$H" && ok "the terminal section is labelled the fallback" || no "the terminal section is not framed as the fallback"
else
  no "could not locate both sections" "phrasebook=$ql terminal=$wl — fix this locator, do not delete the check"
fi
n=$(awk '/^### Just say it/{f=1} f&&/^### Launching from a terminal/{exit} f&&/^```/{c++} END{print c+0}' "$H")
[ "${n:-0}" -eq 0 ] && ok "no code fences in the phrasebook" \
  || no "the phrasebook contains $n code fence(s)" "a fence here turns a phrasebook back into a command reference, and then it drifts from the spec it copied"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

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
# The operator's literal instruction was "all 'Do this' should be 'Prompt something like this'".
# This assertion previously hard-coded 'Say something like' -- the wording a session substituted
# because it read better -- which made the GUARD the authority for the deviation: the doc could not
# be corrected without failing CI. A check must assert the requirement, never a paraphrase of it.
sayc=$(grep -c 'Prompt something like this' "$H")
[ "${sayc:-0}" -ge 3 ] && ok "prompts are phrased as things to say ($sayc tables)" \
  || no "only $sayc 'prompt something like this' table(s)" "rows written as 'do this' assume a terminal; the point is the words"
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
  # A backticked name is a claim only if the doc frames it as something to reach for.
  # It RESOLVES if it has any of the four homes a capability can live in — an agent file,
  # a bundled skill, a slash command, or a wrapper the installer defines. All four are
  # checked because the framing filter cannot tell them apart: the doc says "the `lawyer`"
  # and "the `spawn` wrappers" in the same grammar, and only the second is a shell function.
  # Resolving against agents+skills ALONE reported `spawn` missing — a false positive on a
  # name that is real, documented, and invocable. The check's promise is that a name the
  # phrasebook hands the operator resolves to SOMETHING they can invoke, not that it is
  # specifically an agent.
  hit=$(find agents -name "$n.md" -print -quit 2>/dev/null)
  [ -n "$hit" ] || { [ -f "skills/aios/$n/SKILL.md" ] && hit=1; }
  [ -n "$hit" ] || { [ -f "plugins/aios/commands/$n.md" ] && hit=1; }
  # a wrapper is a shell function the installer emits — no file bears its name
  [ -n "$hit" ] || { grep -qE "^(function )?$n *\\(\\) *\\{" hooks/claude-identity/install-wrappers.sh 2>/dev/null && hit=1; }
  if grep -qiE "(the|our|a) \`$n\`" "$H" 2>/dev/null; then
    checked=$((checked+1))
    [ -n "$hit" ] || { miss=$((miss+1)); printf '     NAMED BUT MISSING: %s (no agent, skill, command or wrapper by that name)\n' "$n"; }
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

echo "-- 8. the terminal path is not left behind --"
# Operator-reported after the phrasebook landed: the phrasebook could ask for a tier, a
# model and a scoped profile, and the terminal table had NONE of those flags — while still
# teaching `export CLAUDE_MODEL` in the shell rc, which CLAUDE.md calls the footgun that
# --model exists to remove. A doc that teaches the deprecated path as the only path is worse
# than one that omits it: the omission is discoverable, the wrong answer is not.
for flag in -- '--tier' '--model' '--profile'; do
  [ "$flag" = "--" ] && continue
  grep -qF "spawn $flag" "$H" && ok "the terminal path documents \`spawn $flag\`" \
    || no "the terminal path omits \`spawn $flag\`" "the phrasebook can ask for it; a terminal operator must be able to type it"
done
# The footgun may be WARNED about but never taught. Distinguish the two by looking for the
# warning marker on the same line — prose may discuss it, a table row may not offer it.
bad=$(grep -n 'export CLAUDE_MODEL' "$H" | grep -vciE "don't|do not|footgun|⚠")
[ "${bad:-0}" -eq 0 ] && ok "the global export appears only as a warning, never as an instruction" \
  || no "$bad line(s) still teach export CLAUDE_MODEL" "miss the revert and every future terminal is pinned; --model scopes to the one spawn"
grep -qiE 'nothing here is a lesser path|same capabilities, same flags' "$H" \
  && ok "the terminal path is framed as equal, not remedial" \
  || no "the terminal section reads as second-class" "it is the only path for a plain clone with no surface installed"

echo "-- 9. the terminal path is grouped, not one flat list --"
# It had grown into fifteen rows mixing launching, model choice, wrapper install and company
# mounting in a single table — four concerns, one list, no ordering an operator could use.
groups=$(awk '/^### Launching from a terminal/{f=1} f&&/^## §2/{exit} f&&/^\*\*[A-Z]/{c++} END{print c+0}' "$H")
[ "${groups:-0}" -ge 4 ] && ok "grouped into $groups labelled sections" \
  || no "only $groups group heading(s)" "fifteen rows spanning launching, model choice, setup and context-mounting is a list, not a reference"

echo "-- 10. the mechanical dance is EXECUTABLE, not just named --"
# WHY. The file routed you to the right repo and then said "fork -> branch -> pull request"
# once, in five words, with zero commands in 263 lines. That is not a gap in polish: the
# install flow points an operator's `origin` at their OWN private vault repo and leaves
# canonical as a `repo=` line in `.aios-update` rather than a remote -- so the five-word
# clause has no starting point from where an operator actually stands. Worse, the obvious
# reading of it (branch from your vault, push to a fork) puts `context/observed/` in the
# PR diff, which is the one violation this file calls non-negotiable. So the commands are
# load-bearing, and the vault-leak warning is the reason they exist.
#
# These greps target the COMMANDS and the concrete tell, never the prose around them --
# a check that restates the sentence it is checking only tests its own restatement.
for cmd in 'gh repo fork' 'git remote add upstream' 'git checkout -b' 'git push -u origin' 'gh pr create'; do
  grep -qF "$cmd" "$C" && ok "documents \`$cmd\`" \
    || no "no \`$cmd\`" "the dance is not executable without it"
done
# the commands must be COPYABLE -- i.e. inside a fenced block, not described in prose
fenced=$(awk '/^```bash/{f=1;next} /^```/{f=0} f' "$C" | grep -cE '^(gh|git) ')
[ "${fenced:-0}" -ge 6 ] && ok "$fenced git/gh lines sit in fenced blocks (copyable)" \
  || no "only ${fenced:-0} fenced command lines" "commands described in prose cannot be pasted"

# the accident this section exists to prevent
grep -qF '.aios-update' "$C" && ok "names the vault-vs-contrib-clone tell (.aios-update)" \
  || no "no concrete tell for 'is this tree a vault?'" "without a mechanical test the rule is advice"
grep -qF 'context/observed/' "$C" && ok "names the path that leaks if you push from a vault" \
  || no "the leak is abstract" "'personal data' is not actionable; the path is"
grep -qE 'branch from (CANONICAL|`?upstream/main`?)' "$C" && ok "says which base to branch from" \
  || no "no base-branch rule" "a branch cut from a stale fork main produces a diff nobody can review"
# a refused push is the SUCCESS signal here, and a contributor who does not know that files a bug
grep -qiE 'refused, and that is correct|permission error there means' "$C" \
  && ok "pre-empts the refused-push-to-canonical confusion" \
  || no "does not explain that no push access is expected" "reads as a broken setup"

# the session-facing half: this file is read by Claude sessions, not only humans
grep -qiE 'if you are a claude session' "$C" && ok "carries an explicit session-facing precondition" \
  || no "no session-facing guidance" "a human hits 'no push access' and thinks; a session does not"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

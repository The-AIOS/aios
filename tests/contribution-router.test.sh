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

echo "-- 5. CHEATSHEET answers the operating questions --"
for probe in 'spawn-inbox' 'orchestration-ladder' 'tier' 'agents/_index.md'; do
  grep -qF "$probe" "$H" && ok "CHEATSHEET references $probe" \
    || no "CHEATSHEET never mentions $probe" "it is the day-to-day index; an operator who cannot find this from here will not find it"
done
grep -qiE 'running pid|alive, not when' "$H" \
  && ok "CHEATSHEET carries the liveness rule (not directory-existence)" \
  || no "CHEATSHEET omits the liveness rule" "a request written when no surface is alive is never picked up AND never reported — that is the trap worth one line"
grep -qiE 'you wanted a subagent' "$H" \
  && ok "CHEATSHEET carries the wrong-primitive tell" \
  || no "CHEATSHEET has no primitive-choice tell"

echo "-- 6. the operating examples sit ABOVE the terminal path --"
# Operator's call: the terminal table is the advanced / no-surface fallback, so it
# must not be the first thing a new App user meets.
wl=$(grep -n 'from a terminal' "$H" | head -1 | cut -d: -f1)
ql=$(grep -n 'Getting a worker' "$H" | head -1 | cut -d: -f1)
if [ -n "$wl" ] && [ -n "$ql" ]; then
  [ "$ql" -lt "$wl" ] && ok "the worker examples precede the terminal table (line $ql < $wl)" \
    || no "the terminal table comes first (line $wl < $ql)" "opening a new App operator's quick-reference with shell commands teaches them the AIOS is a terminal product that happens to have an app"
  grep -qiE 'advanced path|plain clone with no surface' "$H" \
    && ok "the terminal section is labelled as the advanced/no-surface path" \
    || no "the terminal section is not framed as the fallback"
else
  no "could not locate both sections" "worker-examples=$ql terminal=$wl — fix this locator, do not delete the check"
fi

echo "-- 7. CHEATSHEET stays an index: it ROUTES rather than restating --"
# It must not become a second copy of the ladder or the bus protocol. Proxy: the
# additions reference their owning surfaces, and no code fence reimplements them.
grep -qiE 'Full protocol|Depth, plus how' "$H" \
  && ok "the additions hand off to their owning docs" \
  || no "the additions do not route onward" "a cheatsheet that explains everything is a manual, and then it drifts from the spec it copied"
n=$(awk '/^### Getting a worker/{f=1} f&&/^### Launching from a terminal/{exit} f&&/^```/{c++} END{print c+0}' "$H")
[ "${n:-0}" -eq 0 ] && ok "no code blocks reimplementing the protocol in the new sections" \
  || no "the new sections contain $n code fence(s)" "worked examples belong in tables that point at the spec; a fence here becomes a second implementation"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

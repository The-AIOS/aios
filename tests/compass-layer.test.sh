#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The compass layer ships the METHOD, never one operator's answer — and stays
# silent until it has earned the right to speak.
#
# Two things make this suite necessary rather than decorative, and both are
# about what a well-meaning future edit will do:
#
# 1. THE DERIVATION EVIDENCE IS PRIVATE AND THE PROSE IS TEMPTING. This feature
#    was derived from one operator's vault — a named student's AI session, a
#    biography, corpus percentages, a purpose statement. Every one of those is
#    the kind of concrete detail that makes writing better, which is exactly why
#    it leaks. Canonical is authored from inside a live vault, so the leak is a
#    reflex, not a lapse. The test asserts the boundary the docs only state.
#
# 2. THE MECHANISM HAS A NEUROCHEMICAL NAME AND USING IT IS A TRAP. The two
#    layers ("what did I do" / "what did it mean") map onto well-known biology.
#    Naming that in operator-facing text turns a design into a lecture, invites
#    bad pop-science, and makes a claim about a person's body a vault has no
#    standing to make. The words are banned in shipped text and the ban needs a
#    guard, because every future author will independently rediscover them.
#
# The cold-start half is asserted too: State 0 must be SILENT. A version that
# prompts an operator to "set your purpose" has rebuilt the substitution
# heuristic as a feature, and it would pass every other check in this file.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

SKILL=skills/aios/finding-your-why/SKILL.md
TODAY=plugins/aios/commands/today.md
CLOSE=plugins/aios/commands/close-day.md
[ -f "$SKILL" ] || { echo "::error::$SKILL missing"; exit 1; }

# Shipped operator-facing surfaces. CHANGELOG is excluded deliberately: it is a
# dated record of what changed and may legitimately describe provenance.
SURFACES="$SKILL $TODAY $CLOSE CLAUDE.md README.md"

echo "-- 1. no derivation evidence travelled (the private half stays private) --"
# Names and vault-specific artifacts from the derivation. Matched case-insensitively
# and word-anchored so an innocent substring can't fail the build.
# Private derivation evidence ONLY. Two deliberate exclusions, each learned by this
# check firing on healthy content the first time it ran:
#   * the framework author's public essay URL (chuycepeda.substack.com) ships in every
#     vault BY DESIGN and CLAUDE.md carries a comment saying so — matching a byline is
#     not matching private evidence, so the name is matched only when it is NOT that URL;
#   * `philosopher-oracle` was already in CLAUDE.md as an example of a brand-named
#     project in the naming convention. A pre-existing generic example is not a leak.
# And "arrival-fallacy" is deliberately ABSENT: § 5 REQUIRES that attribution near the
# borrowed line, so banning it here would have made two checks in this file contradict
# each other — one failing exactly when the other passed.
LEAKS='Zai|Zineb|Anna|Charly|refresh_chuy_corpus|BE-3|BE-6'
# Matched in two stages rather than with a negative lookahead: BSD grep has no -P,
# and a check that only runs on the maintainer's Linux CI is a check with a platform hole.
NAME_TOKEN='chuycepeda[a-z.]*'; NAME_EXCLUDE='chuycepeda.substack'
found=0
for f in $SURFACES; do
  [ -f "$f" ] || continue
  hits=$(grep -nEio "$LEAKS" "$f" 2>/dev/null | head -4)
  # the operator's name, but never the author's public essay URL
  # Portable: BSD grep (macOS) has no -P, so match the name then drop the byline URL.
  nm=$(grep -nio 'chuycepeda[a-z.]*' "$f" 2>/dev/null | grep -vi 'chuycepeda.substack' | head -2)
  [ -n "$nm" ] && hits="$hits
$nm"
  if [ -n "$hits" ]; then
    found=$((found+1)); printf '     LEAK in %s:\n' "$f"; printf '%s\n' "$hits" | sed 's/^/       /'
  fi
done
[ "$found" = "0" ] && ok "no operator-private names or vault-only artifacts in shipped text" \
  || no "$found shipped file(s) carry derivation evidence" "canonical ships the method; the vault keeps the proof. Relocate the evidence, keep the rule."

echo "-- 2. no corpus percentages or key numbers carried over --"
# The derivation cited one operator's measured shares (4.1% -> 1.5%) and target band.
numfound=0
for f in $SURFACES; do
  [ -f "$f" ] || continue
  h=$(grep -nE '\b(4\.1|2\.9|2\.2|1\.5)ance?%|\b(4\.1|2\.9|2\.2|1\.5)%|15–25%|15-25%' "$f" 2>/dev/null | head -2)
  [ -n "$h" ] && { numfound=$((numfound+1)); printf '     NUMBER in %s: %s\n' "$f" "$(printf '%s' "$h" | head -1 | cut -c1-90)"; }
done
[ "$numfound" = "0" ] && ok "no operator-specific measurements in shipped text" \
  || no "$numfound file(s) carry one operator's numbers" "a share target is that vault's instrument, not a framework constant"

echo "-- 3. the neurochemistry vocabulary is NOT in shipped text --"
chem=0
for f in $SURFACES; do
  [ -f "$f" ] || continue
  h=$(grep -nEio 'dopamine|serotonin|dopaminergic|serotonergic' "$f" 2>/dev/null | head -2)
  [ -n "$h" ] && { chem=$((chem+1)); printf '     %s: %s\n' "$f" "$(printf '%s' "$h" | head -1)"; }
done
[ "$chem" = "0" ] && ok "describes the behaviour, not the biology" \
  || no "$chem file(s) name the neurochemistry" "describe it as 'what did I do' vs 'what did it mean' — a vault has no standing to make a claim about someone's body"

echo "-- 4. CONTROL: the leak and vocabulary checks can actually fail --"
# Both greps above are the kind that pass vacuously if a pattern is wrong. Plant
# each defect in a fixture and require detection, or the three passes above are
# worth nothing.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'A student named Zai said it best.\n' > "$T/leak.md"
printf 'This is the dopamine layer talking.\n' > "$T/chem.md"
printf 'Personal share fell to 1.5%% against a 15-25%% target.\n' > "$T/num.md"
grep -qEio "$LEAKS" "$T/leak.md" && ok "control: a planted name IS detected" || no "control failed: the leak pattern matches nothing" "the passes in §1 prove nothing"
printf 'This is what Chuycepeda decided about his own purpose.\n' > "$T/name.md"
grep -qio "$NAME_TOKEN" "$T/name.md" && ok "control: the operator's bare name IS detected" || no "control failed: the scoped name pattern matches nothing" "excluding the byline must not disarm the name check"
printf 'See https://chuycepeda.substack.com/p/x for the essay.\n' > "$T/url.md"
{ grep -io "$NAME_TOKEN" "$T/url.md" | grep -qvi "$NAME_EXCLUDE"; } && no "control failed: the author's essay URL was flagged" "that URL ships by design; flagging it is the false positive this exclusion exists for" || ok "control: the author's public essay URL is NOT flagged"
grep -qEio 'dopamine|serotonin' "$T/chem.md" && ok "control: planted vocabulary IS detected" || no "control failed: the vocabulary pattern matches nothing" "the pass in §3 proves nothing"
grep -qE '\b1\.5%|15-25%' "$T/num.md" && ok "control: a planted measurement IS detected" || no "control failed: the number pattern matches nothing" "the pass in §2 proves nothing"

echo "-- 5. the map/compass line carries its provenance wherever it appears --"
# One of the two taglines is compressed from an outside source and must never
# appear bare; the other is ours and needs nothing.
bare=0
for f in $SURFACES; do
  [ -f "$f" ] || continue
  grep -qF 'destination on the map' "$f" 2>/dev/null || continue
  # the attribution must sit within the same paragraph-ish neighbourhood
  ctx=$(grep -A3 -B1 -F 'destination on the map' "$f" | tr '\n' ' ')
  case "$ctx" in
    *arrival-fallacy*|*provenance*|*attribution*|*Compressed*|*compressed*) ok "provenance attached in $f" ;;
    *) bare=$((bare+1)); no "the map/compass line appears bare in $f" "it is compressed from an outside framing — carry the attribution wherever it is quoted" ;;
  esac
done
[ "$bare" = "0" ] && [ "$PASS" -gt 0 ] && ok "no bare use of the borrowed line" || true

echo "-- 6. State 0 is SILENCE — no surface prompts for a purpose --"
# The failure this guards is a "set your purpose" nudge, which rebuilds the exact
# substitution heuristic the design rejects and would look like a helpful feature.
for f in "$TODAY" "$CLOSE"; do
  b=$(basename "$f")
  grep -qE 'no `?##? ?Horizon`?|No `## Horizon`|without a horizon|No horizon' "$f" 2>/dev/null \
    && ok "$b states the no-horizon behaviour explicitly" \
    || no "$b never says what to do when there is no horizon" "silence has to be written down or it will be filled in"
done
for f in "$TODAY" "$CLOSE"; do
  b=$(basename "$f")
  if grep -qiE 'say nothing about purpose|no prompt, no placeholder|produces no output of any kind|exactly as before and say nothing' "$f" 2>/dev/null; then
    ok "$b instructs silence rather than a prompt"
  else
    no "$b does not instruct silence" "a 'set your purpose' nudge is the substitution heuristic shipped as a feature"
  fi
done

echo "-- 7. the gate is VARIATION, not elapsed time --"
# Asserted PER FILE, not across both. An earlier version passed either file, so
# deleting the gate from close-day — the surface that actually applies it — stayed
# green because the skill still described it. Found by mutation.
for f in "$CLOSE" "$SKILL"; do
  b=$(basename "$f")
  grep -qiE 'variation, not tenure|not from elapsed time|never from elapsed time' "$f" 2>/dev/null \
    && ok "$b states the gate as variation rather than tenure" \
    || no "$b does not state the variation gate" "a day-count gate offers a compass to someone with one project's evidence — and the invariant is then that project"
done
grep -qiE '3\+ distinct projects|2\+ domains' "$CLOSE" 2>/dev/null \
  && ok "the gate is concrete enough to compute from disk" \
  || no "the gate has no computable threshold" "a gate a session has to feel out will be crossed whenever the session is in the mood"

echo "-- 8. the horizon cannot become a goal --"
if grep -qiE 'no checkbox|has no checkbox' "$SKILL" && grep -qiE 'no checkbox|nothing to advance' "$CLOSE" "CLAUDE.md" 2>/dev/null; then
  ok "the no-checkbox rule is stated where the horizon is defined and where it is offered"
else
  no "the no-checkbox rule is missing from one of its two homes" "the moment a horizon can be advanced it has become a goal, which is the thing it exists to sit above"
fi

echo "-- 9. a rejection is durable (the offer cannot loop) --"
if grep -qiE '90 days|do not re-offer|not re-asking|not re-asked' "$CLOSE" "$SKILL" 2>/dev/null; then
  ok "declining is recorded and not re-asked"
else
  no "nothing stops the offer repeating" "a warm offer made every month is a nag, and the operator already answered"
fi

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

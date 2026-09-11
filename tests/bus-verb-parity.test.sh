#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The bus verb set is documented TWICE — the two copies must agree (AI-150)
#
# Canonical states the spawn-inbox verbs in exactly two places: CLAUDE.md
# § Spawning Sessions, which every session loads at startup, and the
# orchestration-ladder skill, which a session loads when it is deciding how to
# delegate. They are two copies of one fact, both hand-maintained, and until
# this suite nothing compared them.
#
# That is the shape that has already cost this repo real money elsewhere: the
# Google API set was written in six places and every copy disagreed. Here the
# failure would be worse than confusing, because the two documents are read at
# different moments — a verb present in the skill and missing from CLAUDE.md is
# invisible to a session that never had a reason to load the skill.
#
# The verbs themselves are the App's to define; canonical only mirrors them. So
# this asserts AGREEMENT and the presence of the rules that change an agent's
# behaviour, never a hardcoded verb list of its own — a canonical-side list
# would be a third copy, which is the thing being prevented.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

CM="CLAUDE.md"
OL="skills/aios/orchestration-ladder/SKILL.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

for f in "$CM" "$OL"; do [ -f "$f" ] || { printf '  FAIL  %s missing\n' "$f"; exit 1; }; done

# Every verb named as an `"action":"…"` payload, deduped.
verbs(){ grep -oE '"action" *: *"[a-z]+"' "$1" | grep -oE '"[a-z]+"$' | tr -d '"' | sort -u; }

echo "── 1. both documents name the same verb set ──"
verbs "$CM" > "$TMP/cm"; verbs "$OL" > "$TMP/ol"
NC="$(grep -c . "$TMP/cm" || true)"; NO="$(grep -c . "$TMP/ol" || true)"
if [ "$NC" -lt 3 ] || [ "$NO" -lt 3 ]; then
  no "extracted $NC verbs from CLAUDE.md and $NO from the skill — the extractor is broken, not the docs" \
     "$(paste -d'|' "$TMP/cm" "$TMP/ol" 2>/dev/null | head -5)"
else
  ok "extractor found $NC verbs in CLAUDE.md, $NO in the skill"
  ONLY_CM="$(comm -23 "$TMP/cm" "$TMP/ol" | tr '\n' ' ')"
  ONLY_OL="$(comm -13 "$TMP/cm" "$TMP/ol" | tr '\n' ' ')"
  if [ -z "$ONLY_CM$ONLY_OL" ]; then
    ok "identical verb sets: $(tr '\n' ' ' < "$TMP/cm")"
  else
    no "the two verb lists disagree" \
       "only in CLAUDE.md: ${ONLY_CM:-none}
        only in the skill:  ${ONLY_OL:-none}
        both are read, at different moments — a verb in one and not the other is invisible to whoever loads the other"
  fi
fi

echo "── 2. the rules that change an agent's BEHAVIOUR are in both ──"
# A verb list alone is not enough for these two. An agent that writes inbox
# files needs the refusal rule wherever it is reading, because a misspelled verb
# used to degrade to spawn harmlessly and now does not.
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  grep -qiE 'unknown .*action|unrecognised .*action|an unknown `action`|verb you WRITE and spell wrong' "$f" \
    && ok "$label states the unknown-action refusal" \
    || no "$label does not state that an unknown action is refused" \
          "before resume this degraded to spawn harmlessly; now the outcomes differ"
  # The stamp an agent can actually find is the HTML comment the fulfiller writes:
  # `aios-spawn-inbox: contract N`. `INBOX_CONTRACT` is the symbol's name inside the
  # App and Glass source and appears nowhere in the README -- so a doc that sends an
  # agent looking for it describes a check that cannot be performed. Verified against
  # the shipped v0.9.5 tree before this assertion was written.
  grep -qF 'aios-spawn-inbox: contract' "$f" \
    && ok "$label names the stamp as it actually appears in the README" \
    || no "$label does not name the real stamp text" \
          "an agent greps the file; the marker there is 'aios-spawn-inbox: contract N', not INBOX_CONTRACT"
done

echo "── 2b. both state that verb matching ignores case and space ──"
# normalizeVerb() trims and lowercases before matching, so `"Resume"` resolves.
# Without this an agent reading a refusal blames its own formatting and starts
# quoting differently, instead of reading the one thing a refusal actually means:
# the verb is not implemented here.
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  grep -qiE 'case and surrounding whitespace|[Cc]ase and surrounding space' "$f" \
    && ok "$label states case/space are not significant" \
    || no "$label does not say matching ignores case and space" \
          "a refusal then reads as a formatting problem rather than an unknown verb"
done

echo "── 3. the contract NUMBER agrees across both ──"
# Two documents each asserting a version is a second way for them to drift.
cnum(){ grep -oE 'aios-spawn-inbox: contract[^0-9]{0,20}[0-9]+|contract \*\*[0-9]+\*\*|contract \*\*?[0-9]+' "$1" | grep -oE '[0-9]+' | sort -u | tr '\n' ' '; }
A="$(cnum "$CM")"; B="$(cnum "$OL")"
if [ -z "$A" ] || [ -z "$B" ]; then
  no "could not read a contract number from both (CLAUDE.md='$A' skill='$B')"
elif [ "$A" = "$B" ]; then
  ok "both state contract $A"
else
  no "contract number disagrees — CLAUDE.md says '$A', the skill says '$B'" \
     "a fulfiller on the older contract spawns a duplicate when handed a resume"
fi

echo "── 4. canonical does not author the generated README ──"
# CLAUDE.md says spawn-inbox/README.md is rewritten by whichever surface boots,
# so it cannot drift from the running code. Canonical shipping one would
# manufacture exactly the drift the generation exists to prevent.
FOUND="$(find . -path ./.git -prune -o -name 'README.md' -path '*spawn-inbox*' -print 2>/dev/null | grep . || true)"
[ -z "$FOUND" ] \
  && ok "no spawn-inbox/README.md in canonical — it stays generated" \
  || no "canonical ships a spawn-inbox README: $FOUND" \
        "CLAUDE.md calls that file generated-not-authored; shipping one re-creates the drift it prevents"

echo "── 5. resume is documented as resolving from TRANSCRIPTS, not the registry ──"
# This is the half most likely to be mirrored wrong, because CLAUDE.md's
# addressing rule says the registry is the only truth -- and for resume it
# cannot be: a closed session is absent from the registry by design.
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  grep -q 'resume' "$f" || continue
  grep -qiE 'transcript' "$f" \
    && ok "$label resolves resume from the transcripts" \
    || no "$label documents resume without naming the transcripts" \
          "the registry holds only RUNNING sessions, so it cannot resolve a closed one"
done
grep -qiE 'registry is the only truth' "$CM" && {
  grep -qiE 'LIVE session — the session registry|cannot answer for .*resume|only for .*live' "$CM" \
    && ok "CLAUDE.md scopes the registry rule to live sessions" \
    || no "CLAUDE.md still claims the registry is the ONLY truth, unqualified" \
          "resume falsifies that; an unqualified rule sends an agent to the one source that cannot answer"
}

echo "── 6. CONTROL — a verb added to one list only must FAIL ──"
# Without this the parity check could pass by extracting nothing from both.
mkdir -p "$TMP/ctl/skills/aios/orchestration-ladder"
sed 's/{"action":"kill"/{"action":"teleport"/' "$CM" > "$TMP/ctl/CLAUDE.md"
cp "$OL" "$TMP/ctl/skills/aios/orchestration-ladder/SKILL.md"
if grep -q 'teleport' "$TMP/ctl/CLAUDE.md"; then
  ok "injection assertion: the mutated fixture really carries the stray verb"
  verbs "$TMP/ctl/CLAUDE.md" > "$TMP/c1"; verbs "$TMP/ctl/skills/aios/orchestration-ladder/SKILL.md" > "$TMP/c2"
  if [ -n "$(comm -3 "$TMP/c1" "$TMP/c2")" ]; then
    ok "control: a verb in one list only is detected"
  else
    no "control: the mutated pair compared EQUAL" "this suite cannot detect the drift it exists for"
  fi
else
  no "control: mutation did not take — the control proves nothing"
fi

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

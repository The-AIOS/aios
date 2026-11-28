#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The spawn-inbox contract numbers are declared once, and both documents repeat them
#
# An agent is told to read the stamp in ~/.aios/spawn-inbox/README.md before it
# relies on a verb or a field. To use that number it has to know two others: the
# contract the verbs arrived in, and the contract in force now. Canonical used to
# state only the first, so a session reading CLAUDE.md could not tell that a
# contract with newer optional fields existed (#409).
#
# Both numbers live in ONE file, skills/aios/orchestration-ladder/
# inbox-contract.json: "current", and "verbs" (the contract the verb set arrived
# in). CLAUDE.md and the orchestration-ladder skill each repeat them in a
# sentence, because they are read at different moments; this suite fails when
# either sentence disagrees with the file.
#
# No network, no other repo: this is the check that blocks. Whether the declared
# number matches what the surfaces really stamp is a separate question, asked by
# tests/inbox-contract-stamp.test.sh.
#
# Written for bash 3.2. No dependencies.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

DECL="skills/aios/orchestration-ladder/inbox-contract.json"
CM="CLAUDE.md"
OL="skills/aios/orchestration-ladder/SKILL.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

nums(){ grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# A document as one line, so a sentence wrapped across two lines is still found. The
# leading blockquote marker goes first: CLAUDE.md states this inside a "> - " bullet,
# where a wrapped line would otherwise carry a ">" into the middle of the sentence.
flat(){ sed 's/^[> ]*//' "$1" | tr '\n' ' ' | tr -s ' '; }
# A declared number: the integer after "<key>" in the one file that owns it.
declared(){ [ -f "$1" ] && grep -oE "\"$2\" *: *[0-9]+" "$1" | grep -oE '[0-9]+$' | nums; }
# What a document says is current: every number in a "current contract is **N**" sentence.
doc_current(){ flat "$1" | grep -oE 'current contract is \*\*[0-9]+\*\*' | nums; }
# The contract a document says the verb set arrived in. Two exact phrasings, one per
# document, so a later mention of another contract in bold is not mistaken for this one.
doc_verbs(){ flat "$1" | grep -oE 'verb set above is contract \*\*[0-9]+\*\*|\*\*[0-9]+\*\* for this verb set' | nums; }
one(){ case "$1" in ''|*' '*) return 1 ;; esac; return 0; }

echo "── 1. one file declares both numbers ──"
CUR="$(declared "$DECL" current)"; VER="$(declared "$DECL" verbs)"
one "$CUR" && ok "declared current contract: $CUR" \
  || no "$DECL does not declare exactly one current contract (read: '$CUR')" \
        'expected JSON: {"current": N, "verbs": M}'
one "$VER" && ok "declared contract of the verb set: $VER" \
  || no "$DECL does not declare exactly one contract for the verb set (read: '$VER')" \
        'expected JSON: {"current": N, "verbs": M}'
if one "$CUR" && one "$VER"; then
  [ "$VER" -le "$CUR" ] && ok "the verb set's contract ($VER) is not newer than the current one ($CUR)" \
    || no "$DECL says the verbs arrived in contract $VER, newer than the current $CUR"
fi

echo "── 2. both documents state that number as current ──"
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  [ -f "$f" ] || { no "$f missing"; continue; }
  D="$(doc_current "$f")"
  if [ -z "$D" ]; then
    no "$label never says which contract is current" \
       "it needs the sentence 'the current contract is **N**'; a session that reads only this document cannot tell that fields newer than the verb set exist"
  elif [ -n "$CUR" ] && [ "$D" = "$CUR" ]; then
    ok "$label says the current contract is $D"
  else
    no "$label says the current contract is '$D', $DECL declares '${CUR:-nothing}'" \
       "change the number in one place only: $DECL, then repeat it here"
  fi
done

echo "── 3. both documents state the declared contract of the verb set ──"
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  [ -f "$f" ] || continue
  V="$(doc_verbs "$f")"
  if [ -z "$V" ]; then
    no "$label does not say which contract introduced the verb set" \
       "looked for 'the verb set above is contract **N**' or '**N** for this verb set'"
  elif [ -n "$VER" ] && [ "$V" = "$VER" ]; then
    ok "$label says the verb set arrived in contract $V"
  else
    no "$label says the verb set arrived in contract '$V', $DECL declares '${VER:-nothing}'"
  fi
done

echo "── 4. CONTROL — a document or a declaration that moves alone must be seen ──"
# Without this the suite could pass by extracting nothing from every file.
if one "$CUR" && one "$VER"; then
  NEXT=$((CUR+1)); i=0
  for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
    f="${pair%%:*}"; label="${pair#*:}"; i=$((i+1))
    flat "$f" | sed "s/current contract is \*\*$CUR\*\*/current contract is **$NEXT**/" > "$TMP/cur$i"
    [ "$(doc_current "$TMP/cur$i")" = "$NEXT" ] \
      && ok "control: $label changed to say current $NEXT is read as $NEXT, not as $CUR" \
      || no "control: $label changed to current $NEXT still reads as '$(doc_current "$TMP/cur$i")'" \
            "the extractor cannot see the sentence it exists to compare"
    flat "$f" | sed -e "s/verb set above is contract \*\*$VER\*\*/verb set above is contract **$NEXT**/" \
        -e "s/\*\*$VER\*\* for this verb set/**$NEXT** for this verb set/" > "$TMP/ver$i"
    [ "$(doc_verbs "$TMP/ver$i")" = "$NEXT" ] \
      && ok "control: $label changed to say the verbs arrived in $NEXT is read as $NEXT, not as $VER" \
      || no "control: $label changed to verbs $NEXT still reads as '$(doc_verbs "$TMP/ver$i")'"
  done
  printf '{"current": %s, "verbs": %s}\n' "$NEXT" "$NEXT" > "$TMP/decl.json"
  [ "$(declared "$TMP/decl.json" current) $(declared "$TMP/decl.json" verbs)" = "$NEXT $NEXT" ] \
    && ok "control: a declaration of $NEXT / $NEXT is read as such" \
    || no "control: the mutated declaration reads as '$(declared "$TMP/decl.json" current)' / '$(declared "$TMP/decl.json" verbs)'"
else
  no "control: nothing declared, so the control has nothing to mutate"
fi

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

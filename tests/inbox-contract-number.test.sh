#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The CURRENT spawn-inbox contract is declared once, and both documents repeat it
#
# An agent is told to read the stamp in ~/.aios/spawn-inbox/README.md before it
# relies on a verb or a field. To use that number it has to know two others: the
# contract the verbs arrived in, and the contract in force now. Canonical used to
# state only the first, so a session reading CLAUDE.md could not tell that a
# contract with newer optional fields existed (#409).
#
# The current number lives in ONE file, skills/aios/orchestration-ladder/
# inbox-contract.json. CLAUDE.md and the orchestration-ladder skill each repeat
# it in a sentence, because they are read at different moments; this suite fails
# when either sentence disagrees with the file.
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

# The declared number: the integer after "current" in the one file that owns it.
declared(){ [ -f "$1" ] && grep -oE '"current" *: *[0-9]+' "$1" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# What a document says is current: every number in a "current contract is **N**" sentence.
doc_current(){ grep -oE 'current contract is \*\*[0-9]+\*\*' "$1" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# The contract a document says the verb set arrived in.
doc_verbs(){ grep -oE 'contract \*\*[0-9]+\*\*|\*\*[0-9]+\*\* for this verb set' "$1" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

echo "── 1. one file declares the current contract ──"
CUR="$(declared "$DECL")"
case "$CUR" in
  '')    no "$DECL does not declare a current contract" \
            'expected one line of JSON: {"current": N}' ;;
  *' '*) no "$DECL declares more than one current contract: $CUR" ;;
  *)     ok "declared current contract: $CUR" ;;
esac

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

echo "── 3. the verb set's contract is not newer than the current one ──"
for pair in "$CM:CLAUDE.md" "$OL:the skill"; do
  f="${pair%%:*}"; label="${pair#*:}"
  [ -f "$f" ] || continue
  V="$(doc_verbs "$f")"
  case "$V" in
    '')    no "$label does not say which contract introduced the verb set" ;;
    *' '*) no "$label names more than one contract for the verb set: $V" ;;
    *)     if [ -n "$CUR" ] && [ "${CUR#* }" = "$CUR" ] && [ "$V" -le "$CUR" ]; then
             ok "$label: verbs arrived in contract $V, current is $CUR"
           else
             no "$label: verbs arrived in contract $V, which is newer than the declared current '${CUR:-nothing}'"
           fi ;;
  esac
done

echo "── 4. CONTROL — a document or a declaration that moves alone must be seen ──"
# Without this the suite could pass by extracting nothing from every file.
if [ -n "$CUR" ] && [ "${CUR#* }" = "$CUR" ]; then
  NEXT=$((CUR+1))
  sed "s/current contract is \*\*$CUR\*\*/current contract is **$NEXT**/" "$CM" > "$TMP/CLAUDE.md"
  [ "$(doc_current "$TMP/CLAUDE.md")" = "$NEXT" ] \
    && ok "control: a CLAUDE.md that says $NEXT is read as $NEXT, not as $CUR" \
    || no "control: the mutated CLAUDE.md still reads as '$(doc_current "$TMP/CLAUDE.md")'" \
          "the extractor cannot see the sentence it exists to compare"
  printf '{"current": %s}\n' "$NEXT" > "$TMP/decl.json"
  [ "$(declared "$TMP/decl.json")" = "$NEXT" ] \
    && ok "control: a declaration of $NEXT is read as $NEXT" \
    || no "control: the mutated declaration reads as '$(declared "$TMP/decl.json")'"
else
  no "control: nothing declared, so the control has nothing to mutate"
fi

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

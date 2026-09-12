#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Shipping files carry the RULE, never one operator's evidence
#
# CLAUDE.md § Git & Commit Conventions: canonical is authored from inside a live
# vault, so vault-personal references leak into it by reflex. Each one leaks both
# ways -- it exposes that operator's private state to everyone, and hands every
# other operator a pointer that resolves to nothing.
#
# Found by audit 2026-09-11: several shipping files carried dated incidents from
# one operator's week, a possessive reference to their vault, and an example that
# named real third parties who never agreed to appear in a public repo. All
# predated the audit by months, and none was a mistake anyone would repeat
# deliberately -- which is the point: the leak arrives as *good writing*, because
# concrete evidence is what makes a rule persuasive.
#
# THIS SUITE NAMES NOBODY, deliberately. A guard that hardcoded the offending
# names would re-publish them on every run and go stale the moment a different
# operator contributed. It matches the SHAPE of the leak instead:
#
#   a possessive reference to a NAMED person's vault ("<Name>'s vault"), as
#   opposed to "the operator's vault" / "the user's vault", which are correct and
#   everywhere. The possessor is tested against a closed list of generic words; a
#   real first name is not in it.
#
# A SECOND CHECK WAS WRITTEN AND DELETED, and the reason belongs here. It flagged
# any wikilink to a date-prefixed note -- the shape of the leak that named real
# third parties. On its first run it fired on the corrected example that replaced
# them, because a dated wikilink is exactly how the convention is DOCUMENTED and
# no regex distinguishes an invented surname from a real one. Per antifragile
# #105, a check that cannot tell an example from an instance is worse than no
# check: it trains the reader to ignore it. The residual risk is covered by
# review and by the rule being stated in CLAUDE.md, not by a pattern that cries
# wolf on its own fix.
#
# Per antifragile #105, each check ships with a CONTROL that plants the shape in a
# fixture and requires it to be caught -- and the checks scan only files that
# actually SHIP, since tests/ and .github/ never reach an operator vault.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The two shapes, defined once and reused by both the scan and its controls.
OWNED_VAULT="[A-Za-z][A-Za-z]+'s vault"
# The closed list of generic possessors. Everything here is correct writing and
# common; a person's name is not among them, which is the whole discriminator.
GENERIC="operator|user|teammate|peer|person|someone|anyone|everyone|contributor|author|maintainer|collaborator|your|their|its|today|session|client|reader|newcomer"

scan(){ # $1 = regex · prints "file:line  text" for shipping files only
  git ls-files | grep -vE '^(tests/|\.github/)' | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -nE "$1" "$f" 2>/dev/null | while IFS= read -r hit; do
      printf '%s:%s\n' "$f" "$hit"
    done
  done
}

echo "── 1. no shipping file names a PERSON's vault possessively ──"
# -i on the exemption: a heading or table cell capitalises ("Operator's vault"),
# and a generic possessor stays generic whatever its case. A real name is still
# absent from the list either way, so this loosens nothing that matters.
HITS="$(scan "$OWNED_VAULT" | grep -viE "($GENERIC)'s vault" | grep -v '^CHANGELOG.md' || true)"
[ -z "$HITS" ] && ok "every possessive vault reference uses a generic possessor" \
  || no "a shipped file names one person's vault:" "$HITS"

echo "── 2. CONTROLS — the shape must be caught, and correct writing must not be ──"
# Without these the suite reports clean just as convincingly when broken.
printf "caught in Alex's vault last spring: three files stale\n" > "$TMP/f1.md"
{ grep -qE "$OWNED_VAULT" "$TMP/f1.md" && ! grep -qE "($GENERIC)'s vault" "$TMP/f1.md"; } \
  && ok "control: a named person's vault is detected" \
  || no "control: the pattern does NOT match its own fixture"
for phrase in "the operator's vault" "the user's vault" "a teammate's vault" "today's vault state" "**Operator's vault** in a table heading"; do
  printf '%s\n' "measure it against $phrase, not a remembered one" > "$TMP/f2.md"
  if grep -qiE "($GENERIC)'s vault" "$TMP/f2.md"; then
    ok "control: \"$phrase\" is exempted, not flagged"
  else
    no "control: correct phrasing \"$phrase\" would be flagged" "a guard that fires on good writing gets switched off"
  fi
done

echo "── 3. the rule this enforces is stated where authors will read it ──"
grep -qiE 'stranger.s empty vault|for a stranger' CLAUDE.md \
  && ok "CLAUDE.md states the write-for-a-stranger rule" \
  || no "the rule is unstated" "a guard with no stated rule reads as arbitrary"

# NOTE ON SCOPE: CHANGELOG.md is excluded from check 1. It is append-only history
# whose older entries describe incidents in the words used at the time, and
# rewriting shipped history to satisfy a new guard would be the tail wagging the
# dog. New entries are governed by tests/changelog-entry-shape.test.sh instead.

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

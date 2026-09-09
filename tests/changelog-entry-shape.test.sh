#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A CHANGELOG entry is read by EVERY operator's session on EVERY /aios:update
# (the command's Step 1.5 shows every new entry). So a sentence written once
# here is re-read by every operator forever, and maintainer-internal prose is a
# permanent per-operator tax on reasoning that mattered to one reviewer once.
#
# WHY THIS EXISTS. This file drifted to 5,000-word entries twice while every
# individual paragraph looked worth keeping -- test counts, mutation runs,
# "deliberately NOT changed", naming deliberation, development archaeology, and
# a vendored-license aside about a fictional name in upstream sample data. An
# operator cannot act on any of it. Reported by an operator reading their own
# update: "what's the value for a user updating to know that?"
#
# SCOPE, stated rather than implied: this checks the NEWEST entry only -- the
# one currently being authored. Historical entries predate the rule and are not
# rewritten (that would churn content every operator has already synced past,
# for no gain). The guard is forward-facing by design.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
F=CHANGELOG.md
[ -f "$F" ] || { echo "::error::$F missing"; exit 1; }

# The newest entry = from the first "## YYYY-MM-DD" to the next one.
awk '/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/{n++} n==1' "$F" > "${TMPDIR:-/tmp}/aios-newest-entry.md"
E="${TMPDIR:-/tmp}/aios-newest-entry.md"
head -1 "$E" | sed 's/^/  entry under test: /'
[ -s "$E" ] && ok "newest entry extracted" || { no "could not extract the newest entry" "the check cannot run"; echo; echo "-- $PASS passed, $FAIL failed --"; exit 1; }

echo "-- 1. it answers the two questions an operator has --"
grep -qiE '^> \*\*What you can now do' "$E" && ok "opens with the capability read" \
  || no "no 'What you can now do'" "/aios:update leads with this section; without it the operator gets a file list"
grep -qiE 'What you need to do|Action required|nothing for you to do|no action' "$E" \
  && ok "states the action (or explicitly none)" \
  || no "no action statement" "an entry must say what to do, even when the answer is nothing"

echo "-- 2. maintainer-internal prose stays in the PR --"
# Each pattern is a CLASS with a real home elsewhere. Keyed to the phrasing that
# actually shipped, not to invented straw text.
check_ban () { # $1=label  $2=pattern  $3=where it belongs
  hits=$(grep -icE "$2" "$E")
  [ "$hits" -eq 0 ] && ok "no $1" \
    || no "$1 ($hits line(s))" "belongs in $3 — the operator cannot act on it"
}
check_ban "proof-of-work narrative"      'mutation-verified|mutation-tested|each mutation|the control is|controls? (pass|fired)|escaped the first pass' "the PR body"
check_ban "test inventories"             'tests/[a-z0-9-]+\.test\.sh \(|\([0-9]+ checks?\)|[0-9]+ assertions' "the PR body"
check_ban "non-change justification"     'deliberately not changed|left untouched on purpose|not part of this patch' "the PR body"
check_ban "development archaeology"      'took (two|three|four) tries|the first version (walked|had|used)|initially escaped' "the commit message / antifragile.md"
check_ban "naming deliberation"          'the first name was wrong|was .Horizon. for|chosen against a real alternative' "the spec that owns the concept"
check_ban "vendored-license asides"      "vendored upstream|anthropic's own sample data" "LICENSE-AUDIT.md"

echo "-- 3. the closing rule is stated where entries are written, and is satisfiable without CI --"
# WHY THE SECOND HALF. The rule was first drafted as "names the deterministic CHECK that catches
# its class" -- and `tests/` + `.github/` are Tier-0: they NEVER reach an operator vault, while
# `antifragile.md` is Tier-2 (canonical ships a seed with zero entries). So the file the rule
# governs is the operator's and the only thing it let them name was the maintainer's: a rule 100%
# of operators could never satisfy, landing in the file every one of them loads at session start.
# Same class as a fix placed where it cannot reach the population it governs.
CL=CLAUDE.md
grep -qiE 'may not close until it names' "$CL" && ok "the closing rule is in CLAUDE.md" \
  || no "no closing rule" "an entry that changes nothing is a permanent read cost with no payoff"
# SCOPED to the rule sentence itself. A file-wide OR alternation passed a mutation that
# reverted the RULE to "the deterministic check" while a later explanatory paragraph still
# mentioned hooks -- one survivor satisfied the check. Assert the requirement where it is
# normative, not wherever the words appear.
rule_line=$(grep -m1 'may not close until it names' "$CL")
printf '%s' "$rule_line" | grep -qiE 'hook' && printf '%s' "$rule_line" | grep -qiE 'structural change' \
  && ok "the mechanism is generalized beyond a CI check (in the rule sentence)" \
  || no "the rule names only a check" "an operator vault has no tests/ or .github/ -- Tier-0 never syncs, so the rule would be unsatisfiable for every operator"
grep -qiE 'explicit reason no mechanism can|reason no mechanism' "$CL" \
  && ok "'no mechanism can' is an allowed answer" \
  || no "no escape hatch" "judgment calls and operator-behaviour lessons cannot be caught mechanically; forbidding that answer forces a lie"
grep -qiE 'mechanism is now the memory|mechanism is the memory' "$CL" \
  && ok "states the compaction payoff" \
  || no "the payoff is unstated" "without it the rule reads as bookkeeping rather than the lever /aios:compact lacks"
# canonical hygiene: the rule must not carry the vault measurement that motivated it
# GENERIC on purpose. Hardcoding the numbers that motivated the rule would only ever catch
# THIS vault's measurement -- and would itself put a vault-specific figure in canonical's repo.
# Match the SHAPE of a vault measurement instead, so any contributor's numbers are caught too.
grep -qiE '[0-9]+ of [0-9]+ (antifragile )?entries|[0-9]+ (antifragile )?entries[,.]? (against|vs)|my vault|this vault (has|holds)' "$CL" \
  && no "a vault-specific measurement leaked into CLAUDE.md" "canonical must never carry a ratio measured on one operator's vault -- the seed ships zero entries, so it is undefined there" \
  || ok "no vault measurement in the canonical rule"

echo "-- 3. it fits the budget every operator pays for --"
w=$(wc -w < "$E" | tr -d ' ')
[ "$w" -le 1500 ] && ok "$w words (budget 1500)" \
  || no "$w words — over the 1500-word budget" "every operator's session reads this on every sync; cut the proof, keep the capability"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

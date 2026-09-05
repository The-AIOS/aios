#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The commerce bundle and the shipping-a-saas skill
#
# TWO CONTRACTS WORTH PINNING
#
# 1. THE BUNDLE COUNT FANS OUT TO NINE FILES. Adding a 7th agent bundle required
#    editing nine documents that each hand-maintain "6 bundles" — a stale-constant
#    shape this repo has been bitten by repeatedly (a housekeeping command said
#    "all 23 buckets" while 27 were live, silently gating three of them). A
#    hardcoded count in prose is a second implementation, and the one a session
#    obeys is whichever it reads first. This check derives the number.
#
# 2. THE COMMERCE BUNDLE'S OWN ARGUMENT IS FALSIFIABLE. It ships ONE agent, and
#    the reason is that the guidance it draws from explicitly rejects splitting
#    the conversational path into cooperating sub-agents. Adding shopping-agent
#    and merchant-agent as separate workers would contradict the very claim they
#    would implement. That is a rule with an expiry date if nobody guards it.
#
# The load-bearing content assertion is the harness boundary: money, inventory
# and other customers' data are enforced in CODE, never in a prompt. A prompt is
# a request; a guard is a guarantee. If that sentence ever leaves the agent file,
# the agent is actively dangerous rather than merely incomplete.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
SK=skills/aios/shipping-a-saas/SKILL.md
AG=agents/aios/commerce/commerce-agent-architect.md

echo "── the bundle count is not hardcoded anywhere stale ──"
TRUTH=$(ls -d agents/aios/*/ | wc -l | tr -d ' ')
ok "ground truth: $TRUTH bundles on disk"
stale=$(grep -rln '6 bundles\|six bundles\|6-bundle' --include='*.md' . 2>/dev/null | grep -v '^./vault/' | grep -v CHANGELOG || true)
[ -z "$stale" ] && ok "no document still claims 6 bundles" \
  || no "stale bundle counts remain" "$(printf '%s' "$stale" | tr '\n' ' ')"
# Control: the sweep must be capable of seeing a stale count.
TMP=$(mktemp); printf 'agents across 6 bundles\n' > "$TMP"
grep -q '6 bundles' "$TMP" && ok "control: the sweep DOES detect a planted stale count" \
  || no "CONTROL FAILED — the sweep cannot see what it looks for"
rm -f "$TMP"
grep -qF "$TRUTH bundles" agents/_index.md && ok "agents/_index.md states $TRUTH" || no "agents/_index.md count disagrees with disk"

echo "── the agent count agrees with disk in EVERY place it is written ──"
# One new bundle touches FIVE hand-maintained places: the purity allowlist, the
# existence loop, the _index table row, the _index total, and the registry
# section. Four of five were updated on the first pass; CI caught the fifth.
A_DISK=$(find agents/aios -name '*.md' ! -name '_index.md' ! -name 'README.md' | wc -l | tr -d ' ')
A_TOT=$(grep -oE 'Total bundled agents: [0-9]+' agents/_index.md | grep -oE '[0-9]+' | head -1)
A_SUM=$(grep -oE '\*\*`aios/[a-z-]+/`\*\* \| [^|]+ \| [0-9]+' agents/_index.md | grep -oE '[0-9]+$' | paste -sd+ - | bc 2>/dev/null)
[ "$A_TOT" = "$A_DISK" ] && ok "_index total matches disk ($A_DISK)" || no "_index says $A_TOT, disk has $A_DISK"
[ "$A_SUM" = "$A_DISK" ] && ok "_index bundle-table sums to disk ($A_DISK)" || no "table sums to $A_SUM, disk has $A_DISK"

# Extract the purity allowlist ONCE: the alternation line inside the agents/aios
# case block, e.g. "  sales|strategy|finance-legal|...|commerce) ;;"
PURITY_ALLOW=$(grep -oE '^ +sales\|[a-z|-]+\)' .github/workflows/validate.yml | head -1 | tr -d ' )')

echo "── every bundle on disk has a README and is in CI's list ──"
for d in agents/aios/*/; do
  b=$(basename "$d")
  test -f "$d/README.md" && ok "$b has a README" || no "$b has no README.md"
  # TWO independent hardcoded bundle lists live in validate.yml — the existence
  # loop AND the framework-purity allowlist. Adding commerce updated one and not
  # the other, and CI failed on the one that was missed. Checking a single list
  # would have passed this exact defect, so check BOTH.
  grep -q "for bundle in .*\b$b\b" .github/workflows/validate.yml \
    && ok "$b is in the CI existence loop" || no "$b missing from the CI existence loop" "a bundle CI does not know about can rot"
  # Membership test, not a positional regex. The first attempt required the name
  # to appear AFTER "sales|strategy|", so it could only ever pass for the last
  # alternative — the newest bundle passed by accident while five real ones
  # "failed". A check whose result depends on position in a list is not checking
  # membership.
  case "|$PURITY_ALLOW|" in
    *"|$b|"*) ok "$b is in the framework-purity allowlist" ;;
    *) no "$b missing from the purity allowlist" "purity reads it as a company namespace and fails the build" ;;
  esac
done

echo "── the commerce bundle ships ONE agent, on purpose ──"
n=$(find agents/aios/commerce -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')
[ "$n" = "1" ] && ok "exactly one agent in the bundle" \
  || no "$n agents in commerce/" "the source guidance rejects splitting the conversational path — adding sub-agents contradicts it"
grep -qiE 'one agent and not a catalog|modes of one architecture' agents/aios/commerce/README.md \
  && ok "the README states WHY it is one agent" \
  || no "the one-agent decision is undocumented" "an undocumented rule gets 'fixed' by the next contributor"

echo "── the harness boundary is present and unambiguous ──"
grep -qiE 'harness.*not.*prompt|prompt is a request.*guard is a guarantee' "$AG" \
  && ok "money/policy enforcement is placed in the harness" \
  || no "the harness boundary is missing" "without it this agent would sanction spending decided by a prompt"
for s in 'never fan out into sub-agents' 'data, never instructions' 'eval'; do
  grep -qi "$s" "$AG" && ok "constraint present: $s" || no "constraint missing: $s"
done

echo "── the commerce agent is a THIN entry point, not a copy ──"
grep -qF 'anthropics/commerce-agents' "$AG" && ok "points at the official reference implementation" \
  || no "the agent does not link the reference implementation" "it would be a paraphrase of six skills with no path to the real thing"
grep -qiE 'not vendored|generalist entry point' "$AG" && ok "states that it is an entry point, not a copy" \
  || no "the no-vendoring decision is undocumented"
[ -d skills/aios/commerce-architecture ] && no "an upstream commerce skill was vendored in" "6.7MB that drifts; one link reaches all of it" \
  || ok "no upstream commerce skills copied into the tree"

echo "── the skill defers to the operator's own declared stack ──"
grep -qF 'coding_style.md' "$SK" && ok "reads the operator declaration first" \
  || no "the skill never checks for a declared stack" "canonical would be imposing one operator's choices"
grep -qiE 'a deviation is a decision' "$SK" && ok "deviation-vs-drift rule present" || no "nothing distinguishes a deviation from drift"
grep -qiE 'Timebox the spike' "$SK" && ok "carries the honest learning-curve caveat" || no "the Nix caveat is missing"
for s2 in 'Elixir + Phoenix' 'React + TypeScript + Vite' 'PostgreSQL' 'Nix flakes'; do
  grep -qF "$s2" "$SK" && ok "recommended stack names: $s2" || no "recommended stack missing: $s2"
done

echo "── the skill carries the build ORDER, which is its whole point ──"
[ -f "$SK" ] && ok "skill exists" || no "$SK missing"
grep -qiE 'rung 2 is the one everyone gets wrong' "$SK" && ok "admin+seeds is called out as the missed rung" \
  || no "the build-order argument is gone" "without it this is a list of preferences"
grep -qiE 'auth is rung 3, not rung 1' "$SK" && ok "auth is explicitly not first" || no "auth ordering unstated"
for s in 'Deterministic seed data' 'Non-sequential ids' 'One command to a working environment' 'force-with-lease'; do
  grep -qF "$s" "$SK" && ok "default present: $s" || no "default missing: $s"
done
grep -qiE 'mutate the code so the defect is genuinely present' "$SK" \
  && ok "PR discipline requires a check that CAN fail" || no "the can-it-fail discipline is missing"
# The non-imposition guarantee moved from a weak word ("override") to a real
# resolution rule: the operator's own declaration WINS. Assert the rule, not the
# vocabulary — a check pinned to a phrase fails the moment the prose improves.
grep -qiE "it wins|recommendation for someone who has not decided" "$SK" \
  && ok "the operator's declared stack outranks the recommendation" \
  || no "nothing states that a declared stack wins" "canonical would be imposing one operator's choices"

echo "── it is registered where sessions will find it ──"
grep -qF 'shipping-a-saas' skills/_index.md && ok "in skills/_index.md" || no "not in the skills registry"
grep -qF 'commerce-agent-architect' agents/_index.md && ok "in agents/_index.md" || no "not in the agent registry"
for a in technical-cofounder code-reviewer security-engineer; do
  grep -qF 'shipping-a-saas' "agents/aios/engineering/$a.md" \
    && ok "$a references the skill" || no "$a does not reference shipping-a-saas"
done

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]

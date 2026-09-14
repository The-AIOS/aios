#!/usr/bin/env bash
# tests/toplevel-classification.test.sh
#
# Every top-level directory in canonical is either SHIPPED to operator vaults (Tier 1)
# or CANONICAL-ONLY (Tier 0). This suite fails the build when a new one is neither.
#
# WHY A GUARD AND NOT A PARAGRAPH. `/aios:update` DERIVES its layer list from the clone
# rather than hardcoding it, so a newly-added infra layer can never be silently MISSED.
# The mirror-image failure is that a new top-level folder is silently INCLUDED — the
# default is "ships to every vault", and nothing asks. update.md anticipates it in prose
# ("Adding a new canonical-only folder … name it here in the same PR"), and that is an
# instruction someone has to remember on the one PR that introduces the folder.
#
# Measured 2026-09-14: #133 added `scripts/autofix.sh` — repo maintenance invoked only by
# CI and CONTRIBUTING.md, named by no operator surface — and a root `scripts/` folder
# reached a live vault on the next sync. The same PR had already put its sibling
# (`explain-failure.sh`) under `.github/scripts/`, which is Tier 0 and structurally safe.
# One category, two homes, one of them protected. Nothing failed, which is the problem.
#
# The Tier-0 list is READ from update.md, never restated here — one bound, one home.
#
# Run:  bash tests/toplevel-classification.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$REPO/plugins/aios/commands/update.md"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# ── Tier 1: the top-level directories canonical INTENDS every vault to receive. ──────
# Adding a directory here is a deliberate statement that its contents are operator
# runtime — code an operator's own sessions and commands invoke. If it is contributor
# or CI tooling instead, it belongs under .github/ (already Tier 0), not here.
SHIPS=".claude-plugin agents hooks mcps plugins skills templates"

[ -f "$SPEC" ] || { printf '  FAIL  %s missing\n' "$SPEC"; exit 1; }

# ── Tier 0: parsed from the spec that actually enforces it at sync time. ─────────────
DENY="$(grep -m1 '^TIER0_DENY=' "$SPEC" | sed -E 's/^TIER0_DENY="([^"]*)".*/\1/')"

# A failed parse yields an empty DENY, under which `tests` and `.github` would read as
# unclassified and every run would fail for the wrong reason. Assert the premise first.
if [ -n "$DENY" ]; then ok "Tier-0 denylist parsed from update.md: $DENY"
else no "could not parse TIER0_DENY from update.md" "every verdict below would be meaningless"; fi

classify() { # $1 = a top-level name -> ships | canonical-only | UNCLASSIFIED
  case " $DENY " in *" $1 "*) echo canonical-only; return ;; esac
  case " $SHIPS " in *" $1 "*) echo ships;         return ;; esac
  echo UNCLASSIFIED
}

# ── The control, first: prove UNCLASSIFIED is reachable. ─────────────────────────────
# A classifier that answers "fine" to everything passes this suite forever while
# checking nothing. Same discipline the mcps-setup suite uses: prove by mutation.
[ "$(classify aios-benchmarks-fixture)" = "UNCLASSIFIED" ] \
  && ok "control: a folder in neither list is reported UNCLASSIFIED" \
  || no "the classifier cannot report UNCLASSIFIED" "this suite would pass against any tree"

[ "$(classify .github)" = "canonical-only" ] \
  && ok "control: .github classifies as canonical-only" \
  || no ".github did not classify as canonical-only" "the Tier-0 parse is wrong"

# ── The assertion: every TRACKED top-level directory is classified. ──────────────────
# Tracked, not on-disk: an untracked local folder (.claude, a scratch dir, a venv) is
# not part of canonical and can never reach a vault, so flagging it would be noise.
#
# Read the INDEX (`ls-files`), not `ls-tree HEAD`. The index is what the commit under
# review would contain, so a folder added or moved in the working tree is judged now
# rather than one commit later — which is the difference between a guard that blocks
# the PR that introduces the folder and one that reports it after it has landed.
UNCLASSIFIED=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ "$(classify "$d")" = "UNCLASSIFIED" ] && UNCLASSIFIED="$UNCLASSIFIED $d"
done <<EOF
$(git -C "$REPO" ls-files | awk -F/ 'NF>1 {print $1}' | sort -u)
EOF

if [ -z "$UNCLASSIFIED" ]; then
  ok "every tracked top-level directory is classified Tier-1 or Tier-0"
else
  no "unclassified top-level director(ies):$UNCLASSIFIED" \
     "each ships to EVERY operator vault on their next /aios:update. Decide: operator runtime -> add to SHIPS in this file; contributor/CI tooling -> move it under .github/ (already Tier 0)."
fi

# ── And the two Tier-0 entries that must never leave, asserted from the live spec. ───
for must in tests .github; do
  case " $DENY " in
    *" $must "*) ok "$must is still denylisted in update.md" ;;
    *) no "$must left TIER0_DENY" "it would sync into every operator vault" ;;
  esac
done

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

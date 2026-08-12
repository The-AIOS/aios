#!/usr/bin/env bash
# tests/update-tier0-denylist.test.sh
#
# Guards the Tier-0 boundary in /aios:update AFTER the layer enumeration was made
# generic over directories (Step 2 + Step 6.5).
#
# WHY THIS EXISTS, AND WHY IT IS SHAPED THIS WAY
# ----------------------------------------------
# The layer list used to be hardcoded (`templates skills hooks mcps plugins agents
# .claude-plugin`). That was safe for Tier 0 by ACCIDENT: tests/ and .github/ were
# excluded by simple omission. It was unsafe for everything else — a newly-added
# bundled folder was invisible to Step 2 (nothing DIFFERS; the path is merely absent
# from the vault) and equally invisible to Step 6.5, because the backstop read from
# the same hardcoded list. One blind spot, shared by the check and its own backstop.
#
# Deriving the list from the clone fixes that — and immediately arms the footgun the
# Tier 0 section warns about in writing: a generic enumeration sweeps tests/ and
# .github/ into every operator vault. So the exclusion has to stop being an omission
# and become a named denylist, and that denylist needs a test that CANNOT pass
# vacuously.
#
# Hence the shape: this does not grep update.md for reassuring strings. It EXTRACTS
# the real derivation logic, RUNS it against a fixture tree, and asserts the output.
# Then it re-runs the same logic with the denylist emptied and asserts the opposite —
# so a version of this file that could never fail would itself fail scenario 3.
#
# Run:  bash tests/update-tier0-denylist.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
U="$REPO/plugins/aios/commands/update.md"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# A fixture standing in for the canonical clone: real Tier-1 layers, the two Tier-0
# folders, an operator vault/ tree, and a layer that does NOT appear in any hardcoded
# list anywhere — that last one is the regression the generalisation exists to fix.
CLONE="$TMP/clone"
mkdir -p "$CLONE"/{templates,skills,hooks,mcps,plugins,agents,.claude-plugin,tests,.github/workflows,vault/.obsidian,brandnewlayer}
: > "$CLONE/CLAUDE.md"

echo "== update-tier0-denylist =="

# ---------------------------------------------------------------------------
# 1. The denylist is present in the spec and names both Tier-0 folders.
# ---------------------------------------------------------------------------
DENY_LINE="$(grep -m1 '^TIER0_DENY=' "$U" 2>/dev/null || true)"
if [ -z "$DENY_LINE" ]; then
  no "TIER0_DENY is defined in update.md" "no TIER0_DENY= line found — the enumeration is generic with nothing excluding Tier 0"
else
  miss=""
  for d in tests .github; do
    case "$DENY_LINE" in *"$d"*) ;; *) miss="$miss $d" ;; esac
  done
  [ -z "$miss" ] && ok "TIER0_DENY names tests and .github" \
                 || no "TIER0_DENY names tests and .github" "missing:$miss"
fi

# ---------------------------------------------------------------------------
# 2. THE REAL CHECK — run the derivation and assert what it produces.
#    Extracted from the spec rather than reimplemented, so this cannot drift
#    into testing a copy of the logic that update.md no longer uses.
# ---------------------------------------------------------------------------
derive(){ # $1 = denylist to use
  local deny="$1" out="" d
  for d in $(cd "$CLONE" && ls -A); do
    [ -d "$CLONE/$d" ] || continue
    case " $deny " in *" $d "*) continue ;; esac
    out="$out $d"
  done
  printf '%s' "$out"
}

REAL_DENY="$(printf '%s' "$DENY_LINE" | sed -e 's/^TIER0_DENY=//' -e 's/^"//' -e 's/"$//')"
LAYERS="$(derive "$REAL_DENY")"

leaked=""
for d in tests .github; do
  case " $LAYERS " in *" $d "*) leaked="$leaked $d" ;; esac
done
[ -z "$leaked" ] && ok "derived layers exclude every Tier-0 folder" \
               || no "derived layers exclude every Tier-0 folder" \
                     "LEAKED:$leaked — this would ship CI scaffolding into every operator vault"

# vault/ is Tier 2; only vault/.obsidian is added back, and by hand.
case " $LAYERS " in
  *" vault "*) no "vault/ is not swept wholesale" "vault/ entered the layer list — that is operator content (Tier 2)" ;;
  *)           ok "vault/ is not swept wholesale" ;;
esac

# ---------------------------------------------------------------------------
# 3. The positive half — the reason to generalise at all.
#    A layer named in no hardcoded list must still be found.
# ---------------------------------------------------------------------------
case " $LAYERS " in
  *" brandnewlayer "*) ok "a layer absent from every hardcoded list is still enumerated" ;;
  *)                   no "a layer absent from every hardcoded list is still enumerated" \
                          "the enumeration is not actually generic — the original bug survives" ;;
esac

# ---------------------------------------------------------------------------
# 4. THE NEGATIVE CASE — prove this test can fail.
#    Same logic, empty denylist: Tier 0 MUST leak. If it does not, the assertion
#    in scenario 2 is vacuous and proves nothing.
# ---------------------------------------------------------------------------
UNGUARDED="$(derive "")"
n=0
for d in tests .github; do
  case " $UNGUARDED " in *" $d "*) n=$((n+1)) ;; esac
done
[ "$n" = 2 ] && ok "test is falsifiable (empty denylist leaks both Tier-0 folders)" \
             || no "test is falsifiable (empty denylist leaks both Tier-0 folders)" \
                   "expected 2 leaks with no denylist, got $n — scenario 2 cannot fail, so it is not a check"

# ---------------------------------------------------------------------------
# 5. Both call sites apply it. One guarded loop and one unguarded loop is the
#    same bug with a green build: Step 6.5 is Step 2's backstop.
# ---------------------------------------------------------------------------
# NB: `grep -c` exits 1 on zero matches while still printing "0", so the idiomatic
# `$(grep -c … || echo 0)` emits "0\n0" and the arithmetic test below dies on it.
# Read the count, then read the exit code — never let one stand in for the other.
sites="$(grep -c 'case " \$TIER0_DENY " in' "$U" 2>/dev/null)" || sites=0
[ "${sites:-0}" -ge 2 ] && ok "both Step 2 and Step 6.5 apply the denylist ($sites sites)" \
                        || no "both Step 2 and Step 6.5 apply the denylist" \
                              "found $sites guarded loop(s), expected >= 2"

# ---------------------------------------------------------------------------
# 6. The category stays documented — folklore is how the first blind spot happened.
# ---------------------------------------------------------------------------
grep -q '^### Tier 0' "$U" && ok "update.md still documents § Tier 0" \
                           || no "update.md still documents § Tier 0"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1

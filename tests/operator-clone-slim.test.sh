#!/usr/bin/env bash
# tests/operator-clone-slim.test.sh
#
# SETUP step 2 leaves tests/ out of an operator's working tree with a non-cone sparse-checkout.
# Measured before building: nothing an operator runs reads tests/ (every reference outside it is
# prose or a comment naming a guard), /aios:update never syncs it (Tier 0), and the only CI jobs a
# forked vault runs (frontmatter, explain) do not use it. This proves the step on a real clone:
# tests/ gone, the framework present, the tree clean, commits unaffected, and fully reversible.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

CMD="$(grep -o "sparse-checkout set --no-cone '/\*' '!/tests/'" "$ROOT/SETUP.md" | head -1)"
[ -n "$CMD" ] && ok "SETUP prescribes the sparse-checkout" || no "SETUP no longer carries the step"

git clone -q "$ROOT" "$T/v" 2>/dev/null || { no "could not clone the repo under test"; echo "── RESULT: $PASS passed, $FAIL failed ──"; exit 1; }
git -C "$T/v" sparse-checkout set --no-cone '/*' '!/tests/' || no "sparse-checkout set failed (git too old?)"
[ ! -e "$T/v/tests" ] && ok "tests/ is not in the working tree" || no "tests/ still checked out"
[ -f "$T/v/CLAUDE.md" ] && [ -f "$T/v/hooks/vault/aios-commit" ] && [ -d "$T/v/plugins/aios" ] && ok "the framework is all there" || no "sparse-checkout dropped framework files"
[ -z "$(git -C "$T/v" status --porcelain)" ] && ok "the tree is clean (nothing reads as deleted)" || no "status is dirty" "$(git -C "$T/v" status --porcelain | head -3)"
echo x >> "$T/v/README.md"
git -C "$T/v" -c user.name=t -c user.email=t@t commit -qam t && [ "$(git -C "$T/v" show --stat --format= HEAD | grep -c tests/)" = 0 ] \
  && [ "$(git -C "$T/v" ls-files tests | wc -l | tr -d ' ')" -gt 0 ] && ok "a commit touches nothing in tests/, which stays tracked" || no "commit behaviour changed"
git -C "$T/v" sparse-checkout disable && [ -d "$T/v/tests" ] && ok "sparse-checkout disable brings tests/ back" || no "not reversible"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]

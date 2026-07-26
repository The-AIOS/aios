#!/usr/bin/env bash
# Regression test for install-wrappers.sh → detect_primary_session.
#
# This function writes a name into the operator's shell rc, so a wrong answer is not a crash —
# it silently redefines a function they type every day. Two real incidents shaped it:
#   1. It scraped USER.md's EXAMPLE row and wrote `*buddy*` into the rc; zsh globs it, so every
#      new terminal errored on startup, from an installer reporting success.
#   2. The validator added to fix (1) allowed lowercase only, so an operator whose session is
#      `ALI` had their months-old `ALI()` silently renamed to `aios()` on update. Same shape:
#      a check that substitutes a different answer and reports success.
# Both are "the check reads/permits the wrong thing" — see antifragile #88. Hence: every case
# below asserts BOTH that valid names survive AND that hostile ones are still rejected. A guard
# that only ever returns the fallback would pass a one-sided test while protecting nothing.
#
# Canonical-only (Tier 0 — never synced to operator vaults). Run:  bash tests/install-wrappers.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/hooks/claude-identity/install-wrappers.sh"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[ -f "$SRC" ] || { echo "::error::missing $SRC"; exit 1; }

# Extract ONLY the function under test — sourcing the whole installer would rewrite this
# machine's shell rc as a side effect of running the tests.
FN=$(awk '/^detect_primary_session\(\)/,/^}/' "$SRC")
[ -n "$FN" ] || { echo "::error::could not extract detect_primary_session from $SRC"; exit 1; }
eval "$FN"

# detect_primary_session reads $HOME/aios/USER.md — point HOME at a throwaway per case.
run_with_identity() { # $1 = the raw cell to put in the Identity table's Name column
  local tmp; tmp=$(mktemp -d); mkdir -p "$tmp/aios"
  printf '## Identity\n\n| Name | Role |\n|------|------|\n| %s | primary |\n\n## Settings\n' "$1" > "$tmp/aios/USER.md"
  ( HOME="$tmp" detect_primary_session ) 2>/dev/null
  rm -rf "$tmp"
}

echo "── accepted: valid session-name shapes survive ──"
for n in buddai sarah app-walker ALI Ali a1 x9-y; do
  got=$(run_with_identity "$n")
  [ "$got" = "$n" ] && ok "'$n' preserved" || no "'$n' → '$got' (should survive)"
done

echo "── rejected: anything that could reach a shell as syntax falls back to aios ──"
# NOTE the pairing: if these ever start passing through, the fix above went too wide.
# Deliberately NOT tested here: a backtick (the parser strips those — they're markdown code
# formatting, `| \`buddai\` |` is the vault's own table style) and a raw pipe (that IS the column
# separator, so it cannot occur inside a cell). Both are parser-layer, not validator-layer.
for n in '*buddy*' '_example_' 'my name' 'a;b' 'a$(id)' "a'b" '-lead' 'lead-' '$HOME'; do
  got=$(run_with_identity "$n")
  [ "$got" = "aios" ] && ok "'$n' rejected → aios" || no "'$n' → '$got' (should have fallen back)"
done

echo "── the fallback announces itself (silent substitution is the bug, not the fallback) ──"
# Use a name that SURVIVES the parser but FAILS the validator. An emphasis row is skipped upstream
# as an example, so nothing is ever rejected there — and silence is correct in that case.
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| my name | primary |\n' > "$tmp/aios/USER.md"
msg=$( { HOME="$tmp" detect_primary_session >/dev/null; } 2>&1 )
rm -rf "$tmp"
echo "$msg" | grep -q 'using "aios"' && ok "rejection is reported on stderr" || no "fell back SILENTLY — the operator can only notice by missing their function"

echo "── but an EXAMPLE row is skipped upstream, so it must NOT announce a rejection ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | EXAMPLE |\n' > "$tmp/aios/USER.md"
msg=$( { HOME="$tmp" detect_primary_session >/dev/null; } 2>&1 )
rm -rf "$tmp"
[ -z "$msg" ] && ok "example row → silent fallback (nothing was rejected)" || no "announced a rejection that never happened: $msg"

echo "── the announcement must not corrupt the return value (stdout is the name) ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | primary |\n' > "$tmp/aios/USER.md"
out=$( HOME="$tmp" detect_primary_session 2>/dev/null )
rm -rf "$tmp"
[ "$out" = "aios" ] && ok "stdout is exactly 'aios', message went to stderr" || no "stdout polluted: '$out'"

echo "── example rows are skipped, real rows below them win ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | EXAMPLE |\n| `ALI` | primary |\n' > "$tmp/aios/USER.md"
out=$( HOME="$tmp" detect_primary_session 2>/dev/null )
rm -rf "$tmp"
[ "$out" = "ALI" ] && ok "emphasis row skipped, backticked uppercase row used" || no "got '$out', expected ALI"

echo ""
echo "── RESULT: $PASS passed, $FAIL failed  (bash $BASH_VERSION) ──"
[ "$FAIL" = "0" ] || exit 1

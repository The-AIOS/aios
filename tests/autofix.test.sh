#!/usr/bin/env bash
# tests/autofix.test.sh
#
# Asserts the count fixer repairs exactly what it claims and nothing else.
#
# WHY THE "NOTHING ELSE" HALF MATTERS MORE. A fixer that runs in CI and commits its own output
# is trusted by definition — nobody reviews a bot commit line by line. So the risk is not that it
# fails to fix; it is that it quietly rewrites something it was never asked to touch. Every case
# below therefore ends by comparing the repaired file against the original byte for byte.
#
# The fixture is a COPY of the real tree (docs + the folders the counts are derived from), broken
# on purpose. Testing against the live repo would only ever exercise the already-correct path.
#
# Run:  bash tests/autofix.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$REPO/scripts/autofix.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

[ -f "$FIX" ] || { printf '  FAIL  %s missing\n' "$FIX"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aios-autofix.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$REPO/TOOLS.md" "$REPO/README.md" "$WORK/" 2>/dev/null
cp -r "$REPO/agents" "$REPO/plugins" "$REPO/skills" "$WORK/" 2>/dev/null
run() { AIOS_REPO_ROOT="$WORK" bash "$FIX" ${1:-}; }

echo "-- 1. a tree that is already right is left ALONE --"
if run --check >/dev/null 2>&1; then ok "--check on an unmodified copy exits 0"
else no "--check reports work to do on a tree that matches the repo" "$(run --check 2>&1 | head -3)"; fi
run >/dev/null 2>&1
for f in TOOLS.md README.md agents/_index.md; do
  cmp -s "$WORK/$f" "$REPO/$f" && ok "$f untouched by a no-op run" || no "$f was rewritten on a no-op run"
done

echo
echo "-- 2. a stale number is repaired, and only the number --"
# Break one claim per file, including a table row (the case a naive sed rewrites wrongly).
sed -E 's#(AIOS-built[^0-9]*)[0-9]+#\17#' "$WORK/TOOLS.md" > "$WORK/t" && mv "$WORK/t" "$WORK/TOOLS.md"
sed -E 's#(\*\*)[0-9]+( commands)#\13\2#' "$WORK/README.md" > "$WORK/t" && mv "$WORK/t" "$WORK/README.md"
sed -E 's#(Total bundled agents: )[0-9]+#\12#' "$WORK/agents/_index.md" > "$WORK/t" && mv "$WORK/t" "$WORK/agents/_index.md"
sed -E 's#(\*\*`aios/sales/`\*\*.*\| )[0-9]+( \|)#\177\2#' "$WORK/agents/_index.md" > "$WORK/t" && mv "$WORK/t" "$WORK/agents/_index.md"

if run --check >/dev/null 2>&1; then no "--check passed a tree with four stale counts" "it cannot see what it is meant to fix"
else ok "--check fails on stale counts (exit 1)"; fi
cmp -s "$WORK/TOOLS.md" "$REPO/TOOLS.md" && no "--check MODIFIED a file — it must only report" \
  || ok "--check changed nothing (the file is still broken after it ran)"

run >/dev/null 2>&1
for f in TOOLS.md README.md agents/_index.md; do
  cmp -s "$WORK/$f" "$REPO/$f" && ok "$f repaired back to the original, byte for byte" \
    || no "$f differs from the original after repair" "$(diff "$REPO/$f" "$WORK/$f" | head -4)"
done

echo
echo "-- 3. running it twice is a no-op --"
run --check >/dev/null 2>&1 && ok "the repaired tree passes --check" || no "the fixer does not converge"
run >/dev/null 2>&1
cmp -s "$WORK/agents/_index.md" "$REPO/agents/_index.md" && ok "a second apply changes nothing" \
  || no "the fixer is not idempotent — a bot commit would loop"

echo
echo "-- 4. it declares what it covers, and the name is a real CI step --"
COVERS="$(bash "$FIX" --covers)"
[ -n "$COVERS" ] && ok "--covers names at least one step" || no "--covers prints nothing"
MISS=""
printf '%s\n' "$COVERS" | while IFS= read -r step; do
  [ -n "$step" ] || continue
  grep -qF "name: $step" "$REPO/.github/workflows/validate.yml" || printf '%s\n' "$step" >> "$WORK/miss"
done
[ -s "$WORK/miss" ] && no "--covers names a step that does not exist in the workflow: $(tr '\n' ' ' < "$WORK/miss")" \
  || ok "every covered name matches a step in validate.yml"
# CONTROL: the comparison must be capable of failing.
grep -qF "name: a step that does not exist" "$REPO/.github/workflows/validate.yml" \
  && no "the control found a step that cannot be there — the grep is not reading the workflow" \
  || ok "control: the step lookup answers no for an invented name"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

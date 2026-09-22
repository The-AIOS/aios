#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# README's Repository Architecture tree names every root doc, and only real ones
#
# WHY
# The tree is the first map a newcomer reads, and it is maintained by hand. It
# silently fell behind three root docs (CONTRIBUTING, GLOSSARY, SECURITY) while
# every other surface — CLAUDE.md's documentation map, /aios:update's Tier-1
# list — had them. It also restated a count ("10 bundled" MCPs) that a later
# server made false; a count in a tree is a second implementation of a fact
# mcps/_index.md already owns, so this suite forbids one rather than pinning it.
#
# Both directions: a root doc missing from the tree, and a tree entry naming a
# root doc that does not exist. A control proves the extractor finds entries at
# all — an empty extraction would otherwise pass "nothing is listed but absent".
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }

# The tree = the first fenced block after the "Repository Architecture" heading.
TREE="$(awk '/^#+ .*Repository Architecture/{f=1;next} f&&/^```/{n++; if(n==2) exit; next} f&&n==1' README.md)"
# Root-level entries only: exactly one tree glyph, no │ indentation before it.
LISTED="$(printf '%s\n' "$TREE" | sed -nE 's/^[├└]── ([A-Za-z0-9._-]+\.md) .*/\1/p' | sort -u)"

N=$(printf '%s\n' "$LISTED" | grep -c . || true)
if [ "$N" -ge 5 ] && printf '%s\n' "$LISTED" | grep -qx 'CLAUDE.md'; then
  ok "control: extractor finds the tree's root docs ($N, CLAUDE.md among them)"
else
  no "control: extractor finds the tree's root docs" "found $N — the heading or tree format moved; fix the extractor before trusting the checks below"
fi

for f in *.md; do
  if printf '%s\n' "$LISTED" | grep -qxF "$f"; then ok "tree lists $f"
  else no "tree lists $f" "root doc exists but README's architecture tree omits it"; fi
done

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || no "tree entry $f exists at root" "README names a root doc that is not there"
done <<< "$LISTED"

if printf '%s\n' "$TREE" | grep -qE '[0-9]+ bundled'; then
  no "tree restates no bundled-server count" "$(printf '%s\n' "$TREE" | grep -E '[0-9]+ bundled' | head -1 | sed 's/^ *//')"
else ok "tree restates no bundled-server count (mcps/_index.md owns it)"; fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

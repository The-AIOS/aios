#!/usr/bin/env bash
# route-insight.test.sh — entry excision across BOTH supported styles.
#
# Regression origin: `hooks/route-insight.py` matched only `### ` headings, but a
# session-insights buffer that follows the documented lifecycle naturally becomes
# top-level `- **…**` bullets with indented facets. The tool therefore matched
# nothing and exited 2 — which reads as "nothing to do", not "I cannot see your
# data" — so BOTH of /close-day's compounding steps silently did nothing.
# Reported by Luigi Matrone / ALI, 2026-08-08. Invisible from the author's vault,
# whose buffer uses headings.
#
# Scenarios 1 and 2 MUST fail (exit 2) against the pre-fix implementation.

set -uo pipefail
TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/route-insight.py"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

tmp(){ mktemp "${TMPDIR:-/tmp}/ri-XXXXXX"; }

fixture_bullets(){ cat > "$1" <<'EOF'
## Reinforced

- **Alpha entry — the one to keep** (reinforced — 2026-07-01)
  - first facet of alpha
  - second facet of alpha

<!-- ROUTED 2026-07-02: something → [[patterns]] -->

- **Bravo entry — the excision target** (new — 2026-08-01)
  - bravo facet one
  - bravo facet two

- **Charlie entry — also kept** (new — 2026-08-02)
  - charlie facet

## Emerging
EOF
}

# ── 1. bullet excision carries its indented facets, leaves neighbours intact ──
f=$(tmp); fixture_bullets "$f"
out=$(python3 "$TOOL" "$f" --match "Bravo entry" --marker "<!-- ROUTED: bravo -->" 2>&1); rc=$?
if [ $rc -ne 0 ]; then no "1 bullet excision" "exit $rc — $out"
elif grep -q "bravo facet" "$f"; then no "1 bullet excision" "orphaned facet left behind"
elif ! grep -q "Alpha entry" "$f" || ! grep -q "Charlie entry" "$f"; then no "1 bullet excision" "collateral loss"
elif ! grep -q "ROUTED: bravo" "$f"; then no "1 bullet excision" "marker did not land"
else ok "1 bullet excision carries facets, neighbours intact"; fi

# ── 2. the file-level comment between entries must survive ──
f=$(tmp); fixture_bullets "$f"
before=$(grep -c '<!--' "$f")
python3 "$TOOL" "$f" --match "Bravo entry" --marker "<!-- ROUTED: bravo -->" >/dev/null 2>&1
after=$(grep -c '<!--' "$f")
[ "$after" -eq $((before+1)) ] \
  && ok "2 file-level <!-- --> trail line preserved (marker adds exactly 1)" \
  || no "2 comment preservation" "was $before, now $after (expected $((before+1)))"

# ── 3. last bullet before a section heading stops at the heading ──
f=$(tmp); fixture_bullets "$f"
out=$(python3 "$TOOL" "$f" --match "Charlie entry" --marker "<!-- ROUTED: charlie -->" 2>&1); rc=$?
if [ $rc -ne 0 ]; then no "3 last-bullet-before-heading" "exit $rc — $out"
elif ! grep -q "^## Emerging" "$f"; then no "3 last-bullet-before-heading" "ate the section heading"
elif grep -q "charlie facet" "$f"; then no "3 last-bullet-before-heading" "orphaned facet"
else ok "3 last bullet stops at the section heading"; fi

# ── 4. BACK-COMPAT: a ### entry whose body contains bullets is not truncated ──
f=$(tmp); cat > "$f" <<'EOF'
## Emerging

### Delta heading entry — the target (new — 2026-08-03)
Prose line under the heading.
- a bullet that is BODY, not a boundary
- another body bullet
Closing prose of delta.

### Echo heading entry — kept (new — 2026-08-04)
Echo body.
EOF
out=$(python3 "$TOOL" "$f" --match "Delta heading" --marker "<!-- ROUTED: delta -->" 2>&1); rc=$?
if [ $rc -ne 0 ]; then no "4 ### back-compat" "exit $rc — $out"
elif grep -q "body bullet" "$f" || grep -q "Closing prose of delta" "$f"; then
  no "4 ### back-compat" "a body bullet truncated the entry — back half orphaned"
elif ! grep -q "Echo heading entry" "$f"; then no "4 ### back-compat" "ate the next entry"
else ok "4 ### entry keeps bullet-containing body (no orphan)"; fi

# ── 5. refusal paths still refuse ──
f=$(tmp); fixture_bullets "$f"; cp "$f" "$f.orig"
python3 "$TOOL" "$f" --match "nonexistent zzz" >/dev/null 2>&1; rc_none=$?
python3 "$TOOL" "$f" --match "entry" >/dev/null 2>&1; rc_many=$?
if [ $rc_none -eq 2 ] && [ $rc_many -eq 2 ] && cmp -s "$f" "$f.orig"; then
  ok "5 refuses on 0 and on >1 match, file untouched"
else no "5 refusal paths" "no-match rc=$rc_none ambiguous rc=$rc_many (both must be 2), file changed=$(cmp -s "$f" "$f.orig" && echo no || echo YES)"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

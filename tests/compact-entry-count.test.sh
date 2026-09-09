#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:compact Step 3.5's entry probe must measure STRUCTURE, not just count.
#
# WHY. The retired quick-read (`grep -c '^### [0-9]'`) failed two ways in one
# incident: it counted a numbered meta-pattern index as entries (~2x on vaults
# whose index uses `### 1.` headings), and on a file carrying a complete stale
# copy of itself it reported "207 entries" instead of "damaged" -- the inflated
# count CONCEALED the duplication a measurement exists to expose. The doubled
# file had survived 11 days and 8 commits because every consumer read a number
# that looked plausible. The fix is an invariant (entries == highest AND zero
# duplicate numbers) computed OUTSIDE the `## Meta-patterns` section.
#
# These checks run THE DOCUMENT'S OWN probe (extract-never-restate -- a guard
# that restates the command it checks goes green when the doc drifts) against
# fixtures shaped like the real incident, so a future edit to the prose cannot
# silently revert the fix.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
C=plugins/aios/commands/compact.md
[ -f "$C" ] || { echo "::error::$C missing"; exit 1; }

echo "-- 1. the prose carries the invariant, not a bare count --"
grep -qF 'entries == highest' "$C" && ok "states the count==highest invariant" \
  || no "invariant 'entries == highest' missing" "a count alone cannot see a doubled file"
grep -qF 'duplicated == 0' "$C" && ok "states the zero-duplicates invariant" \
  || no "invariant 'duplicated == 0' missing" "duplicate entry numbers are the silent-duplication tell"
grep -qF 'MUST stop and diff' "$C" && ok "mismatch stops the pass before compaction" \
  || no "no stop-and-diff instruction on mismatch" "tombstoning against a doubled file destroys the newest copy"

echo "-- 2. the probe exists and is extractable --"
probe=$(sed -n '/# entry probe/,/^      ```$/p' "$C" | sed '$d')
if [ -n "$probe" ]; then ok "probe block found via its '# entry probe' marker"; else
  no "probe block not extractable" "marker '# entry probe' + closing fence expected in Step 3.5a"; fi
printf '%s\n' "$probe" | grep -q 'Meta-patterns' \
  && ok "probe scopes entries OUTSIDE the meta-pattern index" \
  || no "probe does not exclude the index section" "a numbered index re-creates the ~2x over-count"
printf '%s\n' "$probe" | grep -q '\${A:-' \
  && ok "probe target is overridable (testable against fixtures)" \
  || no "probe hardcodes its target path" "fixtures cannot exercise it"

echo "-- 3. run the document's probe against incident-shaped fixtures --"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# clean fixture: NUMBERED index (the legacy shape that broke the bare count) + 5 entries
cat > "$TMP/clean.md" <<'EOF'
# Antifragile

## Meta-patterns (read these first)

### 1. The rush-to-commit pattern
- Entries: #1, #2

### 2. The works-on-my-machine pattern
- Entries: #3

## Patterns of fragility

### 1. First lesson (Mar 30)
body

### 2. Second lesson (Apr 2)
body

### 3. Third lesson (Apr 9)
body

### 4. Fourth lesson (May 1)
body

### 5. Fifth lesson (May 8)
body
EOF

# damaged fixture: the real incident's shape -- a stale copy of the document
# (its own H1 + index + entries 1-3) glued onto the end by a bad edit
cat "$TMP/clean.md" > "$TMP/damaged.md"
cat >> "$TMP/damaged.md" <<'EOF'

# Antifragile

## Meta-patterns (read these first)

### 1. The rush-to-commit pattern
- Entries: #1, #2

## Patterns of fragility

### 1. First lesson (Mar 30)
stale body

### 2. Second lesson (Apr 2)
stale body

### 3. Third lesson (Apr 9)
stale body
EOF

run_probe(){ A="$1" bash -c "$probe" 2>/dev/null; }

out=$(run_probe "$TMP/clean.md")
if [ "$out" = "entries=5 highest=5 duplicated=0" ]; then
  ok "clean file with a NUMBERED index reads 5/5/0 (index not counted)"
else
  no "clean fixture misread" "got: $out — expected entries=5 highest=5 duplicated=0"
fi

out=$(run_probe "$TMP/damaged.md")
n=$(printf '%s' "$out" | sed -n 's/.*entries=\([0-9]*\).*/\1/p')
hi=$(printf '%s' "$out" | sed -n 's/.*highest=\([0-9]*\).*/\1/p')
dup=$(printf '%s' "$out" | sed -n 's/.*duplicated=\([0-9]*\).*/\1/p')
if [ -n "$n" ] && [ -n "$hi" ] && [ -n "$dup" ] && { [ "$n" != "$hi" ] || [ "$dup" -gt 0 ]; }; then
  ok "doubled file VIOLATES the invariant loudly ($out)"
else
  no "doubled file passed as healthy" "got: $out — the exact concealment the incident produced"
fi

# control: the control must fail if the fixture stops being incident-shaped
bare=$(grep -c '^### [0-9]' "$TMP/damaged.md")
if [ "$bare" -gt 8 ]; then
  ok "control holds: the retired bare count reads $bare on the damaged file (plausible-looking, wrong)"
else
  no "control broke" "bare count read $bare — fixture no longer reproduces the concealment"
fi

echo
echo "compact-entry-count: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]

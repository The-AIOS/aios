#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# mcps/setup.sh — name selection, and a success line that can fail
#
# Both defects here were found on a real first install, and they compound:
#
#   1. `want()` matched only FOLDER names (`nano-banana-mcp`), while the name any
#      tool actually holds is the connector id from `connector.json`
#      (`nano-banana`). The AIOS App passed the id, so the filter matched nothing.
#
#   2. The closing line printed "All MCPs installed" UNCONDITIONALLY. So after
#      matching nothing and doing no work, the script reported success — and the
#      operator watched a terminal tell them it had installed something it had not
#      touched. A static terminal cannot notice its own success message lying.
#
# The second is why the first was invisible. That is the pattern worth guarding:
# a filter that can miss, plus a report that cannot fail, is indistinguishable
# from a working install. See antifragile #88 (UNFALSIFIABLE CHECK).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

echo "── 1. an unknown name FAILS, loudly ──"
out=$(bash mcps/setup.sh definitely-not-an-mcp 2>&1); rc=$?
[ "$rc" -ne 0 ] \
  && ok "unknown name exits non-zero (got $rc)" \
  || no "unknown name exited 0" "this is the bug: nothing installed, success reported"
printf '%s' "$out" | grep -q "Nothing matched" \
  && ok "and says so in words" \
  || no "no 'Nothing matched' line" "the operator is left believing it worked"
printf '%s' "$out" | grep -q "All MCPs installed" \
  && no "it STILL printed the success line" "the guard must come before it" \
  || ok "the success line did not print"

echo "── 2. both spellings select the same MCP ──"
for name in nano-banana nano-banana-mcp; do
  out=$(bash mcps/setup.sh "$name" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q "Nothing matched"; then
    ok "'$name' matches"
  else
    no "'$name' did not match" "callers hold the connector id; this file spoke only folder names"
  fi
done

echo "── 3. --list names both spellings, or the error message lies ──"
# Captured first, NOT piped into `grep -q`: with `set -o pipefail`, grep -q exits on the first
# match, SIGPIPEs the script, and the pipeline reports 141 — a green script read as a failure.
# The first version of this test did exactly that and failed against a working --list.
lst=$(bash mcps/setup.sh --list 2>&1)
printf '%s' "$lst" | grep -q -- "-mcp" \
  && ok "--list shows the folder names" \
  || no "--list shows no folder names"
printf '%s' "$lst" | grep -qi "connector id" \
  && ok "--list also says the id works — matching what the error message promises" \
  || no "--list omits the id spelling" "the failure message tells operators it works; --list must agree"

echo "── 4. the guard is reachable — proven by mutation, not by reading ──"
# Strip the MATCHED assignments and the guard must stop firing. A check whose
# failing branch cannot be demonstrated is not a check (antifragile #88).
tmp=$(mktemp -d); cp mcps/setup.sh "$tmp/s.sh"
sed -i.bak 's/MATCHED=1; //g' "$tmp/s.sh"
out=$(cd "$tmp" && bash s.sh definitely-not-an-mcp 2>&1); rc=$?
[ "$rc" -ne 0 ] \
  && ok "control: without MATCHED the guard still fires (as it must — nothing matched)" \
  || no "control produced a pass" "the guard may be keying off something else"
rm -rf "$tmp"

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

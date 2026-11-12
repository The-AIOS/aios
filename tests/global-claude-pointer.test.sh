#!/usr/bin/env bash
# The global CLAUDE.md pointer (#302): one shared block, offered by setup and by /aios:update,
# carrying nothing personal. Usage: bash tests/global-claude-pointer.test.sh [repo-root]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T="$ROOT/templates/aios/global-claude-pointer.md"
CS="$ROOT/plugins/aios/commands/cold-start-interview.md"
CL="$ROOT/CHANGELOG.md"
MARK='<!-- aios:operating-system -->'
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

echo "global-claude-pointer"
check "template exists" '[ -f "$T" ]'
check "marker stands on its own line exactly once in the template" '[ "$(grep -cxF "$MARK" "$T" 2>/dev/null)" = 1 ]'

# The block: from the marker to the end of the file.
BLOCK=$( [ -f "$T" ] && awk -v m="$MARK" 'f{print} $0==m{f=1}' "$T" )
check "block has the Operating system heading" 'printf "%s\n" "$BLOCK" | grep -qx "## Operating system"'
check "block has exactly three bullets" '[ "$(printf "%s\n" "$BLOCK" | grep -c "^- ")" = 3 ]'
check "block says the vault contract wins inside the vault" 'printf "%s\n" "$BLOCK" | grep -qF "wins on any conflict"'
check "block names INTENT.md as the trust contract" 'printf "%s\n" "$BLOCK" | grep -qF "INTENT.md"'
check "block is a pointer, not an import" '! printf "%s\n" "$BLOCK" | grep -q "^@"'
# Nothing personal: no names, handles, addresses, or one operator's language/tone rules.
check "block carries no personal rules" '! printf "%s\n" "$BLOCK" | grep -qiE "spanish|english|portugu|latam|mexic|slack|gmail|@[a-z0-9]|reply in|sign |chuy|buddai"'

check "template says to write with Edit or Write, not Bash" 'grep -qF "Edit or Write tool" "$T"'
check "template says change nothing else" 'grep -qiF "change nothing else" "$T"'
check "template asks before writing" 'grep -qiF "never written without a yes" "$T"'

check "setup offers it (Step 3.5 names the template)" 'grep -qF "### Step 3.5" "$CS" && grep -qF "templates/aios/global-claude-pointer.md" "$CS"'
check "setup's Core tier includes Step 3.5" 'grep -qF "**3.5 (one question)**" "$CS"'
check "the CHANGELOG offers it to existing operators by the marker" 'grep -qF "templates/aios/global-claude-pointer.md" "$CL" && grep -qF "$MARK" "$CL"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

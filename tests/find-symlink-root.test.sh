#!/usr/bin/env bash
# `find ~/aios` lists only the link when ~/aios is a symlink (setup makes one for a vault cloned
# elsewhere), so a search rooted there finds nothing, exits 0 and says nothing (#319). Lint: every
# find rooted at the vault uses -H/-L or a trailing slash. Live: /aios:update's Step 3.9 sweep,
# run through a symlinked vault, still removes a planted leftover directory.
# Usage: bash tests/find-symlink-root.test.sh [repo-root] [update.md]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
U="${2:-$ROOT/plugins/aios/commands/update.md}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "find-symlink-root"
cd "$ROOT" || exit 1
bad=$( { git grep -nE 'find +("?(\$HOME|~|\$\{HOME\})/aios"?)( |$)' -- ':!CHANGELOG.md' ':!tests/find-symlink-root.test.sh' ':!plugins/aios/commands/update.md'; \
         grep -nE 'find +("?(\$HOME|~|\$\{HOME\})/aios"?)( |$)' "$U" | sed 's|^|update.md:|'; } 2>/dev/null)
[ -z "$bad" ] && ok "no find is rooted at a bare ~/aios (each uses -H, -L or ~/aios/)" || no "find rooted at a bare ~/aios: $bad"

T=$(mktemp -d "${TMPDIR:-/tmp}/fsr.XXXXXX")
mkdir -p "$T/real" "$T/home"; ln -s "$T/real" "$T/home/aios"
NL=$(printf '\nx'); NL=${NL%x}
mkdir -p "$T/real/CHANGELOG.md${NL}CLAUDE.md${NL}hooks"
awk '/^### 3\.9/{f=1} f&&/^```bash$/{g=1;next} g&&/^```$/{exit} g' "$U" > "$T/sweep.sh"
HOME="$T/home" sh "$T/sweep.sh" >/dev/null 2>&1
n=$(find "$T/real" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[ "$n" = 0 ] && ok "Step 3.9's sweep works through a symlinked ~/aios" || no "Step 3.9's sweep left the leftover directory behind a symlinked ~/aios"
rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# /aios:update never writes into /tmp or the temporary clone after Step 1 (#316). A sandboxed Bash
# tool may write the vault and $TMPDIR only; Step 1's clone runs outside it (it needs the network),
# but every later write into /tmp stopped the run on a sandbox denial. Scratch lives in the vault's
# gitignored .aios-run/. Static: no write redirection into $CLONE, $T=/tmp or /tmp/ outside Step 1.
# Live: Step 2's block runs against a READ-ONLY clone and still saves its list.
# Usage: bash tests/update-sandbox-writes.test.sh [repo-root] [update.md]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
U="${2:-$ROOT/plugins/aios/commands/update.md}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "update-sandbox-writes"

# Every bash block after Step 1's, as text.
after1=$(awk '/^### 1\.5/{f=1} f' "$U")
bad=$(printf '%s\n' "$after1" | grep -v '^[[:space:]]*#' | grep -nE '(>|>>|tee)[[:space:]]*"?(\$CLONE/|/tmp/)|T="/tmp"')
[ -z "$bad" ] && ok "no step after Step 1 writes into the clone or /tmp" || no "writes into the clone or /tmp remain: $bad"
grep -q 'tee "$HOME/aios/.aios-run/update-files"' "$U" && ok "Step 2 saves its list in .aios-run/" || no "Step 2's list is not in .aios-run/"
grep -q 'rm -f "$HOME/aios/.aios-run/update-files"' "$U" && ok "a list from an earlier run is removed before this run's Step 2" || no "a stale list could stand in for this run's"

# Live: Step 2 against a read-only clone.
T=$(mktemp -d "${TMPDIR:-/tmp}/usw.XXXXXX")
mkdir -p "$T/clone" "$T/home/aios"
( cd "$T/clone" && git init -q && mkdir -p hooks agents plugins tests .github vault && echo a > hooks/a.sh && echo x > agents/x.md && echo p > plugins/p.md \
  && echo t > tests/t.sh && echo g > .github/g.yml && echo v > vault/v.md && echo r > README.md \
  && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -qm A \
  && echo b > hooks/a.sh && git -c user.email=t@t -c user.name=t commit -qam B ) >/dev/null
BASE=$(git -C "$T/clone" rev-parse HEAD~1)
awk '/^### 2\. Find what changed/{f=1} f&&/^```bash$/{g=1;next} g&&/^```$/{exit} g' "$U" \
  | sed -e "s|^CLONE=\"/tmp/aios-update-check\"|CLONE=\"$T/clone\"|" -e "s|{stored_hash}|$BASE|g" > "$T/step2.sh"
chmod -R a-w "$T/clone"
out=$(HOME="$T/home" bash "$T/step2.sh" 2>&1); rc=$?
chmod -R u+w "$T/clone"
{ [ "$rc" = 0 ] && grep -qx 'hooks/a.sh' "$T/home/aios/.aios-run/update-files" 2>/dev/null; } \
  && ok "Step 2 runs against a read-only clone and saves its list" || no "Step 2 failed against a read-only clone (rc=$rc): $out"
rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

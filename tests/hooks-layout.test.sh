#!/usr/bin/env bash
# hooks/ is grouped by domain (#309). The top level holds only folders, _index.md, requirements.txt,
# .gitattributes and the one-release forwarding stubs; every stub runs its file's new home; and no
# file outside the stubs, CHANGELOG history and the installer's migration map names an old
# top-level path, so references cannot drift back.
# Usage: bash tests/hooks-layout.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "hooks-layout"

stubs=$(git ls-files hooks | awk -F/ 'NF==2' | grep -vE '^hooks/(_index\.md|requirements\.txt|\.gitattributes)$')
bad=""
for s in $stubs; do
  grep -qE 'Moved to hooks/[a-z]+/' "$s" || bad="$bad $s"
done
[ -z "$bad" ] && ok "the top level holds only folders, the index, requirements and forwarding stubs" || no "files at hooks/ top level that are not stubs:$bad"

missing=""
for s in $stubs; do
  tgt=$(grep -oE 'Moved to hooks/[a-z]+/[^ ]+ ' "$s" | head -1 | sed -E 's/^Moved to //; s/ $//')
  [ -f "$tgt" ] || missing="$missing $s->$tgt"
done
[ -z "$missing" ] && ok "every stub points at a file that exists" || no "stubs pointing nowhere:$missing"

out=$(bash hooks/whoami 2>&1; echo "rc=$?")
case "$out" in *rc=0*) ok "a bash stub forwards (hooks/whoami runs)" ;; *) no "hooks/whoami stub failed: $out" ;; esac
out=$(printf '' | python3 hooks/list-agents.py --unclear >/dev/null 2>&1; echo "rc=$?")
case "$out" in rc=0|rc=1) ok "a python stub forwards (hooks/list-agents.py runs)" ;; *) no "python stub failed: $out" ;; esac

names=$(for s in $stubs; do basename "$s"; done | grep . | sed 's/[.]/\\./g' | paste -sd'|' -)
[ -n "$names" ] || { no "harness: no stub names found"; echo "$pass passed, $fail failed"; exit 1; }
hits=$(git grep -nE "(^|[^a-zA-Z0-9_./-])hooks/($names)([^a-zA-Z0-9_-]|$)" -- . \
        ':!CHANGELOG.md' ':!tests/hooks-layout.test.sh' ':!hooks/install/install-settings.py' ':!tests/install-settings.test.sh' \
        $(for s in $stubs; do printf ":!%s " "$s"; done) | grep -vE 'Moved to hooks/' | head -10)
[ -z "$hits" ] && ok "nothing outside the stubs names an old top-level hook path" || no "old paths still referenced:
$hits"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

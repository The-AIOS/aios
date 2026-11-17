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

# A bash stub ignores an exported CDPATH (another tree's hooks/ must never win), follows symlinks,
# and stops on a symlink loop instead of spinning.
X=$(mktemp -d "${TMPDIR:-/tmp}/hl.XXXXXX"); mkdir -p "$X/other/hooks/context" "$X/bin"
printf '#!/usr/bin/env bash\necho WRONG-TREE\n' > "$X/other/hooks/context/whoami"; chmod +x "$X/other/hooks/context/whoami"
out=$( cd "$ROOT" && CDPATH="$X/other" bash hooks/whoami 2>/dev/null )
case "$out" in *WRONG-TREE*) no "a CDPATH sent the stub into another tree" ;; *) ok "a bash stub ignores CDPATH" ;; esac
ln -s "$ROOT/hooks/whoami" "$X/bin/whoami"; "$X/bin/whoami" >/dev/null 2>&1 && ok "a bash stub runs through a symlink" || no "the stub failed through a symlink"
ln -s "$X/bin/loop2" "$X/bin/loop1"; ln -s "$X/bin/loop1" "$X/bin/loop2"; cp "$ROOT/hooks/whoami" "$X/bin/stub"
( cd "$X/bin" && sed 's|^s="\$0"|s="$X/bin/loop1"|' stub > stub2 && chmod +x stub2 && X="$X" perl -e 'alarm 5; exec @ARGV' bash ./stub2 >/dev/null 2>&1 ); rc=$?
[ "$rc" != 142 ] && ok "a symlink loop ends instead of spinning" || no "the stub spun on a symlink loop"
rm -rf "$X"

# `uv run <old path>` builds its environment from the file it is given, so a stub of a script with a
# `# /// script` block must carry the same block, or the forwarded script runs without its dependencies.
meta_bad=""
for s in $stubs; do
  tgt=$(grep -oE 'Moved to hooks/[a-z]+/[^ ]+ ' "$s" | head -1 | sed -E 's/^Moved to //; s/ $//')
  [ -f "$tgt" ] && grep -q '^# /// script' "$tgt" || continue
  [ "$(sed -n '/^# \/\/\/ script/,/^# \/\/\/$/p' "$tgt")" = "$(sed -n '/^# \/\/\/ script/,/^# \/\/\/$/p' "$s")" ] || meta_bad="$meta_bad $s"
done
[ -z "$meta_bad" ] && ok "every stub of a uv script carries its inline dependencies" || no "stubs missing their target's # /// script block:$meta_bad"

names=$(for s in $stubs; do basename "$s"; done | grep . | sed 's/[.]/\\./g' | paste -sd'|' -)
[ -n "$names" ] || { no "harness: no stub names found"; echo "$pass passed, $fail failed"; exit 1; }
# A `<ref>:hooks/...` path names a file inside an OLDER commit (a pinned pre-#309 control), so it keeps
# the old layout on purpose: a colon before hooks/ is skipped.
hits=$(git grep -nE "(^|[^a-zA-Z0-9_./:-])hooks/($names)([^a-zA-Z0-9_-]|$)" -- . \
        ':!CHANGELOG.md' ':!tests/hooks-layout.test.sh' ':!hooks/install/install-settings.py' ':!tests/install-settings.test.sh' \
        $(for s in $stubs; do printf ":!%s " "$s"; done) | grep -vE 'Moved to hooks/' | head -10)
[ -z "$hits" ] && ok "nothing outside the stubs names an old top-level hook path" || no "old paths still referenced:
$hits"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

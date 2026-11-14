#!/usr/bin/env bash
# Two /aios:update defects a release dry run found (v0.8.18):
#   1. Step 2 listed changed files with git's rename detection on, so a file canonical MOVED was
#      reported only by its new path; the old copy never reached Step 3.4's deletion pass and stayed
#      in every vault. The diff must carry --no-renames.
#   2. Step 1.5 streamed the CHANGELOG up to "$STOP_HEADER", a variable nothing defined, so the
#      block could not run as written. It must define it: the first entry whose hashes are ALL synced.
# Plus three a second dry run found: Step 1.5 never set CLONE, Steps 3/3.4 read a FILES array
# nothing defined, and the cache-sync loops abort zsh when no cache exists.
# Runs Step 1.5's block from update.md, under bash and zsh, against a fixture repo.
# Usage: bash tests/update-renames-and-stop.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
U="$ROOT/plugins/aios/commands/update.md"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "update-renames-and-stop"

grep -q 'diff --no-renames {stored_hash}..HEAD --name-only' "$U" && ok "Step 2's file list turns rename detection off" || no "Step 2 lists renames by their new path only"

# Found by the second dry run: each tool call is a fresh shell, so state must not live in variables.
grep -q '| tee "$CLONE/.git/aios-update-files"' "$U" && ok "Step 2 saves its file list where Step 3 can read it" || no "Step 2's list lives only in the shell that printed it"
! grep -q '"${FILES\[@\]}"' "$U" && ok "no step reads a FILES array nothing defines" || no "a step still reads \${FILES[@]}"
sed -n '/^CLONE="\/tmp\/aios-update-check"   # each tool call/,/^STOP_HEADER=/p' "$U" | grep -q STOP_HEADER && ok "Step 1.5 sets CLONE itself" || no "Step 1.5 relies on CLONE from another call"
! grep -qE 'for d in "\$HOME"/\.claude/plugins/cache/the-aios/aios/\*/commands/' "$U" && ok "no cache loop aborts zsh on an unmatched glob" || no "a cache loop still globs (zsh aborts when there is no cache)"
[ "$(grep -c "Step 2's saved list is missing" "$U")" -ge 2 ] && ok "Steps 3 and 3.4 refuse to run on a missing list instead of applying nothing" || no "a step reads the saved list without checking it exists"
grep -q "starting again at Step 1.5 under it, then Step 2's block run again" "$U" && ok "after a self-update, the changelog (1.5) and the file list (2) are redone under the new spec" || no "a self-update resumes past the changelog step (the old one showed only part of the entries)"
! grep -qE 'for d in "\$HOME"/\.claude/plugins/cache/[^ ]*\*' "$U" && ok "no cache lookup loops over a glob (zsh aborts on no match)" || no "a cache lookup still loops over a glob"
T=$(mktemp -d "${TMPDIR:-/tmp}/urs.XXXXXX")
R="$T/repo"; mkdir -p "$R"
g(){ git -C "$R" -c user.name=t -c user.email=t@example.com "$@" >/dev/null 2>&1; }
g init -q
printf 'old\n' > "$R/old.md"
printf '# Changelog\n\n## 2026-01-01 — first\n\n`hash: 0000000`\n\nfirst body\n' > "$R/CHANGELOG.md"
g add -A; g commit -qm a
A=$(git -C "$R" rev-parse --short HEAD)
sed -i.bak "s/0000000/$A/" "$R/CHANGELOG.md" && rm -f "$R/CHANGELOG.md.bak"; g add -A; g commit -qm a2
A=$(git -C "$R" rev-parse --short HEAD)
sed -i.bak "s/\`hash: [0-9a-f]*\`/\`hash: $A\`/" "$R/CHANGELOG.md" && rm -f "$R/CHANGELOG.md.bak"
g mv old.md new.md; g commit -qm b
B=$(git -C "$R" rev-parse --short HEAD)
python3 - "$R/CHANGELOG.md" "$B" "$A" <<'PY'
import sys
p, b, a = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read().replace("# Changelog\n\n", "# Changelog\n\n## 2026-02-01 — second\n\n`hash: %s · %s`\n\nsecond body\n\n" % (a, b), 1)
open(p, "w").write(s)
PY
g add -A; g commit -qm c
STORED="$A"   # synced through the first entry; the second is new

names=$(git -C "$R" diff --no-renames "$STORED"..HEAD --name-only)
printf '%s\n' "$names" | grep -qx 'old.md' && ok "with --no-renames the moved file's old path is listed" || no "old path missing from the list"
plain=$(git -C "$R" diff "$STORED"..HEAD --name-only)
printf '%s\n' "$plain" | grep -qx 'old.md' && no "control: rename detection did not hide the old path (fixture proves nothing)" || ok "control: without it the old path is hidden"

sed -n '/^STOP_HEADER=/,/^awk .*stop!=/p' "$U" > "$T/block.sh"
[ -s "$T/block.sh" ] && ok "Step 1.5 defines STOP_HEADER before streaming" || no "Step 1.5 never defines STOP_HEADER"
sed -e "s#{stored_hash}#$STORED#g" -e "s#\$CLONE#$R#g" "$T/block.sh" > "$T/run.sh"
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { echo "  skip $sh not installed"; continue; }
  out=$("$sh" "$T/run.sh" 2>&1)
  if printf '%s\n' "$out" | grep -q '^## 2026-02-01' && ! printf '%s\n' "$out" | grep -q '^## 2026-01-01'; then
    ok "$sh: shows the new entry and stops at the synced one"
  else
    no "$sh: wrong slice: $(printf '%s' "$out" | grep '^## ' | tr '\n' ' ')"
  fi
done
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

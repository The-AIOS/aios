#!/usr/bin/env bash
# tests/aios-commit-reconcile.test.sh
#
# "Another machine pushed first" is the push failure a multi-machine vault meets most. When the
# two sides changed DIFFERENT files, aios-commit combines them (git merge-tree, never in the working
# tree), writes only the remote's files to disk, and pushes. When they changed the same file, or
# the operator has edits to a file the remote changed, it touches nothing and says why.
# Two clones of one bare remote; the twin always pushes first. bash 3.2-safe.
set -uo pipefail
AC="$(cd "$(dirname "$0")/.." && pwd)/hooks/aios-commit"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
g(){ git -c user.name=t -c user.email=t@x "$@"; }
git init -q --bare "$T/r.git"; g -C "$T/r.git" symbolic-ref HEAD refs/heads/main
g clone -q "$T/r.git" "$T/a" 2>/dev/null; cd "$T/a"; g checkout -q -b main 2>/dev/null; echo a > a.md; echo b > b.md; echo c > c.md; g add -A; g commit -qm init; g push -q -u origin main
g clone -q "$T/r.git" "$T/twin"
for d in "$T/a" "$T/twin"; do git -C "$d" config user.name t; git -C "$d" config user.email t@x; done
pass=0; fail=0; ok(){ echo "  ok   $1"; pass=$((pass+1)); }; no(){ echo "  FAIL $1"; fail=$((fail+1)); }
# 1. disjoint
( cd "$T/twin" && echo twin > b.md && g commit -qam twin-b && g push -q )
echo mine > a.md
out=$(bash "$AC" -m "mine-a" a.md 2>&1)
case "$out" in *"combined"*"pushed."*) ok "disjoint: combined and pushed" ;; *) no "disjoint — $out" ;; esac
[ "$(cat b.md)" = twin ] && ok "the twin's file is on disk" || no "b.md on disk: $(cat b.md)"
[ "$(git -C "$T/r.git" show main:a.md)" = mine ] && [ "$(git -C "$T/r.git" show main:b.md)" = twin ] && ok "the remote has both changes" || no "remote content wrong"
[ -z "$(git status --porcelain)" ] && ok "working tree clean afterwards" || no "dirty: $(git status --porcelain | head -3)"
# 2. overlap
( cd "$T/twin" && g pull -q && echo twin2 > c.md && g commit -qam twin-c && g push -q )
echo mine2 > c.md
out=$(bash "$AC" -m "mine-c" c.md 2>&1)
case "$out" in *"both machines changed: c.md"*) ok "overlap: stops and names the file" ;; *) no "overlap — $out" ;; esac
[ "$(cat c.md)" = mine2 ] && ok "…and the local file is untouched" || no "local c.md changed"
# 3. local edit to a remote-changed file
g fetch -q; g reset -q --hard origin/main
( cd "$T/twin" && g pull -q && echo twin3 > b.md && g commit -qam twin-b2 && g push -q )
echo local-wip > b.md          # operator is editing b.md, not committing it
echo mine3 > a.md
out=$(bash "$AC" -m "mine-a3" a.md 2>&1)
case "$out" in *"local edits to b.md"*) ok "a local edit to a remote-changed file stops it" ;; *) no "dirty remote path — $out" ;; esac
[ "$(cat b.md)" = local-wip ] && ok "…and the operator's edit is untouched" || no "operator edit lost: $(cat b.md)"
# 4. a remote file NAMED like a pathspec must stay literal: `*` must not check out every file
g fetch -q; g reset -q --hard origin/main
( cd "$T/twin" && g pull -q && echo star > '*' && g add -- '*' && g commit -qm star && g push -q )
echo wip > c.md                # the operator's uncommitted edit, on a file the remote did NOT change
echo mine4 > a.md
out=$(bash "$AC" -m "mine-a4" a.md 2>&1)
case "$out" in *"combined"*) ok "a remote file named '*' still reconciles" ;; *) no "glob-named file — $out" ;; esac
[ "$(cat c.md)" = wip ] && ok "…and the operator's unrelated edit survives (the name stayed literal)" || no "a glob name overwrote c.md: $(cat c.md)"
[ "$(cat '*')" = star ] && ok "…and the '*' file itself arrived" || no "the '*' file is missing"
git checkout -q -- c.md
# 5. a name git would quote (non-ASCII) changed on BOTH sides is still an overlap
( cd "$T/twin" && g pull -q && echo t > 'café.md' && g add -- 'café.md' && g commit -qm cafe1 && g push -q )
g pull -q 2>/dev/null
( cd "$T/twin" && echo t2 > 'café.md' && g commit -qam cafe2 && g push -q )
echo m > 'café.md'
out=$(bash "$AC" -m "cafe-mine" 'café.md' 2>&1)
case "$out" in *"both machines changed"*) ok "a non-ASCII name changed on both sides is caught as overlap" ;; *) no "quoted-name overlap missed — $out" ;; esac

# 6. removals never use a bare rm (it follows a symlinked directory out of the repo; `git rm`
#    refuses any path "beyond a symbolic link"). A git tree cannot express the attack directly, so
#    this is a static guard on the function rather than a runtime case that would pass either way.
FN=$(awk '/^reconcile_diverged\(\)\{/,/^\}/' "$AC")
[ -n "$FN" ] || no "could not read reconcile_diverged from aios-commit"
printf '%s\n' "$FN" | grep -v '^ *#' | sed 's/git rm/GIT_RM/g' | grep -E '(^|[^a-z_-])rm -' >/dev/null \
  && no "reconcile_diverged removes files with a bare rm" || ok "reconcile_diverged removes files only through git rm"

echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]

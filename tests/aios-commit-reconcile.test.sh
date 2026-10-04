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
echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]

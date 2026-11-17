#!/usr/bin/env bash
# tests/aios-commit-reconcile.test.sh
#
# "Another machine pushed first" is the push failure a multi-machine vault meets most. When the
# two sides changed DIFFERENT files, aios-commit combines them (git merge-tree, never in the working
# tree), writes only the remote's files to disk, and pushes. When they changed the same file, or
# the operator has edits to a file the remote changed, it touches nothing and says why.
# Two clones of one bare remote; the twin always pushes first. bash 3.2-safe.
set -uo pipefail
AC="$(cd "$(dirname "$0")/.." && pwd)/hooks/vault/aios-commit"
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

# 7. the SAME file changed on both sides, on different lines: merge-tree decides by content, so it
#    combines instead of refusing by name
g fetch -q; g reset -q --hard origin/main
printf 'one\ntwo\nthree\nfour\nfive\n' > n.md; bash "$AC" -m "n-init" n.md >/dev/null 2>&1
( cd "$T/twin" && g pull -q && sed 's/^one$/ONE-twin/' n.md > n.tmp && mv n.tmp n.md && g commit -qam twin-n && g push -q )
sed 's/^five$/FIVE-mine/' n.md > n.tmp && mv n.tmp n.md
out=$(bash "$AC" -m "mine-n" n.md 2>&1)
case "$out" in *"both changed n.md without conflicting"*"pushed."*) ok "same file, different lines: combined and pushed" ;; *) no "same-file clean merge — $out" ;; esac
r=$(git -C "$T/r.git" show main:n.md)
case "$r" in *ONE-twin*FIVE-mine*) ok "…the remote has both edits" ;; *) no "remote n.md: $r" ;; esac
case "$(cat n.md)" in *ONE-twin*FIVE-mine*) ok "…and so does the file on disk" ;; *) no "disk n.md: $(cat n.md)" ;; esac
[ -z "$(git status --porcelain)" ] && ok "…and the tree is clean" || no "dirty after same-file merge: $(git status --porcelain | head -3)"

# 8. a STAGED change to a remote-changed file, with the file on disk back at HEAD, must stop it:
#    a HEAD-vs-disk diff sees nothing, and the checkout would drop what was staged
g fetch -q; g reset -q --hard origin/main
( cd "$T/twin" && g pull -q && echo twin8 > b.md && g commit -qam twin-b8 && g push -q )
orig=$(cat b.md); echo staged8 > b.md; g add b.md; echo "$orig" > b.md
echo mine8 > a.md
out=$(bash "$AC" -m "mine-a8" a.md 2>&1)
case "$out" in *"local edits to b.md"*) ok "a staged change to a remote-changed file stops it" ;; *) no "staged remote path — $out" ;; esac
[ "$(git show :b.md)" = staged8 ] && ok "…and what was staged survives" || no "staged b.md lost: $(git show :b.md)"
g reset -q b.md; git checkout -q -- b.md

# 9. a push left pending by a blocker is swept by the next run once the blocker is gone, even with
#    nothing new to commit: the sweep reconciles instead of retrying a bare push forever
g fetch -q; g reset -q --hard origin/main; rm -f "$(git rev-parse --git-dir)/aios-push-pending"
( cd "$T/twin" && g pull -q && echo twin9 > b.md && g commit -qam twin-b9 && g push -q )
echo wip9 > b.md; echo mine9 > a.md
bash "$AC" -m "mine-a9" a.md >/dev/null 2>&1
stranded=$(git rev-parse HEAD)
[ -f "$(git rev-parse --git-dir)/aios-push-pending" ] && ok "blocked: the push is left pending" || no "no pending marker after a blocked push"
git checkout -q -- b.md          # the blocking edit is finished (discarded, here)
out=$(bash "$AC" -m "nothing" a.md 2>&1)
git -C "$T/r.git" merge-base --is-ancestor "$stranded" main 2>/dev/null && ok "the next run sweeps it: the stranded commit is on the remote" || no "still stranded — $out"
[ ! -f "$(git rev-parse --git-dir)/aios-push-pending" ] && ok "…and the marker is settled" || no "marker left: $(cat "$(git rev-parse --git-dir)/aios-push-pending")"
[ "$(cat b.md)" = twin9 ] && ok "…and the twin's file is on disk" || no "b.md after sweep: $(cat b.md)"

# 10. a rename HERE and an edit THERE: the merge moves the remote's edit to the new name, and that
#     name -- not the remote's old one -- is what must reach disk and the index
g fetch -q; g reset -q --hard origin/main; rm -f "$(git rev-parse --git-dir)/aios-push-pending"
printf 'r1\nr2\nr3\n' > ren.md; bash "$AC" -m "ren-init" ren.md >/dev/null 2>&1
( cd "$T/twin" && g pull -q && sed 's/^r2$/R2-twin/' ren.md > x && mv x ren.md && g commit -qam twin-ren && g push -q )
g mv ren.md moved.md; g commit -qm "rename here"
echo mine10 > a.md
out=$(bash "$AC" -m "mine-a10" a.md 2>&1)
case "$(git show HEAD:moved.md 2>/dev/null)" in *R2-twin*) ok "rename: the merged commit carries the remote's edit under the new name" ;; *) no "rename merge — $out" ;; esac
case "$(cat moved.md 2>/dev/null)" in *R2-twin*) ok "…and so does the file on disk" ;; *) no "disk moved.md: $(cat moved.md 2>/dev/null)" ;; esac
[ -z "$(git status --porcelain)" ] && ok "…and nothing is left staged or dirty (no reverted remote edit)" || no "after rename merge: $(git status --porcelain | head -3)"

# 11. a STAGED DELETION of a file both sides edited compatibly is the operator's: absent from the
#     index and from disk, only an index-vs-HEAD diff sees it
g fetch -q; g reset -q --hard origin/main; rm -f "$(git rev-parse --git-dir)/aios-push-pending"
printf 'd1\nd2\nd3\nd4\nd5\n' > del.md; bash "$AC" -m "del-init" del.md >/dev/null 2>&1
( cd "$T/twin" && g pull -q && sed 's/^d1$/D1-twin/' del.md > x && mv x del.md && g commit -qam twin-del && g push -q )
sed 's/^d5$/D5-mine/' del.md > x && mv x del.md && g commit -qam "mine del.md"
g rm -q del.md
echo mine11 > a.md
out=$(bash "$AC" -m "mine-a11" a.md 2>&1)
case "$out" in *"local edits to del.md"*) ok "a staged deletion of a merged file stops it" ;; *) no "staged deletion — $out" ;; esac
[ ! -e del.md ] && ! git ls-files --error-unmatch del.md >/dev/null 2>&1 && ok "…and the deletion is still staged" || no "deletion lost: del.md is back"

# 12. a file flagged assume-unchanged or skip-worktree hides its edits from `git diff`: one the merge
#     would rewrite is left to the operator, never checked out over
for flag in assume-unchanged skip-worktree; do
  g fetch -q; g reset -q --hard origin/main; rm -f "$(git rev-parse --git-dir)/aios-push-pending"
  printf 'h1\nh2\nh3\n' > hid.md; bash "$AC" -m "hid-init $flag" hid.md >/dev/null 2>&1
  ( cd "$T/twin" && g pull -q && sed 's/^h1$/H1-twin/' hid.md > x && mv x hid.md && g commit -qam "twin-hid $flag" && g push -q )
  g update-index --$flag hid.md; echo "hidden-$flag" > hid.md
  echo "mine12-$flag" > a.md
  out=$(bash "$AC" -m "mine-a12 $flag" a.md 2>&1)
  [ "$(cat hid.md)" = "hidden-$flag" ] && ok "$flag: the hidden local edit survives" || no "$flag edit overwritten — $out"
  g update-index --no-$flag hid.md; git checkout -q -- hid.md
done

# 13. the remote replaces a DIRECTORY with a file of the same name: untracked or ignored files the
#     operator keeps inside it here must never be removed to make room
for kind in untracked ignored; do
  g fetch -q; g reset -q --hard origin/main; rm -f "$(git rev-parse --git-dir)/aios-push-pending"
  mkdir -p "dd-$kind"; echo v > "dd-$kind/versioned.md"; bash "$AC" -m "dd-init $kind" "dd-$kind/versioned.md" >/dev/null 2>&1
  ( cd "$T/twin" && g pull -q && g rm -q -r "dd-$kind" && echo file > "dd-$kind" && g add -- "dd-$kind" && g commit -qm "twin dd $kind" && g push -q )
  echo draft > "dd-$kind/draft.md"
  [ "$kind" = ignored ] && echo "dd-$kind/draft.md" >> "$(git rev-parse --git-dir)/info/exclude"
  echo "mine13-$kind" > a.md
  out=$(bash "$AC" -m "mine-a13 $kind" a.md 2>&1)
  [ "$(cat "dd-$kind/draft.md" 2>/dev/null)" = draft ] && ok "dir→file ($kind): the local draft inside it survives" || no "dir→file ($kind) removed the draft — $out"
done

# 6. removals never use a bare rm (it follows a symlinked directory out of the repo; `git rm`
#    refuses any path "beyond a symbolic link"). A git tree cannot express the attack directly, so
#    this is a static guard on the function rather than a runtime case that would pass either way.
FN=$(awk '/^reconcile_diverged\(\)\{/,/^\}/' "$AC")
[ -n "$FN" ] || no "could not read reconcile_diverged from aios-commit"
printf '%s\n' "$FN" | grep -v '^ *#' | sed 's/git rm/GIT_RM/g' | grep -E '(^|[^a-z_-])rm -' >/dev/null \
  && no "reconcile_diverged removes files with a bare rm" || ok "reconcile_diverged removes files only through git rm"

echo "-- $pass passed, $fail failed --"
[ "$fail" -eq 0 ]

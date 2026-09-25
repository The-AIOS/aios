#!/usr/bin/env bash
# tests/lock-reclaim-and-head-cas.test.sh
#
# Three ways the commit and archive helpers lost work while every step reported success.
#
# 1. RECLAIM RACE (aios-commit, aios-snapshot, aios-note-append). A lock left by a dead process
#    is reclaimed. Two waiters read the same dead pid; with a bare `rm -rf` the slower one
#    deleted the lock the faster one had just re-created, and both ran as holders.
# 2. HEAD MOVED MID-COMMIT (aios-commit). The tree was built from HEAD, but `-p HEAD` resolved
#    HEAD again at commit-tree time and `update-ref HEAD` carried no old value. A commit landing
#    in between, from anything that does not take aios-commit's lock, was silently reverted.
# 3. PENDING-PUSH MARKER (aios-commit). A successful push cleared the marker even when HEAD was
#    still ahead of the remote, erasing the only record that a newer commit was stranded.
#
# Each case runs against the current hooks and against the hooks at a pinned pre-change commit,
# where it must reproduce the defect. The pinned half is skipped, with a message, when that
# commit is not present. The race cases inject the same delay into both variants; the only
# difference between them is the code under test.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lockcas.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.io GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.io
REAL_GIT=$(command -v git)

PIN=3d135ded112bf7b77156b61bb29e6233ff7c7285
HAVE_OLD=0
mkdir -p "$TMP/new/git" "$TMP/old/git"
for h in aios-commit aios-snapshot aios-note-append git/secret-scan.sh; do
  cp "$ROOT/hooks/$h" "$TMP/new/$h"
done
if git -C "$ROOT" cat-file -e "$PIN:hooks/aios-commit" 2>/dev/null; then
  for h in aios-commit aios-snapshot aios-note-append git/secret-scan.sh; do
    git -C "$ROOT" show "$PIN:hooks/$h" > "$TMP/old/$h"
  done
  cmp -s "$TMP/old/aios-commit" "$TMP/new/aios-commit" || HAVE_OLD=1
fi
chmod +x "$TMP"/new/* "$TMP"/new/git/* "$TMP"/old/* "$TMP"/old/git/* 2>/dev/null
[ "$HAVE_OLD" = 1 ] || echo "  SKIP  old-hook reproductions: $PIN not present or identical"

dead_pid(){ sleep 0 & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }

echo "── 1. a stale lock is reclaimed once, never out from under a new holder ──"
# Variant builder: the same delay between reading the dead pid and removing the lock, and a
# wider critical section, injected into both old and new. The lock logic is the only difference.
# The delay is STAGGERED per writer (1.1 s, 1.2 s, ...): each wakes 0.1 s after the previous one
# took the lock and before that one copies (0.3 s later). Unstaggered, whether a late reclaimer
# hit a live lock or an empty slot was down to scheduling, and the old code lost content only
# on some runs -- a control that fails at random proves nothing either way.
mkvariant(){ # $1 old|new → $TMP/race-$1/aios-snapshot
  mkdir -p "$TMP/race-$1"
  "$REAL_PY" - "$TMP/$1/aios-snapshot" "$TMP/race-$1/aios-snapshot" <<'PY'
import sys
u = open(sys.argv[1]).read()
for a in ('reclaim "$LOCK" "$holder"', 'rm -rf "$LOCK" 2>/dev/null; continue'):
    if a in u:
        u = u.replace(a, 'sleep "1.${AIOS_T_IDX:-1}"; ' + a, 1); break
else:
    sys.exit("reclaim anchor not found")
# The copy line is `cp -p` before the atomic-copy change and `put` after it; either will do.
for a in ('    put "$src" "$cand" || break', '    cp -p "$src" "$cand" || break'):
    if a in u:
        u = u.replace(a, '    sleep 0.3\n' + a, 1); break
else:
    sys.exit("copy anchor not found")
# Mutual exclusion is measured directly: every holder logs "in" when it gets the lock and
# "out" just before it releases it. Lost content is a symptom; two holders at once is the defect.
a = 'acquire; LOCKED=1'
assert u.count(a) == 1, "acquire anchor"
u = u.replace(a, a + '; echo in >> "$AIOS_T_LOG"', 1)
a = '\nrelease\nexit "$RC"'
assert u.count(a) == 1, "release anchor"
u = u.replace(a, '\necho out >> "$AIOS_T_LOG"\nrelease\nexit "$RC"', 1)
open(sys.argv[2], "w").write(u)
PY
  chmod +x "$TMP/race-$1/aios-snapshot"
}
REAL_PY=""; for c in python3 python; do $c -c 'import sys' >/dev/null 2>&1 && { REAL_PY=$c; break; }; done
[ -n "$REAL_PY" ] || { echo "SKIP: no python"; exit 0; }
race(){ # $1 old|new → "kept max_holders failed_writers"
  local r d i pids="" bad=0; r=$(mktemp -d "$TMP/root.XXXXXX"); d="$r/vault/00 - notes/logs/observed-snapshots/2026-08"
  mkdir -p "$d/.aios-snapshot.lock"; dead_pid > "$d/.aios-snapshot.lock/pid"
  printf 'base\n' > "$d/2026-08-14-obs.md"
  for i in 1 2 3 4 5 6; do mkdir -p "$r/w$i"; printf 'content-%s\n' "$i" > "$r/w$i/obs.md"; done
  for i in 1 2 3 4 5 6; do
    AIOS_T_LOG="$r/holders" AIOS_T_IDX=$i "$TMP/race-$1/aios-snapshot" --root "$r" --date 2026-08-14 "$r/w$i/obs.md" >/dev/null 2>&1 &
    pids="$pids $!"
  done
  for i in $pids; do wait "$i" || bad=$((bad+1)); done
  echo "$(cat "$d"/*obs.md 2>/dev/null | grep -c '^content-') $(awk '/in/{n++; if(n>m)m=n} /out/{n--} END{print m+0}' "$r/holders" 2>/dev/null || echo 0) $bad"
}
mkvariant new
read -r KEPT MAXH BAD <<<"$(race new)"
{ [ "$KEPT" = 6 ] && [ "$MAXH" = 1 ] && [ "$BAD" = 0 ]; } \
  && ok "NEW: 6 writers meet a lock left by a dead process; never more than 1 holder, all 6 contents kept, all exit 0" \
  || no "NEW: max holders $MAXH, kept $KEPT of 6, $BAD writer(s) failed" "two writers held the lock at once"
if [ "$HAVE_OLD" = 1 ]; then
  mkvariant old
  read -r KEPT MAXH BAD <<<"$(race old)"
  { [ "$MAXH" -gt 1 ] && [ "$BAD" = 0 ]; } \
    && ok "OLD: $MAXH holders at once, $KEPT of 6 contents kept, every writer exited 0 (the defect, reproduced)" \
    || no "OLD: the race did not reproduce (max holders $MAXH, $BAD failed)" "the control proves nothing if it cannot fail"
fi

# The same reclaim function is in all three helpers. Unit-check it in each: a lock that names a
# live or different pid, or no pid yet, is never removed; a busy mutex defers; a stale one clears.
for h in aios-commit aios-snapshot aios-note-append; do
  fn=$(sed -n '/^reclaim(){/,/^}/p' "$TMP/new/$h")
  if [ -z "$fn" ]; then no "$h has no reclaim function"; continue; fi
  res=$(bash -c "$fn"'
    L="$1/l"; D=$2; mkdir -p "$L"
    echo "$D" > "$L/pid"; reclaim "$L" "$D"; [ -d "$L" ] && echo "dead:kept" || echo "dead:gone"
    mkdir -p "$L"; echo $$ > "$L/pid"; reclaim "$L" "$D"; [ -d "$L" ] && echo "renewed:kept" || echo "renewed:gone"
    rm -f "$L/pid"; reclaim "$L" "$D"; [ -d "$L" ] && echo "nopid:kept" || echo "nopid:gone"
    echo "$D" > "$L/pid"; mkdir "$L.reclaim"; reclaim "$L" "$D"; [ -d "$L" ] && echo "busy:kept" || echo "busy:gone"
    touch -t 202001010000 "$L.reclaim"; reclaim "$L" "$D"
    [ -d "$L" ] && [ -d "$L.reclaim" ] && echo "oldmutex:left" || echo "oldmutex:removed"
  ' _ "$(mktemp -d "$TMP/u.XXXXXX")" "$(dead_pid)" | tr '\n' ' ')
  [ "$res" = "dead:gone renewed:kept nopid:kept busy:kept oldmutex:left " ] \
    && ok "$h: reclaim removes only the dead holder's lock, and never someone else's mutex ($res)" \
    || no "$h: reclaim misbehaved: $res" "expected dead:gone renewed:kept nopid:kept busy:kept oldmutex:left"
done

# A reclaimer that died inside its critical section leaves a lock with a dead pid AND its
# mutex. Nobody may remove that mutex, so the wait must END: bounded, and naming the mutex.
# The hooks' 600-try timeout is shortened to 20 here; the path taken is the same.
mkdir -p "$TMP/short"
for h in aios-commit aios-snapshot aios-note-append; do
  sed 's/-gt 600 \]/-gt 20 ]/' "$TMP/new/$h" > "$TMP/short/$h"; chmod +x "$TMP/short/$h"
done
mkdir -p "$TMP/short/git"; cp "$TMP/new/git/secret-scan.sh" "$TMP/short/git/"
# A watchdog, so the defect -- a wait that never ends -- fails this test instead of hanging it.
watchdog(){ # $1 seconds · $2.. command → its exit code, or 137 if it had to be killed
  "${@:2}" & local pid=$! w
  ( sleep "$1"; kill -9 "$pid" 2>/dev/null ) & w=$!
  wait "$pid"; local rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}
bounded(){ # $1 hook → "rc seconds names_mutex"
  local r lock t0 rc out
  r=$(mktemp -d "$TMP/ab.XXXXXX")
  case "$1" in
    aios-commit) git -C "$r" init -q; echo x > "$r/f"; lock="$r/.git/aios-commit.lock" ;;
    aios-snapshot) lock="$r/vault/00 - notes/logs/observed-snapshots/2026-08/.aios-snapshot.lock"; echo x > "$r/obs.md" ;;
    aios-note-append) echo "# note" > "$r/n.md"; echo blk > "$r/blk"; lock="$r/n.md.aios-lock" ;;
  esac
  mkdir -p "$lock" "$lock.reclaim"; dead_pid > "$lock/pid"
  t0=$(date +%s)
  case "$1" in
    aios-commit) (cd "$r" && watchdog 20 "$TMP/short/aios-commit" --no-push -m x -- f) >"$r.out" 2>&1 ;;
    aios-snapshot) watchdog 20 "$TMP/short/aios-snapshot" --root "$r" --date 2026-08-14 "$r/obs.md" >"$r.out" 2>&1 ;;
    aios-note-append) watchdog 20 "$TMP/short/aios-note-append" --note "$r/n.md" --block-file "$r/blk" -m x --no-push >"$r.out" 2>&1 ;;
  esac; rc=$?; out=$(cat "$r.out")
  echo "$rc $(( $(date +%s) - t0 )) $(printf '%s' "$out" | grep -c 'reclaim')"
}
for h in aios-commit aios-snapshot aios-note-append; do
  read -r RC SECS NAMED <<<"$(bounded "$h")"
  { [ "$RC" != 0 ] && [ "$SECS" -lt 15 ] && [ "$NAMED" -ge 1 ]; } \
    && ok "$h: a lock left with its reclaim mutex ends the wait (exit $RC after ${SECS}s) and names the mutex" \
    || no "$h: abandoned mutex → rc=$RC after ${SECS}s, mutex named: $NAMED" "a wait that cannot end hangs every later run"
done

echo "── 2. a commit that lands mid-run is never reverted or orphaned ──"
# A git shim that, once, makes a commit of its own just before aios-commit's commit-tree runs,
# the way a plain `git commit` or an editor plugin would, outside aios-commit's lock.
SHIM="$TMP/shim-cas"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\${1:-}" = commit-tree ] && [ ! -e "\$INTRUDED" ]; then
  : > "\$INTRUDED"
  echo theirs > their.txt
  GIT_INDEX_FILE="\$INTRUDED.idx" "$REAL_GIT" read-tree HEAD
  GIT_INDEX_FILE="\$INTRUDED.idx" "$REAL_GIT" add their.txt
  t=\$(GIT_INDEX_FILE="\$INTRUDED.idx" "$REAL_GIT" write-tree)
  c=\$("$REAL_GIT" commit-tree "\$t" -p HEAD -m theirs)
  "$REAL_GIT" update-ref HEAD "\$c"
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"
cas(){ # $1 old|new → "rc their_in_HEAD their_reachable mine_in_HEAD"
  local r rc; r=$(mktemp -d "$TMP/cas.XXXXXX")
  git -C "$r" init -q; echo base > "$r/base.txt"; git -C "$r" add base.txt; git -C "$r" commit -qm base
  echo mine > "$r/mine.txt"
  (cd "$r" && INTRUDED="$r/.intruded" PATH="$SHIM:$PATH" "$TMP/$1/aios-commit" --no-push -m "mine" -- mine.txt >"$r/.out" 2>&1); rc=$?
  local their mine reach
  git -C "$r" cat-file -e HEAD:their.txt 2>/dev/null && their=yes || their=no
  git -C "$r" cat-file -e HEAD:mine.txt 2>/dev/null && mine=yes || mine=no
  git -C "$r" log --format=%s HEAD | grep -qx theirs && reach=yes || reach=no
  echo "$rc $their $reach $mine $(grep -c 'HEAD moved' "$r/.out")"
}
read -r RC THEIR REACH MINE MSG <<<"$(cas new)"
{ [ "$RC" != 0 ] && [ "$THEIR" = yes ] && [ "$REACH" = yes ] && [ "$MINE" = no ] && [ "$MSG" = 1 ]; } \
  && ok "NEW: HEAD moved mid-run → refused and named; the other commit is intact at HEAD" \
  || no "NEW: rc=$RC their-in-HEAD=$THEIR their-reachable=$REACH mine=$MINE msg=$MSG" "the intruding commit must survive untouched"
if [ "$HAVE_OLD" = 1 ]; then
  read -r RC THEIR REACH MINE MSG <<<"$(cas old)"
  { [ "$RC" = 0 ] && [ "$THEIR" = no ] && [ "$MINE" = yes ]; } \
    && ok "OLD: exit 0, and their.txt is gone from HEAD's tree (the other commit was reverted; reachable=$REACH)" \
    || no "OLD: did not reproduce (rc=$RC their=$THEIR mine=$MINE)" "check the pin"
fi

# A checkout of ANOTHER branch at the same commit, mid-run. The old value still matches, so a
# swap on HEAD would follow the checkout and put this commit on the other branch.
SSHIM="$TMP/shim-switch"; mkdir -p "$SSHIM"
cat > "$SSHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\${1:-}" = commit-tree ] && [ ! -e "\$INTRUDED" ]; then
  : > "\$INTRUDED"; "$REAL_GIT" symbolic-ref HEAD refs/heads/other
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SSHIM/git"
switch(){ switch_with "$SSHIM" "$1"; }
switch_with(){ # $1 shim dir · $2 old|new → "rc main_has_mine other_has_mine ran"
  local r rc; r=$(mktemp -d "$TMP/sw.XXXXXX")
  git -C "$r" init -q; git -C "$r" symbolic-ref HEAD refs/heads/main
  echo base > "$r/base.txt"; git -C "$r" add base.txt; git -C "$r" commit -qm base; git -C "$r" branch other
  echo mine > "$r/mine.txt"
  (cd "$r" && INTRUDED="$r/.sw" PATH="$1:$PATH" "$TMP/$2/aios-commit" --no-push -m mine -- mine.txt >/dev/null 2>&1); rc=$?
  echo "$rc $(git -C "$r" cat-file -e main:mine.txt 2>/dev/null && echo yes || echo no) $(git -C "$r" cat-file -e other:mine.txt 2>/dev/null && echo yes || echo no) $([ -e "$r/.sw" ] && echo ran || echo idle)"
}
read -r RC ONMAIN ONOTHER RAN <<<"$(switch new)"
{ [ "$RAN" = ran ] && [ "$RC" = 0 ] && [ "$ONMAIN" = yes ] && [ "$ONOTHER" = no ]; } \
  && ok "NEW: HEAD switched to another branch at the same commit mid-run → the commit lands on the branch it started on" \
  || no "NEW: shim=$RAN rc=$RC on-main=$ONMAIN on-other=$ONOTHER" "a checkout mid-run must not redirect the commit"
if [ "$HAVE_OLD" = 1 ]; then
  read -r RC ONMAIN ONOTHER RAN <<<"$(switch old)"
  { [ "$RAN" = ran ] && [ "$ONOTHER" = yes ] && [ "$ONMAIN" = no ]; } \
    && ok "OLD: the same switch put the commit on the other branch (rc=$RC)" \
    || no "OLD: did not reproduce (shim=$RAN on-main=$ONMAIN on-other=$ONOTHER)" "check the pin"
fi

# The branch switch can also land right after the branch is READ -- before the commit is
# resolved. Resolving the commit from the captured branch makes that window harmless.
RSW="$TMP/shim-readswitch"; mkdir -p "$RSW"
cat > "$RSW/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\$*" = "symbolic-ref -q HEAD" ] && [ ! -e "\$INTRUDED" ]; then
  : > "\$INTRUDED"; out=\$("$REAL_GIT" "\$@"); rc=\$?
  "$REAL_GIT" symbolic-ref HEAD refs/heads/other; echo "\$out"; exit \$rc
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$RSW/git"
read -r RC ONMAIN ONOTHER RAN <<<"$(switch_with "$RSW" new)"
{ [ "$RAN" = ran ] && [ "$ONMAIN" = yes ] && [ "$ONOTHER" = no ]; } \
  && ok "NEW: a switch right after the branch is read still leaves the commit on the branch it started on" \
  || no "NEW: read-switch: shim=$RAN rc=$RC on-main=$ONMAIN on-other=$ONOTHER" "the commit must be resolved from the captured branch"

# After such a switch, a bare push would publish the OTHER branch. Nothing is pushed, the marker
# is written, and the message names the branch that holds the commit.
pushswitch(){ # → "rc marker remote_has_mine named marker_after_second_run"
  local r b rc out; r=$(mktemp -d "$TMP/ps.XXXXXX"); b="$r.remote"
  git init -q --bare "$b"; git -C "$r" init -q; git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" remote add origin "$b"
  echo base > "$r/base.txt"; git -C "$r" add base.txt; git -C "$r" commit -qm base
  git -C "$r" push -q -u origin main >/dev/null 2>&1; git -C "$r" branch other; git -C "$r" push -q -u origin other >/dev/null 2>&1
  echo mine > "$r/mine.txt"
  out=$(cd "$r" && INTRUDED="$r/.sw" PATH="$SSHIM:$PATH" "$TMP/new/aios-commit" -m mine -- mine.txt 2>&1); rc=$?
  local first; first="$rc $([ -f "$r/.git/aios-push-pending" ] && echo kept || echo none) $(git -C "$b" cat-file -e main:mine.txt 2>/dev/null && echo yes || echo no) $(printf '%s' "$out" | grep -c 'NOT pushed')"
  # A later run on the checked-out branch pushes it successfully. That says nothing about main,
  # whose commit is still stranded, so the marker must survive it.
  echo more > "$r/more.txt"; (cd "$r" && "$TMP/new/aios-commit" -m more -- more.txt >/dev/null 2>&1)
  echo "$first $([ -f "$r/.git/aios-push-pending" ] && echo kept || echo none)"
}
read -r RC MK REMOTE NAMED MK2 <<<"$(pushswitch)"
{ [ "$RC" = 0 ] && [ "$MK" = kept ] && [ "$REMOTE" = no ] && [ "$NAMED" = 1 ] && [ "$MK2" = kept ]; } \
  && ok "NEW: HEAD switched mid-run → no push of the wrong branch, marker kept (also through a later push of the other branch), the branch holding the commit is named" \
  || no "NEW: push after switch: rc=$RC marker=$MK remote-has-mine=$REMOTE named=$NAMED marker-after-other-push=$MK2" "the marker belongs to the stranded branch, not the checked-out one"

# Detached HEAD attached to a branch mid-run: the branch must not receive the commit.
detached(){ # → "rc other_has_mine"
  local r rc; r=$(mktemp -d "$TMP/dt.XXXXXX")
  git -C "$r" init -q; echo base > "$r/base.txt"; git -C "$r" add base.txt; git -C "$r" commit -qm base
  git -C "$r" branch other; git -C "$r" checkout -q --detach
  echo mine > "$r/mine.txt"
  (cd "$r" && INTRUDED="$r/.sw" PATH="$SSHIM:$PATH" "$TMP/new/aios-commit" --no-push -m mine -- mine.txt >/dev/null 2>&1); rc=$?
  echo "$rc $(git -C "$r" cat-file -e other:mine.txt 2>/dev/null && echo yes || echo no)"
}
read -r RC ONOTHER <<<"$(detached)"
{ [ "$RC" = 0 ] && [ "$ONOTHER" = no ]; } \
  && ok "NEW: detached HEAD attached to a branch mid-run → that branch is left untouched" \
  || no "NEW: detached: rc=$RC other-has-mine=$ONOTHER" "a branch attached meanwhile must never receive the commit"

echo "── 3. the pending-push marker survives while anything is unpushed ──"
# A push shim that pushes one commit short of HEAD and reports success: the shape of an older
# run's push finishing after a newer commit exists.
PSHIM="$TMP/shim-push"; mkdir -p "$PSHIM"
cat > "$PSHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\${1:-}" = push ]; then echo push >> "\$PUSHLOG"; exec "$REAL_GIT" push -q origin 'HEAD~1:refs/heads/main'; fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$PSHIM/git"
marker(){ # $1 old|new · $2 shim dir or "" · $3 setup hook or "" → "marker ahead rc c2 pushes"
  local r b; r=$(mktemp -d "$TMP/mk.XXXXXX"); b="$r.remote"
  git init -q --bare "$b"
  git -C "$r" init -q; git -C "$r" checkout -q -b main 2>/dev/null || git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" remote add origin "$b"
  echo 0 > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c0; git -C "$r" push -q -u origin main >/dev/null 2>&1
  echo 1 > "$r/f"; git -C "$r" commit -qam c1                      # stranded from an earlier run
  date > "$r/.git/aios-push-pending"
  echo 2 > "$r/g"
  [ -n "${3:-}" ] && "$3" "$r"
  local rc; (cd "$r" && PUSHLOG="$r/.pushes" PATH="${2:+$2:}$PATH" "$TMP/$1/aios-commit" -m c2 -- g >/dev/null 2>&1); rc=$?
  echo "$([ -f "$r/.git/aios-push-pending" ] && echo kept || echo gone) $(git -C "$r" rev-list --count '@{u}..HEAD') $rc $(git -C "$r" log -1 --format=%s) $(grep -c push "$r/.pushes" 2>/dev/null || echo 0)"
}
read -r MK AHEAD RC C2 NP <<<"$(marker new "$PSHIM")"
{ [ "$MK" = kept ] && [ "$AHEAD" -ge 1 ] && [ "$RC" = 0 ] && [ "$C2" = c2 ] && [ "$NP" = 2 ]; } \
  && ok "NEW: a push that left $AHEAD commit(s) behind keeps the marker" \
  || no "NEW: marker $MK, $AHEAD unpushed, rc=$RC head=$C2 pushes=$NP" "the marker is the only record of a stranded commit"
read -r MK AHEAD RC C2 NP <<<"$(marker new "")"
{ [ "$MK" = gone ] && [ "$AHEAD" = 0 ] && [ "$RC" = 0 ] && [ "$C2" = c2 ]; } \
  && ok "NEW: a push that took everything clears the marker" \
  || no "NEW: marker $MK after a complete push ($AHEAD ahead)" "a marker that never clears retries forever"
if [ "$HAVE_OLD" = 1 ]; then
  read -r MK AHEAD RC C2 NP <<<"$(marker old "$PSHIM")"
  { [ "$MK" = gone ] && [ "$AHEAD" -ge 1 ] && [ "$RC" = 0 ] && [ "$C2" = c2 ] && [ "$NP" = 2 ]; } \
    && ok "OLD: the marker was cleared with $AHEAD commit(s) still unpushed (the defect, reproduced)" \
    || no "OLD: did not reproduce (marker $MK, $AHEAD ahead)" "check the pin"
fi

# Where `git push` goes can differ from @{u} (a push remote beside a fetch remote). The marker
# must be judged against the push destination: with it up to date, the marker clears even
# though @{u} is behind.
triangular(){ # $1 repo: push to a second remote while the upstream stays on origin
  local b2="$1.push"; git init -q --bare "$b2"; git -C "$1" remote add pushto "$b2"
  git -C "$1" config remote.pushDefault pushto; git -C "$1" config push.default current
  git -C "$1" push -q pushto main >/dev/null 2>&1
}
read -r MK AHEAD RC C2 NP <<<"$(marker new "" triangular)"
{ [ "$MK" = gone ] && [ "$AHEAD" -ge 1 ] && [ "$RC" = 0 ] && [ "$C2" = c2 ]; } \
  && ok "NEW: pushed to a separate push remote → marker cleared, although @{u} is $AHEAD behind" \
  || no "NEW: triangular push: marker $MK, @{u} $AHEAD behind, rc=$RC head=$C2" "judge the marker by where the push went"
# An error while counting is not "nothing to push": the marker stays.
RSHIM="$TMP/shim-revlist"; mkdir -p "$RSHIM"
cat > "$RSHIM/git" <<SHIMEOF
#!/usr/bin/env bash
case "\${1:-} \${2:-}" in "for-each-ref --contains") echo "fatal: simulated" >&2; exit 128 ;; esac
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$RSHIM/git"
read -r MK AHEAD RC C2 NP <<<"$(marker new "$RSHIM")"
{ [ "$MK" = kept ] && [ "$RC" = 0 ] && [ "$C2" = c2 ]; } \
  && ok "NEW: the published-check fails while settling → the marker is kept" \
  || no "NEW: a failed count cleared the marker ($MK, rc=$RC)" "an error must never read as 'nothing left to push'"

# Check-then-remove must be atomic against a commit. A barrier: the shim answers the settle's
# published-check, then -- before the removal -- starts a second aios-commit whose push fails, and waits.
# Under the lock that second commit cannot land until the settle is done, so its marker stays.
BSHIM="$TMP/shim-barrier"; mkdir -p "$BSHIM"
cat > "$BSHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\${1:-}" = push ] && [ -n "\${FAILPUSH:-}" ]; then echo "fatal: unable to access: Could not resolve host" >&2; exit 128; fi
# The FIRST push (the sweep's) fails too, so the marker survives to the end-of-run settle,
# which is the one this barrier is aimed at.
if [ "\${1:-}" = push ] && [ ! -e "\$BARRIER.firstpush" ]; then : > "\$BARRIER.firstpush"; echo "fatal: unable to access: Could not resolve host" >&2; exit 128; fi
if [ "\${1:-} \${2:-}" = "for-each-ref --contains" ] && [ ! -e "\$BARRIER" ]; then
  : > "\$BARRIER"
  out=\$("$REAL_GIT" "\$@") || exit \$?
  # Detached from this command substitution's pipe: otherwise the caller's \$(...) waits for
  # the background commit, which waits for the caller's lock -- a deadlock made by the test.
  ( echo 3 > h; FAILPUSH=1 "\$AC" -m c3 -- h; : > "\$BARRIER.done" ) >/dev/null 2>&1 </dev/null &
  sleep 1.5
  echo "\$out"; exit 0
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$BSHIM/git"
barrier(){ # $1 old|new → "marker c3_unpushed barrier_ran"
  local r b i; r=$(mktemp -d "$TMP/br.XXXXXX"); b="$r.remote"
  git init -q --bare "$b"; git -C "$r" init -q; git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" remote add origin "$b"
  echo 0 > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c0; git -C "$r" push -q -u origin main >/dev/null 2>&1
  echo 1 > "$r/f"; git -C "$r" commit -qam c1; date > "$r/.git/aios-push-pending"   # stranded earlier
  echo 2 > "$r/g"
  (cd "$r" && AC="$TMP/$1/aios-commit" BARRIER="$r/.barrier" PATH="$BSHIM:$PATH" "$TMP/$1/aios-commit" -m c2 -- g >/dev/null 2>&1)
  for i in $(seq 1 100); do [ -e "$r/.barrier.done" ] && break; sleep 0.1; done
  echo "$([ -f "$r/.git/aios-push-pending" ] && echo kept || echo gone) $(git -C "$r" log --format=%s '@{u}..HEAD' | tr '\n' ',') $([ -e "$r/.barrier" ] && echo ran || echo idle)"
}
read -r MK UNPUSHED RAN <<<"$(barrier new)"
{ [ "$RAN" = ran ] && [ "$UNPUSHED" = "c3," ] && [ "$MK" = kept ]; } \
  && ok "NEW: a commit whose push fails during another run's settle keeps its marker" \
  || no "NEW: barrier=$RAN unpushed=[$UNPUSHED] marker=$MK" "check-then-remove must not interleave with a commit"

# The sweep at the top pushes a commit stranded by an earlier run. When this run then has
# nothing of its own to commit, the settle right after the lock is taken is what clears it.
sweep_only(){ # → "marker ahead rc"
  local r b rc; r=$(mktemp -d "$TMP/sw2.XXXXXX"); b="$r.remote"
  git init -q --bare "$b"; git -C "$r" init -q; git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" remote add origin "$b"
  echo 0 > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c0; git -C "$r" push -q -u origin main >/dev/null 2>&1
  echo 1 > "$r/f"; git -C "$r" commit -qam c1; date > "$r/.git/aios-push-pending"
  (cd "$r" && "$TMP/new/aios-commit" -m noop -- f >/dev/null 2>&1); rc=$?
  echo "$([ -f "$r/.git/aios-push-pending" ] && echo kept || echo gone) $(git -C "$r" rev-list --count '@{u}..HEAD') $rc"
}
read -r MK AHEAD RC <<<"$(sweep_only)"
{ [ "$MK" = gone ] && [ "$AHEAD" = 0 ] && [ "$RC" = 0 ]; } \
  && ok "NEW: the sweep pushes a stranded commit and, with nothing else to commit, clears the marker" \
  || no "NEW: after a successful sweep: marker $MK, $AHEAD ahead, rc=$RC" "a marker left after everything is pushed retries forever"

# Two branches stranded one after the other, then only the second is pushed: the first must
# stay recorded. And a stranded branch renamed away: a name that no longer resolves is not
# evidence of publication. Pushes fail through a shim until FAILPUSH is unset.
FSHIM="$TMP/shim-failpush"; mkdir -p "$FSHIM"
cat > "$FSHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [ "\${1:-}" = push ] && [ -e "\$FAILFLAG" ]; then echo "fatal: unable to access: Could not resolve host" >&2; exit 128; fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$FSHIM/git"
twobranch(){ # $1 "rename" or "" → "marker entries main_published"
  local r b; r=$(mktemp -d "$TMP/tb.XXXXXX"); b="$r.remote"
  git init -q --bare "$b"; git -C "$r" init -q; git -C "$r" symbolic-ref HEAD refs/heads/main
  git -C "$r" remote add origin "$b"
  echo 0 > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c0; git -C "$r" push -q -u origin main >/dev/null 2>&1
  git -C "$r" branch other; git -C "$r" push -q -u origin other >/dev/null 2>&1
  : > "$r/.fail"
  echo m > "$r/m"; (cd "$r" && FAILFLAG="$r/.fail" PATH="$FSHIM:$PATH" "$TMP/new/aios-commit" -m on-main -- m >/dev/null 2>&1)
  git -C "$r" checkout -q other
  echo o > "$r/o"; (cd "$r" && FAILFLAG="$r/.fail" PATH="$FSHIM:$PATH" "$TMP/new/aios-commit" -m on-other -- o >/dev/null 2>&1)
  [ "${1:-}" = rename ] && git -C "$r" branch -m main saved
  rm -f "$r/.fail"
  echo p > "$r/p"; (cd "$r" && FAILFLAG="$r/.fail" PATH="$FSHIM:$PATH" "$TMP/new/aios-commit" -m other-again -- p >/dev/null 2>&1)
  echo "$([ -f "$r/.git/aios-push-pending" ] && echo kept || echo gone) $(grep -c '^pending ' "$r/.git/aios-push-pending" 2>/dev/null || echo 0) $(git -C "$b" log --format=%s --all | grep -c on-main)"
}
read -r MK N PUB <<<"$(twobranch)"
{ [ "$MK" = kept ] && [ "$N" = 1 ] && [ "$PUB" = 0 ]; } \
  && ok "NEW: main and other stranded in turn, only other pushed → main's commit is still recorded (1 entry)" \
  || no "NEW: two stranded branches: marker $MK, $N entr(y|ies), main published $PUB" "a second stranded branch must not overwrite the first"
read -r MK N PUB <<<"$(twobranch rename)"
{ [ "$MK" = kept ] && [ "$N" = 1 ]; } \
  && ok "NEW: the stranded branch renamed away, another pushed → its commit is still recorded" \
  || no "NEW: renamed stranded branch: marker $MK, $N entr(y|ies)" "a name that no longer resolves is not evidence of publication"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

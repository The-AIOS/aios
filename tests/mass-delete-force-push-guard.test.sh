#!/usr/bin/env bash
# tests/mass-delete-force-push-guard.test.sh
#
# The mass-deletion ceiling in hooks/aios-commit and the agent push guard in hooks/git/pre-push.
# Drives the REAL scripts in a throwaway repo with a throwaway bare remote: a commit deleting more
# than the limit refuses, and from a Claude session (CLAUDECODE=1) a force push, a remote-branch
# deletion and a push that deletes more than the limit all refuse — each with its explicit escape
# hatch, and a human at a terminal unaffected. bash 3.2-safe.
#
# Run:  bash tests/mass-delete-force-push-guard.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AC="$ROOT/hooks/aios-commit"; HOOK="$ROOT/hooks/git/pre-push"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
expect(){ [ "$1" = "$2" ] && ok "$3" || no "$3 — exit $1, expected $2"; }
T=$(mktemp -d "${TMPDIR:-/tmp}/massdel.XXXXXX"); trap 'rm -rf "$T"' EXIT

git init -q --bare "$T/remote.git"
R="$T/repo"; git init -q "$R"; cd "$R" || exit 1
git symbolic-ref HEAD refs/heads/main
git config user.name t; git config user.email t@example.test; git config commit.gpgsign false
mkdir -p "$T/hooks"; cp "$HOOK" "$T/hooks/pre-push"; chmod +x "$T/hooks/pre-push"
git config core.hooksPath "$T/hooks"
git remote add origin "$T/remote.git"
mkdir -p notes; i=1; while [ $i -le 40 ]; do echo "note $i" > "notes/n$i.md"; i=$((i+1)); done
git add -A && git commit -qm init && git push -q origin main 2>/dev/null
P=""; i=1; while [ $i -le 30 ]; do rm "notes/n$i.md"; P="$P notes/n$i.md"; i=$((i+1)); done

echo "-- aios-commit --"
# shellcheck disable=SC2086
env -u AIOS_ALLOW_MASS_DELETE bash "$AC" --no-push -m "delete 30" $P >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "a commit deleting 30 files refuses" || no "a commit deleting 30 files went through"
[ "$(git rev-list --count HEAD)" = 1 ] && ok "…and nothing was committed" || no "a refused commit still moved HEAD"
# shellcheck disable=SC2086
AIOS_ALLOW_MASS_DELETE=1 bash "$AC" --no-push -m "delete 30 ok" $P >/dev/null 2>&1; expect $? 0 "AIOS_ALLOW_MASS_DELETE=1 lets it through"
rm notes/n31.md; bash "$AC" --no-push -m "delete 1" notes/n31.md >/dev/null 2>&1; expect $? 0 "a small deletion is untouched"

echo "-- pre-push, from a Claude session --"
CLAUDECODE=1 git push -q origin main 2>/dev/null; expect $? 1 "a push deleting 31 files refuses"
CLAUDECODE=1 AIOS_ALLOW_MASS_DELETE=1 git push -q origin main 2>/dev/null; expect $? 0 "…and passes with AIOS_ALLOW_MASS_DELETE=1"
echo x > f.md; git add f.md; git commit -qm f; CLAUDECODE=1 git push -q origin main 2>/dev/null; expect $? 0 "a normal fast-forward passes"
git commit -q --amend -m rewritten
CLAUDECODE=1 git push -q --force origin main 2>/dev/null; expect $? 1 "a force push refuses"
env -u CLAUDECODE git push -q --force origin main 2>/dev/null; expect $? 0 "a human's force push is not blocked"
git push -q origin main:side 2>/dev/null
CLAUDECODE=1 git push -q origin --delete side 2>/dev/null; expect $? 1 "deleting a remote branch refuses"
CLAUDECODE=1 AIOS_ALLOW_FORCE_PUSH=1 git push -q origin --delete side 2>/dev/null; expect $? 0 "…and passes with AIOS_ALLOW_FORCE_PUSH=1"

echo "-- the owner guard still reads the ref list --"
git config aios.blockedRemoteOwners "$(basename "$T")"
echo y > g.md; git add g.md; git commit -qm g
git remote set-url origin "$T/remote.git"
CLAUDECODE=1 git push -q origin main 2>/dev/null; rc=$?
git config --unset aios.blockedRemoteOwners
[ "$rc" = 1 ] && ok "a blocked owner is still refused after the agent guard read stdin" || no "the owner guard stopped working (exit $rc)"

echo; echo "-- $PASS passed, $FAIL failed --"; [ "$FAIL" -eq 0 ]

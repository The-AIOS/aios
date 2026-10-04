#!/usr/bin/env bash
# tests/mass-delete-force-push-guard.test.sh
#
# Deletions are ANNOUNCED, never blocked (hooks/aios-commit and hooks/git/pre-push), and from a
# Claude session (CLAUDECODE=1) a force push or a remote-branch deletion STOPS and asks the
# operator, passing with AIOS_ALLOW_FORCE_PUSH=1 once they said yes. A human at a terminal is
# unaffected. Drives the REAL scripts in a throwaway repo with a throwaway bare remote. bash 3.2-safe.
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

echo "-- aios-commit: a deletion is announced, never refused --"
# shellcheck disable=SC2086
out=$(bash "$AC" --no-push -m "delete 30" $P 2>&1); rc=$?
expect $rc 0 "a commit deleting 30 files goes through (git is the undo)"
[ "$(git rev-list --count HEAD)" = 2 ] && ok "…and is committed" || no "the deletion commit did not land"
case "$out" in *"DELETES 30 file(s)"*"undo: git revert"*) ok "…and says how many, with the undo" ;; *) no "no deletion announcement — $out" ;; esac
echo z > notes/n40.md; out=$(bash "$AC" --no-push -m "edit" notes/n40.md 2>&1)
case "$out" in *DELETES*) no "an edit was announced as a deletion" ;; *) ok "a commit with no deletion says nothing about deletions" ;; esac

echo "-- pre-push, from a Claude session --"
out=$(CLAUDECODE=1 git push origin main 2>&1); rc=$?
expect $rc 0 "an agent's push carrying 30 deletions is not refused"
case "$out" in *"DELETES 30 file(s)"*) ok "…and it is announced" ;; *) no "push deletions not announced — $out" ;; esac
echo x > f.md; git add f.md; git commit -qm f; CLAUDECODE=1 git push -q origin main 2>/dev/null; expect $? 0 "a normal fast-forward passes"
git commit -q --amend -m rewritten
out=$(CLAUDECODE=1 git push --force origin main 2>&1); rc=$?
expect $rc 1 "an agent's force push stops"
case "$out" in *"Ask the operator first"*) ok "…and tells it to ask the operator" ;; *) no "no ask-the-operator message — $out" ;; esac
CLAUDECODE=1 AIOS_ALLOW_FORCE_PUSH=1 git push -q --force origin main 2>/dev/null; expect $? 0 "…and passes with the operator's yes (AIOS_ALLOW_FORCE_PUSH=1)"
git commit -q --amend -m rewritten-again
env -u CLAUDECODE git push -q --force origin main 2>/dev/null; expect $? 0 "a human's force push is not stopped"
git push -q origin main:side 2>/dev/null
CLAUDECODE=1 git push -q origin --delete side 2>/dev/null; expect $? 1 "an agent deleting a remote branch stops"
CLAUDECODE=1 AIOS_ALLOW_FORCE_PUSH=1 git push -q origin --delete side 2>/dev/null; expect $? 0 "…and passes with AIOS_ALLOW_FORCE_PUSH=1"

echo "-- the owner guard still reads the ref list --"
git config aios.blockedRemoteOwners "$(basename "$T")"
echo y > g.md; git add g.md; git commit -qm g
git remote set-url origin "$T/remote.git"
CLAUDECODE=1 git push -q origin main 2>/dev/null; rc=$?
git config --unset aios.blockedRemoteOwners
[ "$rc" = 1 ] && ok "a blocked owner is still refused after the agent guard read stdin" || no "the owner guard stopped working (exit $rc)"

echo; echo "-- $PASS passed, $FAIL failed --"; [ "$FAIL" -eq 0 ]

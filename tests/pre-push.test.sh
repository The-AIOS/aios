#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pre-push must refuse a push to an owner the operator declared off-limits —
# and must be INERT until the operator declares one.
#
# The push is the one place the destination is unambiguous, so this is the guard
# that does not depend on a command-line pattern matching. Every case below runs
# the hook directly with (remote-name, url) the way git invokes it, against a
# scratch global gitconfig so the machine's real list is never read or touched.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
H=hooks/git/pre-push
[ -x "$H" ] || { echo "::error::$H missing or not executable"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Isolate git's GLOBAL config by relocating HOME (and XDG) for every hook run. Do not use
# GIT_CONFIG_GLOBAL for this: git < 2.32 ignores it, and on such a git a `--global` write
# from this test lands in the developer's real ~/.gitconfig — measured once, and it
# silently replaced a real blocked-owner list with this file's fixture. HOME works on
# every git that exists.
export HOME="$T" XDG_CONFIG_HOME="$T/xdg"; mkdir -p "$XDG_CONFIG_HOME"
unset GIT_CONFIG_GLOBAL

run(){ "$H" origin "$1" >/dev/null 2>&1; echo $?; }

echo "── inert until configured (a fresh clone must never be blocked by someone else's list) ──"
[ "$(run https://github.com/AcmeCorp/x.git)" = "0" ] && ok "no list → exit 0" || no "blocked with no list configured" "a stranger's clone would be unable to push anywhere"

printf '[aios]\n\tblockedRemoteOwners = AcmeCorp anotherorg\n' > "$HOME/.gitconfig"   # fixture, in the scratch HOME only

echo "── blocked owners, both URL shapes, case-insensitive ──"
[ "$(run https://github.com/AcmeCorp/repo.git)" = "1" ] && ok "https URL to a blocked owner → exit 1" || no "https URL to blocked owner passed"
[ "$(run git@github.com:anotherorg/repo.git)" = "1" ]  && ok "ssh URL to a blocked owner → exit 1"   || no "ssh URL to blocked owner passed"
[ "$(run https://github.com/ACMECORP/repo.git)" = "1" ] && ok "owner match is case-insensitive"     || no "ACMECORP (uppercase) passed" "the segment compare must lowercase both sides"

echo "── allowed owners, including one that merely CONTAINS a blocked name ──"
[ "$(run https://github.com/someone/aios.git)" = "0" ]        && ok "unrelated owner → exit 0"          || no "unrelated owner blocked"
[ "$(run git@github.com:someone/karma.git)" = "0" ]           && ok "unrelated ssh owner → exit 0"      || no "unrelated ssh owner blocked"
[ "$(run https://github.com/AcmeCorpOSS/x.git)" = "0" ]       && ok "AcmeCorpOSS is not AcmeCorp (whole-segment match)" || no "prefix match leaked: AcmeCorpOSS blocked"

echo "── the escape hatch is explicit and loud ──"
out=$(AIOS_ALLOW_BLOCKED_REMOTE=1 "$H" origin https://github.com/AcmeCorp/x.git 2>&1); rc=$?
[ "$rc" = "0" ] && ok "AIOS_ALLOW_BLOCKED_REMOTE=1 → exit 0" || no "escape hatch did not allow the push"
case "$out" in *"AIOS_ALLOW_BLOCKED_REMOTE=1"*) ok "the override announces itself on stderr" ;; *) no "override was silent" "a silent bypass is the thing this hook exists to prevent" ;; esac

echo "── the refusal says what to do ──"
out=$("$H" origin https://github.com/AcmeCorp/x.git 2>&1)
case "$out" in *"aios.blockedRemoteOwners"*) ok "refusal names the config key" ;; *) no "refusal does not say how to change the list" ;; esac
case "$out" in *"AcmeCorp"*) ok "refusal names the owner it matched" ;; *) no "refusal does not name the owner" ;; esac

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]

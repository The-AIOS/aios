#!/usr/bin/env bash
# test-identity-cycle.sh — exercise claude-identity.sh end to end against a
# FABRICATED CLAUDE_CONFIG_DIR. Never touches the operator's real credentials.
#
# WHY THIS EXISTS
# ---------------
# The identity manager swaps live Anthropic credentials, so the obvious way to
# test it — run it — is exactly the way you must not. Before this script the only
# validation path was `claude-switch` on a real account, which is why the tool
# shipped claiming "Windows uses the same file layout as Linux" while three
# separate defects made every subcommand fail there: `python3` resolving to the
# Microsoft Store stub, POSIX paths handed to a native Windows interpreter, and
# `grep -c` returning 1 under `set -e`. All three are caught by the run below in
# about two seconds, on any platform.
#
# Run it after touching claude-identity.sh, and on any new platform before
# trusting the tool with real credentials.
#
# Usage:  bash hooks/claude-identity/test-identity-cycle.sh
# Exit:   0 = all assertions passed · 1 = at least one failed (details above)

set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SELF_DIR/claude-identity.sh"
[ -f "$SCRIPT" ] || { echo "claude-identity.sh not found beside this test"; exit 1; }

FIX="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/aios-identity-fixture.$$")"
# ── HARD SAFETY GATE — do not weaken, do not remove ──────────────────────────
# CLAUDE_CONFIG_DIR scopes the FILES. It does NOT scope the macOS Keychain, which is
# machine-global. So on Darwin this suite writes through to the operator's REAL
# credential unless the service name is overridden — and section 7 deliberately writes
# a MALFORMED blob. That is not theoretical: on 2026-08-14 running this suite on macOS
# replaced a live credential with the literal string `not json at all`, and it was
# recovered only because a captured identity happened to exist.
#
# So: point the tool at a throwaway service, then REFUSE TO RUN unless the override is
# actually in effect. A test that merely *claims* isolation is the thing that caused the
# incident; this asserts it.
export AIOS_KEYCHAIN_SERVICE="aios-identity-test-$$"
if ! grep -q 'AIOS_KEYCHAIN_SERVICE' "$SCRIPT"; then
  echo "REFUSING TO RUN: $SCRIPT has no AIOS_KEYCHAIN_SERVICE override." >&2
  echo "On macOS this suite would write to the operator's REAL Keychain credential." >&2
  echo "Update the script (or run this suite only on a file-backend platform)." >&2
  exit 2
fi
case "$(uname -s)" in
  Darwin)
    # Prove the throwaway service is empty before we start, and clean it up after —
    # never touch the default service, never leave a stray keychain item behind.
    security delete-generic-password -s "$AIOS_KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
    ;;
esac


cleanup() {
  rm -rf "$FIX"
  # Remove the throwaway keychain item too. Folded into the ONE cleanup function on
  # purpose: a second `trap ... EXIT` silently REPLACES the first, so adding a separate
  # trap for this would have leaked the item on every run.
  [ -n "${AIOS_KEYCHAIN_SERVICE:-}" ] && \
    security delete-generic-password -s "$AIOS_KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$FIX/cfg"
A="alice@example.com"
B="bob@example.com"

cat > "$FIX/USER.md" <<EOF
# USER.md (fixture)

## Anthropic accounts

1. \`$A\` — primary
2. \`$B\` — overflow

## Another section
ignored by the parser
EOF

# A believable .claude.json: the two keys the tool swaps, plus two it must NOT touch.
mkcfg() {
  cat > "$FIX/cfg/.claude.json" <<EOF
{
  "userID": "uid-$1",
  "oauthAccount": { "emailAddress": "$1", "accountUuid": "uuid-$1" },
  "mcpServers": { "obsidian": { "command": "npx" } },
  "projects": { "keep": "me" }
}
EOF
  local blob
  blob=$(printf '{"claudeAiOauth":{"accessToken":"tok-%s","refreshToken":"ref-%s"}}' "$1" "$1")
  printf '%s' "$blob" > "$FIX/cfg/.credentials.json"
  # Seed the backend the PLATFORM actually uses, not just the file. CLAUDE_CONFIG_DIR
  # scopes the file; on Darwin the tool reads the KEYCHAIN, so a file-only fixture left
  # every read falling through to whatever the machine happened to hold. That is why this
  # suite reported 25/25 on a file backend and only 22/25 on macOS — and the three that
  # "passed" there passed by reading the operator's REAL credential, not the fixture.
  case "$(uname -s)" in
    Darwin) security add-generic-password -U -s "$AIOS_KEYCHAIN_SERVICE" -a "$USER" \
              -w "$blob" >/dev/null 2>&1 ;;
  esac
}

run() { CLAUDE_CONFIG_DIR="$FIX/cfg" USER_MD_PATH="$FIX/USER.md" bash "$SCRIPT" "$@"; }

# Read the LIVE credential from whichever backend this platform uses. Asserting against
# "$FIX/cfg/.credentials.json" directly is only correct on a file backend: on Darwin the
# tool writes to the Keychain, so the file keeps whatever the fixture last put there —
# which made one assertion fail and two others PASS for the wrong reason (they matched a
# stale file rather than the credential the tool had actually written).
cred_now() {
  case "$(uname -s)" in
    Darwin) security find-generic-password -s "$AIOS_KEYCHAIN_SERVICE" -w 2>/dev/null ;;
    *)      cat "$FIX/cfg/.credentials.json" 2>/dev/null ;;
  esac
}

pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }
exp_exit()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi; }
has()       { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 -- '$2' not in: $(printf '%s' "$3" | tr '\n' ' ' | cut -c1-140)" ;; esac; }

echo "== 1. whoami, account A active =="
mkcfg "$A"
out=$(run whoami 2>&1); rc=$?
exp_exit "whoami exits 0" 0 $rc
has "whoami reports A" "$A" "$out"
has "whoami names B as next" "$B" "$out"

echo "== 2. whoami with the account NOT listed in USER.md =="
# Regression guard: `grep -c .` exits 1 on zero matches, and under `set -e` that
# aborted the function before its own "not listed in USER.md" branch could print.
mkcfg "carol@example.com"
out=$(run whoami 2>&1); rc=$?
exp_exit "unlisted account still exits 0" 0 $rc
has "explains it is unlisted" "not listed in USER.md" "$out"

echo "== 3. list =="
mkcfg "$A"
out=$(run list 2>&1); rc=$?
exp_exit "list exits 0" 0 $rc
has "list shows A" "$A" "$out"

echo "== 4. capture A, then B =="
out=$(run switch --capture 2>&1); rc=$?
exp_exit "capture A exits 0" 0 $rc
[ -f "$FIX/cfg/identities/$A/keychain.json" ] && ok "A credential blob written" || bad "A credential blob missing"
[ -f "$FIX/cfg/identities/$A/oauthAccount.json" ] && ok "A oauthAccount written" || bad "A oauthAccount missing"
has "A userID correct" "uid-$A" "$(cat "$FIX/cfg/identities/$A/userID.txt" 2>/dev/null)"
mkcfg "$B"
out=$(run switch --capture 2>&1); rc=$?
exp_exit "capture B exits 0" 0 $rc
has "B userID correct" "uid-$B" "$(cat "$FIX/cfg/identities/$B/userID.txt" 2>/dev/null)"

echo "== 5. explicit switch B -> A =="
out=$(run switch "$A" 2>&1); rc=$?
exp_exit "switch to A exits 0" 0 $rc
has "credential restored" "tok-$A" "$(cred_now)"
has "oauthAccount restored" "$A" "$(cat "$FIX/cfg/.claude.json")"
has "userID restored" "uid-$A" "$(cat "$FIX/cfg/.claude.json")"
has "mcpServers untouched" "obsidian" "$(cat "$FIX/cfg/.claude.json")"
has "projects untouched" "keep" "$(cat "$FIX/cfg/.claude.json")"
[ -f "$FIX/cfg/.claude.json.bak-claude-switch" ] && ok "backup written" || bad "backup missing"

echo "== 6. bare switch rotates A -> B =="
out=$(run switch 2>&1); rc=$?
exp_exit "rotation exits 0" 0 $rc
has "landed on B" "tok-$B" "$(cred_now)"

echo "== 7. malformed blob must be REFUSED, leaving the live credential alone =="
printf 'not json at all' > "$FIX/cfg/identities/$A/keychain.json"
out=$(run switch "$A" 2>&1); rc=$?
exp_exit "switch fails closed" 1 $rc
has "says why" "malformed" "$out"
has "live credential intact" "tok-$B" "$(cred_now)"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

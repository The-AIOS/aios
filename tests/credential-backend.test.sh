#!/usr/bin/env bash
# credential-backend.test.sh — the platform-detected credential store.
#
# macOS keeps the OAuth blob in Keychain; Linux and Windows keep the SAME blob as
# a plaintext JSON file at $CONFIG_DIR/.credentials.json, mode 600. That is
# Claude Code's own layout, not a choice made here — which is why the Linux
# equivalent is a plain file and not libsecret/secret-tool: a keyring would be
# storing the credential somewhere the application never looks.
#
# Two properties below are load-bearing and neither is obvious from reading:
#
#   * The write must VALIDATE before replacing. On this path a bad blob
#     overwrites a working credential, and the operator meets the failure as a
#     logged-out session rather than as an error from this tool.
#   * The write must be ATOMIC VIA RENAME. The mtime bump is the signal a live
#     session rides to pick the new credential up on its next API request; a
#     truncate-and-write risks a torn read and can leave mtime unchanged.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/hooks/claude-identity/claude-identity.sh"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cb-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Extract the backend block only. Sourcing the whole script would run its
# dispatch; these are pure functions and are exercised as such.
sed -n '/^# ---- credential backend/,/^# ---- parse USER.md/p' "$SRC" \
  | sed '$d' > "$WORK/backend.sh"

harness() {  # harness <body>
  CONFIG_DIR="$WORK" bash -c '
    set -uo pipefail
    RED=""; RESET=""
    die() { echo "error: $*" >&2; exit 1; }
    KEYCHAIN_SERVICE="Claude Code-credentials"
    CONFIG_DIR="'"$WORK"'"
    . "'"$WORK"'/backend.sh"
    '"$1"'
  '
}

echo "credential-backend: $SRC"

# 1. The block is extractable and self-contained — if this breaks, everything
#    below is measuring the harness rather than the code.
if [ -s "$WORK/backend.sh" ] && grep -q 'cred_write()' "$WORK/backend.sh"; then
  ok "backend block extracts cleanly"
else
  no "backend block extracts cleanly" "got $(wc -l < "$WORK/backend.sh") lines"; fi

# 2. Non-Darwin selects the file backend. (uname is the real one here; on a mac
#    runner this asserts keychain instead, which is equally correct.)
out="$(harness 'echo "$CRED_BACKEND"')"
expected="file"; [ "$(uname -s)" = "Darwin" ] && expected="keychain"
if [ "$out" = "$expected" ]; then
  ok "platform detection selects '$expected' on $(uname -s)"
else
  no "platform detection selects '$expected' on $(uname -s)" "got: $out"; fi

# The remaining cases exercise the file path. On macOS they would need a real
# Keychain, so skip rather than assert something untrue.
if [ "$expected" = "keychain" ]; then
  echo "  skip remaining (file-backend cases) — this runner is macOS"
  printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; exit $?
fi

# 3. Round-trip: what goes in comes back out byte for byte.
blob='{"claudeAiOauth":{"accessToken":"tok-abc","refreshToken":"ref-xyz"}}'
harness 'cred_write '"'"''"$blob"''"'"'' >/dev/null 2>&1
out="$(harness 'cred_read')"
if [ "$out" = "$blob" ]; then ok "write then read round-trips exactly"; else
  no "write then read round-trips exactly" "got: $out"; fi

# 4. The stored file is 0600 — it is a bearer credential in plaintext.
mode="$(stat -c '%a' "$WORK/.credentials.json" 2>/dev/null || stat -f '%Lp' "$WORK/.credentials.json")"
if [ "$mode" = "600" ]; then ok "credential file is mode 600"; else
  no "credential file is mode 600" "got: $mode"; fi

# 5. THE ONE THAT MATTERS: malformed input must not replace a working credential.
harness 'cred_write "not json at all"' >/dev/null 2>&1
out="$(harness 'cred_read')"
if [ "$out" = "$blob" ]; then
  ok "a malformed blob is refused and the good credential survives"
else
  no "a malformed blob is refused and the good credential survives" \
     "credential is now: $out"; fi

# 6. ...and it fails loudly rather than returning success.
if ! harness 'cred_write "not json at all"' >/dev/null 2>&1; then
  ok "refusing a malformed blob is a non-zero exit"
else
  no "refusing a malformed blob is a non-zero exit" "it reported success"; fi

# 7. No temp file is left behind on the rejected path.
if [ -z "$(find "$WORK" -maxdepth 1 -name '.credentials.json.tmp.*' 2>/dev/null)" ]; then
  ok "no temp file left behind after a refused write"
else
  no "no temp file left behind after a refused write" "$(ls -a "$WORK")"; fi

# 8. mtime advances on write — this is what a live session watches for. Without
#    it the rotation completes and the running session never notices.
before="$(stat -c '%Y' "$WORK/.credentials.json" 2>/dev/null || stat -f '%m' "$WORK/.credentials.json")"
sleep 1.1
harness 'cred_write '"'"'{"claudeAiOauth":{"accessToken":"tok-second"}}'"'"'' >/dev/null 2>&1
after="$(stat -c '%Y' "$WORK/.credentials.json" 2>/dev/null || stat -f '%m' "$WORK/.credentials.json")"
if [ "$after" -gt "$before" ]; then
  ok "a successful write advances mtime (the live-adoption signal)"
else
  no "a successful write advances mtime (the live-adoption signal)" \
     "before=$before after=$after"; fi

# 9. A missing store reads as failure, not as an empty credential.
rm -f "$WORK/.credentials.json"
if ! harness 'cred_read' >/dev/null 2>&1; then
  ok "a missing credential store fails rather than returning empty"
else
  no "a missing credential store fails rather than returning empty" \
     "an empty read would be captured as a valid identity"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

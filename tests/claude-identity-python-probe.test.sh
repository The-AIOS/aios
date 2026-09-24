#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The account watcher finds a real Python under launchd's bare PATH
#
# WHY
# launchd starts the watcher's safety net with PATH=/usr/bin:/bin:/usr/sbin:/sbin,
# so `python3` resolves to /usr/bin/python3 -- on macOS the Command Line Tools
# stub, which fails while the tools are missing or mid-update. The probe only
# tried bare names, so every tick died with "no working Python" while Homebrew's
# interpreter sat in /opt/homebrew/bin. Appending that dir to PATH would not
# help: the broken stub still resolves first. The probe must try absolute paths.
#
# A broken python3/python is put FIRST on PATH, then the rest of the usual PATH.
# Pre-fix: dies at the probe. Fixed: gets past it (any later message is fine).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo "SKIP: launchd/POSIX PATH case" >&2; exit 0 ;; esac
HAVE=""; for p in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$HOME/.local/bin/python3"; do
  if "$p" -c 'import sys' >/dev/null 2>&1; then HAVE="$p"; break; fi; done
[ -n "$HAVE" ] || { echo "SKIP: no interpreter at a fallback location on this machine" >&2; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for n in python3 python; do printf '#!/bin/sh\necho stub >&2\nexit 1\n' > "$T/$n"; chmod +x "$T/$n"; done
S=hooks/claude-identity/claude-identity.sh

out="$(env -i HOME="$T" PATH="$T:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$S" whoami 2>&1)"
if printf '%s' "$out" | grep -c 'no working Python' >/dev/null; then
  no "the probe gave up with $HAVE available" "$(printf '%s' "$out" | head -1)"
else
  ok "broken stub first on PATH → the probe falls through to $HAVE"
fi
# control: with no fallback reachable the probe must still fail loudly, not guess
sed 's#/opt/homebrew/bin/python3 /usr/local/bin/python3 "$HOME/.local/bin/python3"##' "$S" > "$T/ci.sh"
grep -c '/opt/homebrew/bin/python3' "$T/ci.sh" >/dev/null && no "control: could not strip the fallback candidates" "the sed pattern no longer matches the probe line"
out="$(env -i HOME="$T" PATH="$T:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$T/ci.sh" whoami 2>&1)"
printf '%s' "$out" | grep -c 'no working Python' >/dev/null && ok "control: without the fallback candidates the same setup dies at the probe" \
  || no "control: the stub setup did not reproduce the failure" "the pass above would prove nothing"

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

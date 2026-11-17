#!/usr/bin/env bash
# tests/clip.test.sh
#
# hooks/media/clip puts paste-bound text on the clipboard intact and proves it. Run against STUB clipboard
# tools (never the real clipboard: a test must not eat what the operator copied), where the stub
# pbcopy models the measured macOS bug -- it decodes stdin as UTF-8 only under a UTF-8 locale and as
# Mac Roman otherwise. A positive control shows the stub really mangles a bare locale-less pbcopy, so
# a pass means clip forced the locale, not that the stub was lenient.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIP="$ROOT/hooks/media/clip"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# The locale is read in sh BEFORE python starts: Python coerces a missing C locale to UTF-8 and
# writes LC_CTYPE into its own environment (PEP 538), which would hide the very bug modelled here.
cat > "$T/bin/pbcopy" <<'EOF'
#!/bin/sh
STUB_LOC="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" exec python3 -c '
import os, sys
loc = os.environ.get("STUB_LOC", "")
enc = "utf-8" if "UTF-8" in loc.upper().replace("UTF8", "UTF-8") else "mac_roman"
data = sys.stdin.buffer.read().decode(enc, errors="replace")
open(os.environ["STUB_BOARD"], "w", encoding="utf-8").write(data)
'
EOF
cat > "$T/bin/pbpaste" <<'EOF'
#!/usr/bin/env python3
import os, sys
if os.environ.get("STUB_PASTE_LIES"):
    sys.stdout.write("something else"); sys.exit(0)
sys.stdout.buffer.write(open(os.environ["STUB_BOARD"], encoding="utf-8").read().encode("utf-8"))
EOF
chmod +x "$T/bin/pbcopy" "$T/bin/pbpaste"
export STUB_BOARD="$T/board"
TEXT='a→b—c á ñ ü'

echo "── positive control: the stub reproduces the bug ──"
printf '%s' "$TEXT" | env -i PATH="$T/bin:/usr/bin:/bin" STUB_BOARD="$STUB_BOARD" pbcopy
[ "$(cat "$STUB_BOARD")" != "$TEXT" ] && ok "a bare pbcopy with no locale mangles it ($(cat "$STUB_BOARD"))" || no "the stub did not mangle -- the test below would prove nothing"

echo "── clip forces UTF-8 and verifies ──"
printf '%s' "$TEXT" | env -i PATH="$T/bin:/usr/bin:/bin" STUB_BOARD="$STUB_BOARD" CLIP_PLATFORM=darwin bash "$CLIP"; rc=$?
[ "$rc" = 0 ] && ok "clip exits 0 with no locale in its environment" || no "clip exit $rc"
[ "$(cat "$STUB_BOARD")" = "$TEXT" ] && ok "the clipboard holds the text intact" || no "clipboard holds: $(cat "$STUB_BOARD")"
printf '%s\n' "$TEXT" > "$T/in.txt"
env -i PATH="$T/bin:/usr/bin:/bin" STUB_BOARD="$STUB_BOARD" CLIP_PLATFORM=darwin bash "$CLIP" "$T/in.txt" && ok "clip FILE works (trailing newline tolerated)" || no "clip FILE failed"

echo "── a read-back that differs is refused, not claimed ──"
printf '%s' "$TEXT" | env -i PATH="$T/bin:/usr/bin:/bin" STUB_BOARD="$STUB_BOARD" STUB_PASTE_LIES=1 CLIP_PLATFORM=darwin bash "$CLIP" 2>/dev/null; rc=$?
[ "$rc" = 3 ] && ok "mismatch exits 3" || no "mismatch exit $rc (expected 3)"
printf '%s' "$TEXT" | env -i PATH="$T/bin:/usr/bin:/bin" STUB_BOARD="$STUB_BOARD" STUB_PASTE_LIES=1 CLIP_PLATFORM=darwin bash "$CLIP" --no-verify; rc=$?
[ "$rc" = 0 ] && ok "--no-verify skips the read-back" || no "--no-verify exit $rc"

echo "── no clipboard is a distinct, non-zero answer ──"
printf 'x' | env -i PATH="$T/bin:/usr/bin:/bin" CLIP_PLATFORM=linux bash "$CLIP" 2>/dev/null; rc=$?
[ "$rc" = 2 ] && ok "headless Linux exits 2" || no "headless exit $rc (expected 2)"

echo "── wired where it must be ──"
grep -q 'hooks/media/clip' "$ROOT/CLAUDE.md" && ok "CLAUDE.md names hooks/media/clip" || no "CLAUDE.md has no clipboard rule"
if grep -nE '\| *pbcopy|pbpaste' "$ROOT/hooks/claude-identity/install-wrappers.sh" | grep -vE '^[0-9]+: *#' | grep -v 'LC_ALL=' | grep -v 'hooks/media/clip' | grep -q .; then
  no "install-wrappers.sh still has a pbcopy/pbpaste with no forced locale" "$(grep -nE '\| *pbcopy|pbpaste' "$ROOT/hooks/claude-identity/install-wrappers.sh")"
else
  ok "install-wrappers.sh routes every clipboard call through clip or a forced UTF-8 locale"
fi

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]

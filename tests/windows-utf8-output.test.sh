#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Hooks that print text read from files survive a Windows console
#
# WHY
# On Windows, Python's stdout uses the console codepage (cp1252). A vault is full
# of "→", "—" and accents, so the context floor raised UnicodeEncodeError on the
# first heading that carried one and emitted NOTHING — a third route to the silent
# floor (#172, reported from Windows 11 with a Spanish locale). The hook's own
# source is pure ASCII, so the stdout lint could not see it.
#
# PYTHONIOENCODING=cp1252 reproduces that console on any machine, so this runs the
# real floor against a fixture vault with non-ASCII headings under it: the pre-fix
# floor exits 1 with UnicodeEncodeError and prints no heading; the fixed floor
# prints them. tests/lint-windows-stdout.py covers the rest of the class statically.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
PYBIN=""; for _c in python3 python "py -3"; do if $_c -c 'import sys' >/dev/null 2>&1; then PYBIN="$_c"; break; fi; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python" >&2; exit 0; }
V="$(mktemp -d)"; trap 'rm -rf "$V"' EXIT
C="$V/vault/00 - notes/context"
mkdir -p "$C/declared" "$C/observed" "$C/ventures"
printf '# Declared → índice\n' > "$C/declared/_index.md"
printf '# About — café\n## Qué → sí\n' > "$C/declared/about_me.md"
printf '# Observed\n' > "$C/observed/_index.md"
printf -- '---\nupdated: "2026-09-20"\n---\n# Patterns → ñ\n### entry — sí (2026-09-20)\nbody\n' > "$C/observed/patterns.md"
printf '# Intent\n' > "$V/INTENT.md"

out="$(cd "$V" && HOME="$V" PYTHONIOENCODING=cp1252 $PYBIN "$OLDPWD/hooks/context-floor.py" "$V" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'Patterns'; then
  ok "context-floor prints non-ASCII headings under a cp1252 console (exit 0)"
else
  no "context-floor did not survive a cp1252 console" "exit $rc — $(printf '%s' "$out" | grep -m1 -oE 'UnicodeEncodeError[^\n]{0,80}' || printf '%s' "$out" | tail -1)"
fi
printf '%s' "$out" | grep -q 'UnicodeEncodeError' && no "the floor raised UnicodeEncodeError" "" || ok "no UnicodeEncodeError anywhere in the output"

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

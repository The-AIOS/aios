#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# markitdown-convert.py: an empty conversion is a failure, never a success
#
# WHY THIS EXISTS
# MarkItDown returns no text for a scanned, image-only PDF. The script used to
# write an empty file, print "Converted: …" and exit 0, so /aios:ingest went on
# to ingest nothing while looking successful. (#283)
#
# WHAT IT HOLDS
#   * empty or whitespace-only text → non-zero exit, a reason on stderr, and NO
#     output file written
#   * real text → written and reported exactly as before
# A stub `markitdown` module stands in for the real one, so this runs anywhere.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub/markitdown"
cat > "$T/stub/markitdown/__init__.py" <<'PY'
import os
class _R:
    def __init__(self, t): self.text_content = t
class MarkItDown:
    def convert(self, path): return _R(os.environ.get("STUB_TEXT", ""))
PY
printf 'x' > "$T/in.pdf"
conv(){ PYTHONPATH="$T/stub" STUB_TEXT="$1" $PYBIN hooks/markitdown-convert.py "$T/in.pdf" "$T/out.md" >"$T/stdout" 2>"$T/stderr"; }

rm -f "$T/out.md"; conv ""; rc=$?
[ "$rc" -ne 0 ] && ok "an empty conversion exits non-zero" || no "an empty conversion exits 0" "$(cat "$T/stdout")"
[ ! -e "$T/out.md" ] && ok "and writes no output file" || no "an empty output file was written"
grep -i 'no text' "$T/stderr" >/dev/null && ok "and says why on stderr" || no "no reason on stderr" "$(cat "$T/stderr")"
grep 'Converted:' "$T/stdout" >/dev/null && no "it still prints 'Converted:'" || ok "and does not print 'Converted:'"

printf 'the PREVIOUS source\n' > "$T/out.md"; conv ""; rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$T/out.md" ] && ok "a stale file from an earlier run at the same path is removed, not left to be read" \
  || no "the previous run's output survives an empty conversion" "$(cat "$T/out.md" 2>/dev/null)"

rm -f "$T/out.md"; conv "$(printf '  \n\t\n')"; rc=$?
[ "$rc" -ne 0 ] && [ ! -e "$T/out.md" ] && ok "whitespace only counts as empty" || no "whitespace-only text was accepted"

rm -f "$T/out.md"; conv "# Title
Real text."; rc=$?
[ "$rc" -eq 0 ] && grep -q 'Real text' "$T/out.md" && grep 'Converted:' "$T/stdout" >/dev/null \
  && ok "real text is written and reported as before" || no "a real conversion broke" "rc=$rc $(cat "$T/stderr")"

PYTHONPATH="$T/stub" STUB_TEXT="" $PYBIN hooks/markitdown-convert.py "$T/in.pdf" >"$T/stdout" 2>"$T/stderr"; rc=$?
[ "$rc" -ne 0 ] && ok "to stdout, an empty conversion also exits non-zero" || no "stdout mode: an empty conversion exits 0"

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

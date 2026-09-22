#!/usr/bin/env bash
# tests/update-windows-probes.test.sh
#
# Guards two probes that answered a question ADJACENT to the one being asked, and
# so reported a confident wrong result on Windows only.
#
# WHY THIS EXISTS
# ---------------
# #141 established the class: `ls` was asked "what are these directories called"
# and answered with the caller's classify flags applied. The fix was not "avoid
# ls" — it was *assert the outcome, never the code*. Two more instances survived
# that sweep, both on the same platform, both silent:
#
#   1. `command -v python3` was used as "is python3 usable". On Windows it is
#      not: the Microsoft Store installs an App Execution Alias at exactly that
#      name. It is a real file on PATH, so every existence probe succeeds — and
#      running it exits 49, printing an install notice and no stdout. So
#      connect.sh passed its own precondition and then read empty JSON forever,
#      and update.md's cache-parity check (whose stderr is sent to /dev/null)
#      silently produced an EMPTY manifest and compared every cached version
#      against "", reporting a mismatch on every Windows sync.
#
#   2. `diff -rq` was used for a CONTENT verdict without CRLF normalization,
#      although § Backup-on-divergence states as an invariant that every content
#      comparison in the command strips \r first. The hash helpers honour it;
#      the four diff sites never did. With core.autocrlf the vault is CRLF and
#      the clone is LF, so the reconcile reported the whole framework as drift —
#      267 lines on a live vault, 266 of them false, and Step 6.5 says to apply
#      each one like a Tier-1 file.
#
# SHAPE: this does not grep for reassuring strings alone. It REPRODUCES both
# conditions and requires the OLD form to fail under them — so a version of this
# file that could never fail would itself fail its own control assertions.
#
# Run:  bash tests/update-windows-probes.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
U="$REPO/plugins/aios/commands/update.md"
C="$REPO/mcps/google-workspace-mcp/connect.sh"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== update-windows-probes =="

# ---------------------------------------------------------------------------
# 1. CONTROL — reproduce the Store stub, and prove the OLD guard passes on it.
#    If this ever stops holding, the rest of section 2 is vacuous and must fail
#    loudly rather than quietly pass.
# ---------------------------------------------------------------------------
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/python3" <<'STUBEOF'
#!/usr/bin/env bash
echo "Python was not found; run without arguments to install from the Microsoft Store" >&2
exit 49
STUBEOF
cat > "$STUB/python" <<'REALEOF'
#!/usr/bin/env bash
[ "${1:-}" = "-c" ] && { printf 'REAL\n'; exit 0; }
exit 0
REALEOF
chmod +x "$STUB/python3" "$STUB/python"

if PATH="$STUB:$PATH" command -v python3 >/dev/null 2>&1; then
  ok "control: the stub satisfies \`command -v python3\` (the old guard passes)"
else
  no "control: the stub satisfies \`command -v python3\`" \
     "the Windows condition no longer reproduces — sections below prove nothing"
fi
if PATH="$STUB:$PATH" python3 -c 'import sys' >/dev/null 2>&1; then
  no "control: the stub FAILS when actually run" "stub returned success — fixture is wrong"
else
  ok "control: the stub fails when actually run (exit 49, no stdout)"
fi

# ---------------------------------------------------------------------------
# 2. The resolver picks a python that RUNS, not the first name that exists.
#    Mirrors the resolver shipped in connect.sh / update.md.
# ---------------------------------------------------------------------------
resolve(){ for c in python3 python py; do
    command -v "$c" >/dev/null 2>&1 || continue
    "$c" -c 'import json,sys' >/dev/null 2>&1 || continue
    printf '%s\n' "$c"; return 0
  done; return 1; }
GOT="$(PATH="$STUB:$PATH"; resolve || true)"
if [ "$GOT" = "python" ]; then
  ok "resolver skips the stub and selects a working interpreter"
else
  no "resolver skips the stub" "resolved '<${GOT}>' — expected 'python'"
fi

# ---------------------------------------------------------------------------
# 3. No shipped script may invoke a bare `python3` in a COMMAND position, nor
#    lean on `command -v python3` as its only gate.
# ---------------------------------------------------------------------------
BAREPY="$(grep -nE '(^|[^-[:alnum:]_"])python3 [-"$]' "$C" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -n "$BAREPY" ]; then
  no "connect.sh invokes no bare python3" "$BAREPY"
else
  ok "connect.sh invokes python only through the resolved \$PYTHON"
fi
if grep -q 'MANIFEST=\$(python3 ' "$U"; then
  no "update.md resolves python before reading the plugin manifest" \
     "a bare python3 with 2>/dev/null yields an EMPTY manifest on Windows, silently"
else
  ok "update.md resolves python before reading the plugin manifest"
fi

# ---------------------------------------------------------------------------
# 4. CONTROL — reproduce the CRLF condition and prove plain diff reports it as
#    a content difference. This is what made the reconcile unusable on Windows.
# ---------------------------------------------------------------------------
printf 'alpha\r\nbeta\r\n' > "$TMP/crlf.md"
printf 'alpha\nbeta\n'     > "$TMP/lf.md"
if diff -q "$TMP/crlf.md" "$TMP/lf.md" >/dev/null 2>&1; then
  no "control: plain diff calls CRLF-vs-LF a difference" "this platform's diff already normalizes — section 5 proves nothing here"
else
  ok "control: plain diff calls CRLF-vs-LF a difference"
fi
if diff -q --strip-trailing-cr "$TMP/crlf.md" "$TMP/lf.md" >/dev/null 2>&1; then
  ok "--strip-trailing-cr equates them on this platform"
else
  ok "--strip-trailing-cr unsupported here — the spec's probe is why it must not be assumed"
fi

# ---------------------------------------------------------------------------
# 5. Every content-comparing diff in the spec is normalized, and the flag is
#    PROBED rather than assumed (the #143 lesson: no GNU-only flag by faith).
# ---------------------------------------------------------------------------
BARE="$(grep -nE '^[[:space:]]*(else )?diff -r?q "\$(VAULT|V)/' "$U" | grep -v 'SCR' || true)"
if [ -n "$BARE" ]; then
  no "no un-normalized diff remains in the reconcile" "$BARE"
else
  ok "every reconcile diff carries the normalization flag"
fi
if grep -q 'SCR=(--strip-trailing-cr)' "$U" && grep -q 'scr-crlf' "$U" && grep -q 'scr-lf' "$U"; then
  ok "the flag is probed against a real CRLF/LF pair, not assumed"
else
  no "the flag is probed, not assumed" "expected a probe building a CRLF/LF pair and setting SCR"
fi

echo
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1

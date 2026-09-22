#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The floor's PRESCRIBED INVOCATION must actually run where sessions run.
#
# CLAUDE.md § Identity & Greeting 4a names one command as the mandatory first
# context load. Its whole justification is that a floor which emits nothing is
# indistinguishable from a floor that fired — so the invocation itself failing
# is not a degraded outcome, it is the exact failure the step exists to end.
#
# It has now arrived twice, by two different routes:
#   1. `python3` on Windows is a Microsoft Store alias that runs nothing.
#      Answered by mandating `uv` (#129).
#   2. `uv` insists on `~/.cache/uv`, which a SANDBOXED Bash tool may not write
#      (the allowlist is the vault + $TMPDIR). It dies before running anything.
#      Every sandboxed session hits it; the primary unsandboxed session never
#      does, which is why it survived. Answered by UV_CACHE_DIR.
#
# So this does not grep the docs for a reassuring string. It EXTRACTS the
# command the contract prescribes, runs it against a HOME whose cache cannot be
# written, and requires real output — with a CONTROL that strips UV_CACHE_DIR
# from the same command and requires it to produce NOTHING. If that control ever
# stops failing, the condition has stopped reproducing and everything below it
# proves nothing.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
sk(){ SKIP=$((SKIP+1)); printf '  skip %s\n' "$1"; }

echo "== context-floor invocation =="

# ── 1. both contracts prescribe the same, runnable command ───────────────────
for f in CLAUDE.md AGENTS.md; do
  line=$(grep -m1 'uv run ~/aios/hooks/context-floor.py' "$f" 2>/dev/null)
  if [ -z "$line" ]; then
    no "$f prescribes the floor command" "no 'uv run …context-floor.py' line found"
  elif printf '%s' "$line" | grep -q 'UV_CACHE_DIR'; then
    ok "$f prescribes it with UV_CACHE_DIR"
  else
    no "$f prescribes it WITHOUT UV_CACHE_DIR" \
       "a sandboxed session cannot write ~/.cache/uv; the floor emits nothing and nothing says so"
  fi
done

# ── 2. RUN IT. Spelling is the weak claim; this is the real one. ─────────────
if ! command -v uv >/dev/null 2>&1; then
  sk "uv not installed — the execution half cannot run here"
  printf '\n  %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]; exit $?
fi

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAKE="$TMP/home"; mkdir -p "$FAKE/.cache"; chmod 500 "$FAKE/.cache"

# The condition must REPRODUCE, or the assertion after it is decoration.
# `env -u` is load-bearing: GitHub's setup-uv action exports UV_CACHE_DIR for the
# whole job, so a "bare" control inheriting it is not bare and passes for the wrong
# reason. Measured: this control failed in CI on its first run and said so, which is
# what a control is for. XDG_CACHE_HOME is cleared too — uv honours it as well, so
# leaving it set would relocate the cache out of the unwritable HOME and silently
# un-reproduce the condition.
out_ctl="$TMP/ctl.out"
env -u UV_CACHE_DIR -u XDG_CACHE_HOME HOME="$FAKE" uv run hooks/context-floor.py >"$out_ctl" 2>/dev/null
if [ -s "$out_ctl" ]; then
  no "CONTROL: bare 'uv run' should fail against an unwritable cache" \
     "it produced output, so this environment does not reproduce the condition — the check below proves nothing"
else
  ok "CONTROL: bare 'uv run' emits nothing when ~/.cache/uv is unwritable"
fi

out_fix="$TMP/fix.out"
env -u XDG_CACHE_HOME HOME="$FAKE" UV_CACHE_DIR="$TMP/uv-cache" uv run hooks/context-floor.py >"$out_fix" 2>"$TMP/fix.err"
if [ ! -s "$out_fix" ]; then
  no "the prescribed command runs against an unwritable cache" "$(head -2 "$TMP/fix.err" 2>/dev/null)"
else
  ok "the prescribed command runs against an unwritable cache ($(grep -c . "$out_fix") lines)"
  grep -q 'CONTEXT FLOOR' "$out_fix" \
    && ok "and the output is the floor, not an error page" \
    || no "output is not the floor" "$(head -2 "$out_fix")"
fi

printf '\n  %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]

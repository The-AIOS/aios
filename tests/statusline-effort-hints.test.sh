#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The status line shows the effort level beside the model, and two key hints
#
# WHY THIS EXISTS
# Operators did not know the effort level a session runs at, or the keys for a new
# line and for interrupting a turn. The status line now shows `[Model · effort]` and
# ends with a dim `\⏎ new line · esc interrupt`, in the style of Claude Code's own
# dim hints. (#263)
#
# WHAT IT HOLDS
#   * effort comes from the payload's `effort.level`, the documented field
#   * no effort in the payload (a model without the parameter) → the model alone,
#     exactly as before; never an invented level
#   * anything odd in that field renders nothing rather than breaking the line, because
#     this runs on every prompt render
#   * the hints are the LAST segment, so a narrow pane that truncates the line loses
#     the hints before anything that carries state
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
MOD=hooks/claude-identity/context-monitor.py

# Render the line for a payload, ANSI colours stripped. An empty HOME keeps the
# operator's own accounts, swap banner and caches out of the result.
render(){ printf '%s' "$1" | HOME="$T" USER_MD_PATH="$T/none.md" $PYBIN "$MOD" 2>/dev/null \
  | sed $'s/\x1b\\[[0-9;]*m//g'; }

BASE='"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"/tmp/x"}'

out=$(render "{$BASE,\"effort\":{\"level\":\"high\"}}")
case "$out" in *"[Opus 5.5 · high]"*) ok "effort renders right after the model";;
  *) no "effort renders right after the model" "$out";; esac

out=$(render "{$BASE}")
case "$out" in *"[Opus 5.5]"*) ok "no effort in the payload → the model alone";;
  *) no "no effort in the payload → the model alone" "$out";; esac

for odd in '"effort":null' '"effort":{"level":42}' '"effort":"high"' '"effort":{"level":"<b>x</b>"}' '"effort":{}'; do
  out=$(render "{$BASE,$odd}")
  case "$out" in *"[Opus 5.5]"*) ok "an odd effort field ($odd) renders the model alone";;
    *) no "an odd effort field ($odd) renders the model alone" "$out";; esac
done

out=$(render "{$BASE,\"effort\":{\"level\":\"medium\"}}")
case "$out" in *"\⏎ new line · esc interrupt") ok "the key hints are the last segment";;
  *) no "the key hints are the last segment" "$out";; esac

case "$(render 'not json')" in *"[Claude]"*) ok "a broken payload still prints the fallback line";;
  *) no "a broken payload still prints the fallback line";; esac

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one. Same probe
# hooks/claude-identity/claude-identity.sh and mcps/setup.sh already use.
# $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

# quota-config-dir.test.sh — every component follows CLAUDE_CONFIG_DIR together.
#
# Why this matters beyond tidiness: the documented safe way to add a second
# account is to log it into an ISOLATED config dir and capture from there, so the
# live credentials are never touched and no logout fires. (`/login` performs a
# server-side revoke of the previous refresh token, so the naive "log in, then
# capture" flow can kill an identity you already captured.) That workflow only
# holds if the tools actually follow the relocation.
#
# The failure mode if one component lags is the nastiest kind: every path still
# resolves, nothing errors, and the watcher reads one account's state while the
# operator works in another. So these assert the components AGREE — a partial
# migration is worse than none, and is invisible without a test like this.

set -uo pipefail
export AIOS_QUOTA_NOTIFY=0   # drives real watcher code: never put a quota banner on this machine's desktop
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$ROOT/hooks/claude-identity"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n     %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/qcd-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ALT="$WORK/alt-config"
mkdir -p "$ALT"

echo "quota-config-dir: $D"

# 1. _watch.py resolves every one of its state paths inside the relocated dir.
out="$(CLAUDE_CONFIG_DIR="$ALT" python3 - "$D/_watch.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
print("\n".join([w.CACHE, w.LOG, w.SWAP_LOG, w.IDENTITIES]))
PYEOF
)"
if [ "$(printf '%s' "$out" | grep -cv "^$ALT/")" -eq 0 ] && [ -n "$out" ]; then
  ok "_watch.py puts cache, log, swap-log and identities under CLAUDE_CONFIG_DIR"
else
  no "_watch.py puts cache, log, swap-log and identities under CLAUDE_CONFIG_DIR" \
     "escaped: $(printf '%s' "$out" | grep -v "^$ALT/" | tr '\n' ' ')"; fi

# 2. _cache.py agrees — including the tick marker, which is the one easy to miss
#    because it is written from a helper that takes `home`, not the config dir.
out="$(CLAUDE_CONFIG_DIR="$ALT" python3 - "$D/_cache.py" "$WORK" <<'PYEOF'
import importlib.util, sys, os
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
home = sys.argv[2]
print(c.config_dir())
print(os.path.join(c.config_dir(), "watch-tick"))
PYEOF
)"
if [ "$(printf '%s' "$out" | grep -cv "^$ALT")" -eq 0 ] && [ -n "$out" ]; then
  ok "_cache.py resolves its config dir and tick marker under CLAUDE_CONFIG_DIR"
else
  no "_cache.py resolves its config dir and tick marker under CLAUDE_CONFIG_DIR" "got: $out"; fi

# 3. The shell agrees. Probed by sourcing the config block only — running a
#    subcommand would need a real credential store.
out="$(CLAUDE_CONFIG_DIR="$ALT" SRC="$D/claude-identity.sh" bash -c '
  set -uo pipefail
  eval "$(sed -n "/^CONFIG_DIR=/,/^SWAP_LOG=/p" "$SRC")"
  printf "%s\n%s\n%s\n%s\n" "$IDENTITIES_DIR" "$CACHE_FILE" "$WATCH_LOG" "$SWAP_LOG"
')"
if [ "$(printf '%s' "$out" | grep -cv "^$ALT/")" -eq 0 ] && [ -n "$out" ]; then
  ok "claude-identity.sh resolves its state paths under CLAUDE_CONFIG_DIR"
else
  no "claude-identity.sh resolves its state paths under CLAUDE_CONFIG_DIR" "got: $out"; fi

# 4. Unset must reproduce the classic layout exactly — this is the back-compat
#    guard for every existing macOS operator.
out="$(env -u CLAUDE_CONFIG_DIR python3 - "$D/_watch.py" <<'PYEOF'
import importlib.util, sys, os
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
print(w.CONFIG_DIR == os.path.join(os.path.expanduser("~"), ".claude"))
PYEOF
)"
if [ "$out" = "True" ]; then
  ok "unset CLAUDE_CONFIG_DIR keeps the classic ~/.claude layout"
else
  no "unset CLAUDE_CONFIG_DIR keeps the classic ~/.claude layout" "got: $out"; fi

# 5. .claude.json is the odd one out — beside the config dir normally, inside it
#    when relocated. Both branches must resolve to a real file.
printf '{"oauthAccount":{"emailAddress":"relocated@example.com"}}' > "$ALT/.claude.json"
out="$(CLAUDE_CONFIG_DIR="$ALT" SRC="$D/claude-identity.sh" bash -c '
  set -uo pipefail
  eval "$(sed -n "/^CONFIG_DIR=/,/^IDENTITIES_DIR=/p" "$SRC")"
  echo "$CLAUDE_JSON"
')"
if [ "$out" = "$ALT/.claude.json" ]; then
  ok "a relocated .claude.json is preferred when present"
else
  no "a relocated .claude.json is preferred when present" "got: $out"; fi

rm -f "$ALT/.claude.json"
out="$(CLAUDE_CONFIG_DIR="$ALT" SRC="$D/claude-identity.sh" bash -c '
  set -uo pipefail
  eval "$(sed -n "/^CONFIG_DIR=/,/^IDENTITIES_DIR=/p" "$SRC")"
  echo "$CLAUDE_JSON"
')"
if [ "$out" = "$HOME/.claude.json" ]; then
  ok "falls back to \$HOME/.claude.json when the relocated one is absent"
else
  no "falls back to \$HOME/.claude.json when the relocated one is absent" "got: $out"; fi

# ── The statusline and the swap marker (The-AIOS/aios-app#226) ───────────────
# context-monitor.py is the renderer every session runs, and it read three paths
# from a fixed ~/.claude: the account (.claude.json), the cost tracker and the
# swap marker the watcher writes. With the variable set, the bar named the
# default seat's account while the session ran on another. A fake HOME keeps the
# machine's real files out of every case below.
FH="$WORK/home"; mkdir -p "$FH/.claude"
printf '{"oauthAccount":{"emailAddress":"home@example.com"}}' > "$FH/.claude.json"

# Runs $PROBE against context-monitor.py (cm) and _fs.py (fs) with HOME=$FH.
# $1 = CLAUDE_CONFIG_DIR, or "" for unset.
probe() {
  local cfg="$1"
  if [ -n "$cfg" ]; then set -- env HOME="$FH" CLAUDE_CONFIG_DIR="$cfg"
  else set -- env -u CLAUDE_CONFIG_DIR HOME="$FH"; fi
  "$@" $PYBIN - "$D" <<PYEOF 2>&1
import importlib.util, os, sys
sys.path.insert(0, sys.argv[1])
spec = importlib.util.spec_from_file_location("cm", os.path.join(sys.argv[1], "context-monitor.py"))
cm = importlib.util.module_from_spec(spec); spec.loader.exec_module(cm)
import _fs as fs
$PROBE
PYEOF
}

# 7. One rule for .claude.json in Python, and the shell gives the same answers.
printf '{"oauthAccount":{"emailAddress":"relocated@example.com"}}' > "$ALT/.claude.json"
PROBE='print(fs.claude_json_path())'
a="$(probe "$ALT")"
rm -f "$ALT/.claude.json"
b="$(probe "$ALT")"
c="$(probe "")"
if [ "$a" = "$ALT/.claude.json" ] && [ "$b" = "$FH/.claude.json" ] && [ "$c" = "$FH/.claude.json" ]; then
  ok "_fs.claude_json_path: inside the relocated dir when present, else beside home"
else
  no "_fs.claude_json_path: inside the relocated dir when present, else beside home" "present=$a absent=$b unset=$c"; fi

sh_json() {  # the shell's answer for the same case, with the same fake HOME
  HOME="$FH" CFG="$1" SRC="$D/claude-identity.sh" bash -c '
    set -uo pipefail
    if [ -n "$CFG" ]; then export CLAUDE_CONFIG_DIR="$CFG"; else unset CLAUDE_CONFIG_DIR; fi
    eval "$(sed -n "/^CONFIG_DIR=/,/^IDENTITIES_DIR=/p" "$SRC")"
    echo "$CLAUDE_JSON"'
}
printf '{}' > "$ALT/.claude.json"; s1="$(sh_json "$ALT")"; rm -f "$ALT/.claude.json"
s2="$(sh_json "$ALT")"; s3="$(sh_json "")"
if [ "$s1" = "$a" ] && [ "$s2" = "$b" ] && [ "$s3" = "$c" ]; then
  ok "claude-identity.sh resolves .claude.json exactly as _fs.py does, in all three cases"
else
  no "claude-identity.sh resolves .claude.json exactly as _fs.py does, in all three cases" \
     "shell: $s1 | $s2 | $s3 — python: $a | $b | $c"; fi

# 8. No Python module in claude-identity/ (nor the trust check) builds the path to
#    .claude.json, the config dir or the swap marker itself: the rule lives in _fs.py.
#    Only path-like string literals count: docstrings and messages (anything with a
#    space) are skipped, and comments are not strings.
escaped="$(cd "$ROOT/hooks" && for f in claude-identity/*.py install/run-trust-check.py; do
  [ "$f" = "claude-identity/_fs.py" ] && continue
  $PYBIN - "$f" <<'PYEOF'
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
for tok in tokenize.generate_tokens(io.StringIO(src).readline):
    if tok.type != tokenize.STRING or tok.string.startswith(('"""', "'''")):
        continue
    if any(c.isspace() for c in tok.string):
        continue   # a message that names a file is not a path being built
    if any(k in tok.string for k in (".claude.json", "CLAUDE_CONFIG_DIR", "swap-notification.json", "~/.claude")):
        print(f"{sys.argv[1]}:{tok.start[0]}: {tok.string}")
PYEOF
done)"
if [ -z "$escaped" ]; then
  ok "no module outside _fs.py builds .claude.json, the config dir or the swap marker path"
else
  no "no module outside _fs.py builds .claude.json, the config dir or the swap marker path" "$escaped"; fi

# 9. The statusline's own files follow the variable: the account it names, the cost tracker.
printf '{"oauthAccount":{"emailAddress":"relocated@example.com"}}' > "$ALT/.claude.json"
PROBE='print(cm.COST_TRACKER_FILE); print(cm.get_account_display())'
out="$(probe "$ALT")"
if [ "$(printf '%s\n' "$out" | head -1)" = "$ALT/monthly-cost-tracker.json" ] \
   && printf '%s' "$out" | grep -q "relocated" && ! printf '%s' "$out" | grep -q "home"; then
  ok "context-monitor names the relocated account and keeps its cost tracker in the relocated dir"
else
  no "context-monitor names the relocated account and keeps its cost tracker in the relocated dir" "got: $out"; fi
rm -f "$ALT/.claude.json"
out="$(probe "")"
if [ "$(printf '%s\n' "$out" | head -1)" = "$FH/.claude/monthly-cost-tracker.json" ] && printf '%s' "$out" | grep -q "home"; then
  ok "unset: context-monitor keeps ~/.claude and ~/.claude.json"
else
  no "unset: context-monitor keeps ~/.claude and ~/.claude.json" "got: $out"; fi

# 10. The swap marker: the watcher writes it in the config dir, the banner reads it
#     there, and still reads the old ~/.claude spot — that is where an installed Glass
#     (and any framework before this change) writes it, whatever the variable says.
PROBE='print(fs.swap_marker_path())'
out="$(probe "$ALT")"; out2="$(probe "")"
if [ "$out" = "$ALT/swap-notification.json" ] && [ "$out2" = "$FH/.claude/swap-notification.json" ]; then
  ok "the swap marker lives in the config dir (\$CLAUDE_CONFIG_DIR, else ~/.claude)"
else
  no "the swap marker lives in the config dir (\$CLAUDE_CONFIG_DIR, else ~/.claude)" "set=$out unset=$out2"; fi

if grep -q 'write_json_atomic(swap_marker_path()' "$D/_watch.py"; then
  ok "_watch.py writes the marker through _fs.swap_marker_path()"
else no "_watch.py writes the marker through _fs.swap_marker_path()" "no such call in _watch.py"; fi

marker() { printf '{"from":"%s","to":"%s","ts":%s,"reason":"t"}' "$2" "$3" "$4" > "$1"; }
now=$(date +%s)
rm -f "$ALT/swap-notification.json" "$FH/.claude/swap-notification.json"
PROBE='print(cm.get_swap_banner())'
marker "$ALT/swap-notification.json" a@x b@x "$now"
o1="$(probe "$ALT")"; rm -f "$ALT/swap-notification.json"
marker "$FH/.claude/swap-notification.json" c@x d@x "$now"
o2="$(probe "$ALT")"
marker "$ALT/swap-notification.json" e@x f@x "$((now - 60))"
o3="$(probe "$ALT")"
o4="$(probe "")"
marker "$ALT/swap-notification.json" g@x h@x "$now"
marker "$FH/.claude/swap-notification.json" c@x d@x "$((now - 60))"
o5="$(probe "$ALT")"
rm -f "$ALT/swap-notification.json" "$FH/.claude/swap-notification.json"
if printf '%s' "$o1" | grep -q 'a→b'; then
  ok "the banner reads a marker the watcher wrote in the relocated dir"
else no "the banner reads a marker the watcher wrote in the relocated dir" "got: $o1"; fi
if printf '%s' "$o2" | grep -q 'c→d'; then
  ok "the banner still reads a marker left in ~/.claude (installed Glass, older framework)"
else no "the banner still reads a marker left in ~/.claude (installed Glass, older framework)" "got: $o2"; fi
if printf '%s' "$o3" | grep -q 'c→d' && printf '%s' "$o5" | grep -q 'g→h'; then
  ok "with a marker in both places, the newer one wins, whichever place it is in"
else no "with a marker in both places, the newer one wins, whichever place it is in" "older in config dir: $o3 | older in ~/.claude: $o5"; fi
if printf '%s' "$o4" | grep -q 'c→d'; then
  ok "unset: the banner reads ~/.claude as before"
else no "unset: the banner reads ~/.claude as before" "got: $o4"; fi

# 11. The renderer must never go blank because its helper is missing or older: a
#     copy run on its own (the README allows one), or an _fs.py from before these
#     helpers, still draws the bar.
LONE="$WORK/lone"; mkdir -p "$LONE"; cp "$D/context-monitor.py" "$LONE/"
printf 'def write_json_atomic(*a, **k):\n    pass\n' > "$WORK/old_fs.py"
r1="$(printf '{"model":{"display_name":"Opus"}}' | HOME="$FH" $PYBIN "$LONE/context-monitor.py" 2>&1)"; c1=$?
cp "$WORK/old_fs.py" "$LONE/_fs.py"
r2="$(printf '{"model":{"display_name":"Opus"}}' | HOME="$FH" $PYBIN "$LONE/context-monitor.py" 2>&1)"; c2=$?
if [ $c1 -eq 0 ] && [ $c2 -eq 0 ] && printf '%s' "$r1" | grep -q Opus && printf '%s' "$r2" | grep -q Opus \
   && ! printf '%s%s' "$r1" "$r2" | grep -q Traceback; then
  ok "context-monitor still draws the bar alone, or beside an older _fs.py"
else
  no "context-monitor still draws the bar alone, or beside an older _fs.py" "alone rc=$c1: $r1 | old _fs rc=$c2: $r2"; fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

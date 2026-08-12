#!/usr/bin/env bash
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
print(c.config_dir(home))
print(os.path.join(c.config_dir(home), "watch-tick"))
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

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

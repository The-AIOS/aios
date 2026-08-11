#!/usr/bin/env bash
# claude-identity.sh — multi-account Claude Code identity manager + quota autopilot.
#
# ============================================================================
# WHAT THIS IS
# ============================================================================
# One tool that handles three concerns for running Claude Code across multiple
# Anthropic accounts (e.g., a primary + an overflow to dodge the 5h/7d rate
# limits). All state is self-contained in your vault + ~/.claude/.
#
# 1. Identity: save/restore/rotate between Anthropic accounts.
#    Swaps the Keychain 'Claude Code-credentials' blob + the oauthAccount
#    object + userID in ~/.claude.json atomically. Never touches mcpServers
#    or project configs. Captures the outgoing identity before every swap
#    (refresh tokens rotate).
#
# 2. Cache: read a Claude Code hook payload from stdin, extract the
#    rate_limits object + current account email, write to
#    ~/.claude/rate-limit-cache.json. The hook fires on every turn, so the
#    cache stays fresh while a session is active.
#
# 3. Watch: read the cache, decide whether to rotate accounts based on the
#    5h + 7d usage percentages vs thresholds, execute a swap if so. Designed
#    to run under launchd every few minutes.
#
# ============================================================================
# INSTALL ON A NEW MACHINE (macOS)
# ============================================================================
# All paths assume the vault is at ~/aios. Adjust if cloned elsewhere.
#
# Step 1 — shell aliases. Add to ~/.zshrc (or ~/.bashrc):
#
#   claude-whoami() { ~/aios/hooks/claude-identity/claude-identity.sh whoami; }
#   claude-switch() { ~/aios/hooks/claude-identity/claude-identity.sh switch "$@"; }
#
# Step 2 — populate USER.md → ## Anthropic accounts with a numbered list:
#
#   1. `primary@example.com` — optional label/context
#   2. `overflow@example.com`
#
# Step 3 — capture each identity once. For each account, log into it via the
# normal Claude Code flow, then:
#
#   claude-switch --capture
#
# Step 4 — wire the cache writer to the statusLine command. The statusline
# is the ONLY Claude Code surface that receives rate_limits on stdin (Stop
# hook payload does not include them). We piggyback via `tee` — same stdin
# flows to our cache writer AND to the real statusline renderer, so the
# cache is always fresh during active use.
#
# Important: Claude Code runs the statusLine command directly, NOT through
# bash. Process substitution (>(...)) is bash-only — you must wrap in
# `bash -c '...'` or the statusline will come out blank.
#
#   python3 - <<'PY'
#   import json, os
#   p = os.path.expanduser("~/.claude/settings.json")
#   d = json.load(open(p)) if os.path.exists(p) else {}
#   cmd = os.path.expanduser("~/aios/hooks/claude-identity/claude-identity.sh") + " cache"
#   existing = d.get("statusLine", {}).get("command", "") \
#              or "python3 ~/.claude/scripts/context-monitor.py"  # or your own
#   d["statusLine"] = {"type": "command",
#                      "command": f"bash -c 'tee >({cmd} > /dev/null) | {existing}'"}
#   json.dump(d, open(p, "w"), indent=2)
#   PY
#
# Step 5 — load the launchd agent (runs `watch` every 10 min, swaps when near cap):
#
#   cp ~/aios/hooks/claude-identity/com.aios.claude-quota-watch.plist ~/Library/LaunchAgents/
#   launchctl load ~/Library/LaunchAgents/com.aios.claude-quota-watch.plist
#
# Verify: `claude-whoami` works, `claude mcp list` unchanged, after a few
# minutes `~/.claude/rate-limit-cache.json` appears and stays fresh as you use
# Claude Code. The launchd log at ~/.claude/quota-watch.log records each check.
#
# ============================================================================
# SUBCOMMANDS
# ============================================================================
#   whoami                 current account + next in USER.md rotation
#   list                   all configured + saved-state status
#   switch                 rotate to next account in USER.md (wraps)
#   switch {email}         jump to a specific account
#   switch --capture       save current identity to ~/.claude/identities/
#   switch --list          alias for `list`
#   switch --help          swap-specific usage
#   cache                  read stdin JSON, write ~/.claude/rate-limit-cache.json
#                          (statusLine-piggyback entrypoint — not Stop hook;
#                           Stop payloads don't include rate_limits)
#   watch                  read cache, swap if above thresholds
#                          (launchd entrypoint)
#
# Environment overrides for the watcher thresholds:
#   CLAUDE_QUOTA_5H=98      rotate when 5h pct >= this
#   CLAUDE_QUOTA_7D=98      rotate when 7d pct >= this
#
# These are read by _watch.py, which OWNS the default — this script deliberately
# does not define one. It used to (`THRESHOLD_5H="${CLAUDE_QUOTA_5H:-98}"`), and
# that copy was never read by anything: nothing in this file consumed it, it was
# never exported, and the hot path (statusLine -> _cache.py -> _watch.py) never
# runs this script at all. An operator who edited it got silence, not an effect.
# One value, one owner. Export the env vars to change it; `watch --threshold`
# prints what is actually in force.
#
# Note (2026-04-23): come-home semantics removed for topology-independence.
# The watcher now does pure rotate-only: when current account hits its cap,
# advance to the next account in USER.md. Round-robin alternation across
# however many accounts you list.
#
# ============================================================================

set -euo pipefail

USER_MD="${USER_MD_PATH:-$HOME/aios/USER.md}"
# Claude Code relocates its whole config tree when CLAUDE_CONFIG_DIR is set, and
# the safe way to add a second account leans on exactly that: log the new account
# into an isolated config dir and `--capture` from there, so the live credentials
# are never touched and no logout fires (see the /login revoke note below).
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# .claude.json sits BESIDE the config dir in the default layout but INSIDE it
# when relocated. Try the relocated position first, then fall back.
if [ -f "$CONFIG_DIR/.claude.json" ]; then
  CLAUDE_JSON="$CONFIG_DIR/.claude.json"
else
  CLAUDE_JSON="$HOME/.claude.json"
fi
IDENTITIES_DIR="$CONFIG_DIR/identities"
KEYCHAIN_SERVICE="Claude Code-credentials"
CACHE_FILE="$CONFIG_DIR/rate-limit-cache.json"
WATCH_LOG="$CONFIG_DIR/quota-watch.log"
SWAP_LOG="$CONFIG_DIR/swap-log.jsonl"

# NOTE: the rotation thresholds are intentionally NOT defined here — _watch.py
# owns them. See the "Environment overrides" block above.

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; RESET=""
fi

die() { echo "${RED}error:${RESET} $*" >&2; exit 1; }

# ---- parse USER.md for the ordered account list ----
parse_accounts() {
  [ -f "$USER_MD" ] || die "USER.md not found at $USER_MD (set USER_MD_PATH if elsewhere)"
  awk '
    /^## Anthropic accounts/ { in_sec = 1; next }
    in_sec && /^## / { in_sec = 0 }
    in_sec && /^[0-9]+\. `[^`]+`/ {
      match($0, /`[^`]+`/)
      if (RSTART > 0) {
        email = substr($0, RSTART + 1, RLENGTH - 2)
        print email
      }
    }
  ' "$USER_MD"
}

current_email() {
  [ -f "$CLAUDE_JSON" ] || die "$CLAUDE_JSON not found"
  python3 -c "
import json
d = json.load(open('$CLAUDE_JSON'))
print(d.get('oauthAccount', {}).get('emailAddress', ''))
"
}

capture_current() {
  local email="$1"
  [ -n "$email" ] || die "capture_current: no email"
  local dir="$IDENTITIES_DIR/$email"
  mkdir -p "$dir"
  chmod 700 "$IDENTITIES_DIR" "$dir"

  local blob
  blob=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null) || \
    die "could not read Keychain '$KEYCHAIN_SERVICE'. Is this account fully logged in to Claude Code?"
  printf '%s' "$blob" > "$dir/keychain.json"
  chmod 600 "$dir/keychain.json"

  python3 - <<PY
import json
d = json.load(open('$CLAUDE_JSON'))
with open('$dir/oauthAccount.json', 'w') as f:
    json.dump(d.get('oauthAccount', {}), f, indent=2)
with open('$dir/userID.txt', 'w') as f:
    f.write(d.get('userID', ''))
PY
  chmod 600 "$dir/oauthAccount.json" "$dir/userID.txt"

  echo "${GREEN}✓${RESET} captured identity ${BOLD}$email${RESET} → $dir"
}

restore_identity() {
  local email="$1"
  local dir="$IDENTITIES_DIR/$email"
  [ -d "$dir" ] || die "no saved state for $email. Run 'claude-switch --capture' while logged in as $email first."
  [ -f "$dir/keychain.json" ] || die "$dir/keychain.json missing"
  [ -f "$dir/oauthAccount.json" ] || die "$dir/oauthAccount.json missing"
  [ -f "$dir/userID.txt" ] || die "$dir/userID.txt missing"

  cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak-claude-switch"

  local blob
  blob=$(cat "$dir/keychain.json")
  security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$blob" >/dev/null 2>&1 || \
    die "security add-generic-password failed"

  python3 - <<PY
import json, shutil
with open('$CLAUDE_JSON') as f:
    d = json.load(f)
with open('$dir/oauthAccount.json') as f:
    d['oauthAccount'] = json.load(f)
with open('$dir/userID.txt') as f:
    d['userID'] = f.read().strip()
tmp = '$CLAUDE_JSON.tmp'
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2)
shutil.move(tmp, '$CLAUDE_JSON')
PY

  echo "${GREEN}✓${RESET} switched to ${BOLD}$email${RESET}"
  echo "${DIM}backup: $CLAUDE_JSON.bak-claude-switch${RESET}"
  echo "${YELLOW}note:${RESET} any running Claude Code session still holds the previous token in memory. Restart it (or open a new terminal) to use the new identity."
}

# ---- subcommands ----

cmd_whoami() {
  local cur; cur=$(current_email)
  [ -n "$cur" ] || die "could not detect current account from $CLAUDE_JSON"
  local accts; accts=$(parse_accounts)
  local total; total=$(printf '%s\n' "$accts" | grep -c .)
  local idx; idx=$(printf '%s\n' "$accts" | awk -v c="$cur" '$0==c {print NR; exit}')
  local next=""
  if [ -n "$idx" ] && [ "$total" -gt 1 ]; then
    local next_idx=$(( idx % total + 1 ))
    next=$(printf '%s\n' "$accts" | sed -n "${next_idx}p")
  fi

  echo "${BOLD}Currently:${RESET} ${GREEN}$cur${RESET}"
  if [ -n "$idx" ]; then
    echo "${DIM}($idx of $total in USER.md rotation)${RESET}"
  else
    echo "${YELLOW}(not listed in USER.md → ## Anthropic accounts — 'claude-switch --capture' will save it anyway)${RESET}"
  fi
  if [ -n "$next" ]; then
    echo "${BOLD}Next:${RESET}      ${BLUE}$next${RESET}   ${DIM}(claude-switch to rotate)${RESET}"
  fi
}

cmd_list() {
  local cur; cur=$(current_email)
  local accts; accts=$(parse_accounts)
  [ -n "$accts" ] || die "no accounts found in USER.md → ## Anthropic accounts"
  echo "${BOLD}Accounts configured in USER.md:${RESET}"
  local i=1
  while IFS= read -r email; do
    [ -n "$email" ] || continue
    local marker=" "
    [ "$email" = "$cur" ] && marker="●"
    local saved="${DIM}(not saved)${RESET}"
    [ -d "$IDENTITIES_DIR/$email" ] && saved="${GREEN}✓ saved${RESET}"
    printf "  %s %d. %-30s %s\n" "$marker" "$i" "$email" "$saved"
    i=$(( i + 1 ))
  done <<< "$accts"
  echo ""
  echo "${DIM}● = currently active · use 'claude-switch {email}' or bare 'claude-switch' to rotate${RESET}"
}

cmd_switch() {
  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<USAGE
claude-switch — rotate or jump between Anthropic accounts.

Usage:
  claude-switch                    rotate to next account in USER.md list
  claude-switch {email}            switch to a specific account
  claude-switch --capture          save current identity to ~/.claude/identities/
  claude-switch --list             show all configured + saved state
  claude-switch --help             this

First-time setup per account:
  1. Be logged into that Anthropic account in Claude Code (normal /login flow)
  2. Run: claude-switch --capture
  3. Repeat for each account in USER.md → ## Anthropic accounts

Safety:
  - Swaps Keychain '$KEYCHAIN_SERVICE' blob + .claude.json oauthAccount + userID
  - Always captures outgoing identity before swap (refresh tokens rotate)
  - Never touches mcpServers, project configs, or history
  - Backup written to $CLAUDE_JSON.bak-claude-switch on every swap
USAGE
    return 0
  fi

  if [ "${1:-}" = "--capture" ]; then
    local cur; cur=$(current_email)
    [ -n "$cur" ] || die "could not detect current account from $CLAUDE_JSON"
    capture_current "$cur"
    return 0
  fi

  if [ "${1:-}" = "--list" ]; then
    cmd_list
    return 0
  fi

  local target="${1:-}"
  local cur; cur=$(current_email)

  if [ -z "$target" ]; then
    local accts; accts=$(parse_accounts)
    local total; total=$(printf '%s\n' "$accts" | grep -c .)
    [ "$total" -ge 2 ] || die "need at least 2 accounts in USER.md to rotate (found $total)"
    local idx; idx=$(printf '%s\n' "$accts" | awk -v c="$cur" '$0==c {print NR; exit}')
    if [ -z "$idx" ]; then
      target=$(printf '%s\n' "$accts" | sed -n '1p')
    else
      local next_idx=$(( idx % total + 1 ))
      target=$(printf '%s\n' "$accts" | sed -n "${next_idx}p")
    fi
  fi

  [ "$target" != "$cur" ] || { echo "${YELLOW}already on $target${RESET}"; return 0; }

  echo "${DIM}capturing outgoing identity ($cur) before swap...${RESET}"
  capture_current "$cur"

  restore_identity "$target"
}

# The cache + watch logic lives in sibling .py files (stdin flows naturally
# to standalone scripts; heredocs hijacked stdin).
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# `cache` reads stdin (the statusline input, wrapped via tee) and writes
# rate-limit-cache.json. Claude Code's Stop hook payload does NOT include
# rate_limits — only the statusline does. So we piggyback on the statusline:
# see settings.json  "statusLine.command": "tee >(... cache) | real-statusline"
# which updates the cache on every statusline refresh (several times per
# second during active use).
#
# We DO NOT chain into watch from here — statusline fires far too often for
# that to be cheap. The launchd agent polls watch every 60s independently.
cmd_cache() {
  python3 "$SELF_DIR/_cache.py"
}

cmd_watch() {
  # _watch.py used to take a `primary` arg for come-home logic; come-home
  # was removed 2026-04-23 for topology-independence. Only self-path now.
  if [ "${1:-}" = "--threshold" ]; then
    # Ask the process that actually enforces it. Reading a number out of this
    # file would just recreate the second source of truth we deleted.
    python3 "$SELF_DIR/_watch.py" --threshold
    return
  fi
  python3 "$SELF_DIR/_watch.py" "$0"
}

# ---- dispatch ----
case "${1:-}" in
  whoami)  shift; cmd_whoami "$@" ;;
  list)    shift; cmd_list "$@" ;;
  switch)  shift; cmd_switch "$@" ;;
  cache)   shift; cmd_cache "$@" ;;
  watch)   shift; cmd_watch "$@" ;;
  ""|-h|--help)
    # Print the INSTALL + SUBCOMMANDS block from this file
    awk '/^# ============================/{if (++n==2 || n==4 || n==6) print; next} n>=1 && n<=6 {print}' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown subcommand: ${1}. Try: $0 --help"
    ;;
esac

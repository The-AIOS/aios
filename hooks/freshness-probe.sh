#!/usr/bin/env bash
# freshness-probe.sh — the /today and /close-day freshness checks, able to tell a refused
# LOGIN from a missing NETWORK.
#
# Why this exists: the checks used to run `git ls-remote … 2>/dev/null` and call any empty
# result `unreachable`, which the commands render as "offline — fine for now". Discarding
# stderr deleted the only evidence that separates the two cases, so a machine whose SSH key
# had been removed from its GitHub account was told "offline, not a problem" every morning.
# A refused credential is a task that does not fix itself; an outage is not.
#
# Usage:
#   freshness-probe.sh                 both checks
#   freshness-probe.sh --aios-update   the framework check only (reads ~/aios/.aios-update)
#   freshness-probe.sh --companies     one line per mounted company with a .{name}-sync tracker
#   freshness-probe.sh --classify      read git error text on stdin → access-denied | unreachable
#
# Output — the same words as before, plus one new state:
#   aios-update: synced | BEHIND (local=… remote=…) | access-denied (why) | unreachable (why) | no-config
#   company-{name}: synced | BEHIND (…) | access-denied (why) | unreachable (why)
# `access-denied` = the server answered and refused the credential. Always exits 0: finding a
# problem is not a failed command. AIOS_ROOT overrides ~/aios (used by the test).
# Guard: tests/freshness-probe.test.sh
set -uo pipefail

ROOT="${AIOS_ROOT:-$HOME/aios}"
ACCESS_RE='Permission denied|Repository not found|could not read Username|Authentication failed'
NET_RE='Could not resolve host|Connection timed out|Operation timed out|Connection refused|Network is unreachable'

classify() {
  local err; err="$(cat)"
  if printf '%s' "$err" | grep -Eq "$ACCESS_RE"; then echo access-denied; else echo unreachable; fi
}

# Quote the reason that matches the CLASS, not the first match of either pattern. Both
# attempts' stderr is accumulated, so on a network where port 22 is blocked and 443 is open
# the SSH error is a network one while the HTTPS error is the refusal that decided the
# classification -- and searching both patterns at once printed
# "access-denied (Connection refused)", a line that contradicts itself.
reason() {  # $1 errs · $2 classification
  local re="$NET_RE"; [ "${2:-}" = access-denied ] && re="$ACCESS_RE"
  printf '%s' "$1" | grep -Eo "$re" | head -1
}

probe() {  # $1 label · $2 repo url · $3 local hash
  local label="$1" repo="$2" h="$3" r="" errs="" e hr cls why
  export GIT_TERMINAL_PROMPT=0
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
  e="$(mktemp)"
  r=$(git ls-remote "$repo" HEAD 2>"$e" </dev/null | awk '{print $1}')
  errs="$(cat "$e")"
  if [ -z "$r" ]; then
    # SSH first, then public HTTPS, so a fresh HTTPS clone with no SSH keys still resolves.
    hr=$(printf '%s' "$repo" | sed -E 's#git@github\.com:#https://github.com/#')
    if [ "$hr" != "$repo" ]; then
      r=$(git ls-remote "$hr" HEAD 2>"$e" </dev/null | awk '{print $1}')
      errs="$errs"$'\n'"$(cat "$e")"
    fi
  fi
  rm -f "$e"
  if [ -n "$r" ]; then
    if [ "$h" = "$r" ]; then echo "$label: synced"; else echo "$label: BEHIND (local=${h:0:7} remote=${r:0:7})"; fi
    return
  fi
  cls=$(printf '%s' "$errs" | classify)
  why=$(reason "$errs" "$cls")
  echo "$label: $cls${why:+ ($why)}"
}

mode="${1:-all}"
case "$mode" in
  --classify) classify; exit 0 ;;
  --aios-update|--companies|all) ;;
  *) echo "usage: freshness-probe.sh [--aios-update|--companies|--classify]" >&2; exit 0 ;;
esac

if [ "$mode" = all ] || [ "$mode" = --aios-update ]; then
  cfg="$ROOT/.aios-update"
  if [ -f "$cfg" ]; then
    probe aios-update "$(grep ^repo= "$cfg" | cut -d= -f2)" "$(grep ^hash= "$cfg" | cut -d= -f2)"
  else
    echo "aios-update: no-config"
  fi
fi

if [ "$mode" = all ] || [ "$mode" = --companies ]; then
  # find, not a glob: an unmatched glob is a hard error in zsh on a day-zero vault.
  find "$ROOT/vault/00 - notes/context/ventures" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort |
  while IFS= read -r venture; do
    name=$(basename "$venture"); tracker="$venture/.$name-sync"
    [ -f "$tracker" ] || continue
    repo=$(grep ^repo= "$tracker" | cut -d= -f2); h=$(grep ^hash= "$tracker" | cut -d= -f2)
    [ -n "$repo" ] || continue
    probe "company-$name" "$repo" "$h" </dev/null
  done
fi
exit 0

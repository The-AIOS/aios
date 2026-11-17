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
#   aios-update: synced | BEHIND (local=… remote=…) | TESTING <branch> (local=… main=…) | access-denied (why) | unreachable (why) | no-config
#   company-{name}: synced | BEHIND (…) | access-denied (why) | unreachable (why)
# `TESTING` = the tracker's `ref=` names a branch other than the default one that still exists on
# the remote: the vault is testing it, AHEAD or beside main, never behind it. Updating would
# pull main and undo the test, so callers must not auto-update on it (measured: a dogfooded release
# branch read as BEHIND and the App offered an update that would have rolled it back).
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

probe() {  # $1 label · $2 repo url · $3 local hash · $4 tracker ref (optional)
  local label="$1" repo="$2" h="$3" ref="${4:-}" r="" refs="" errs="" e hr cls why
  export GIT_TERMINAL_PROMPT=0
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
  e="$(mktemp)"
  # All refs, not only HEAD: a ref= branch counts only while it still exists there.
  refs=$(git ls-remote "$repo" 2>"$e" </dev/null); r=$(printf '%s\n' "$refs" | awk '$2=="HEAD"{print $1}')
  errs="$(cat "$e")"
  if [ -z "$r" ]; then
    # SSH first, then public HTTPS, so a fresh HTTPS clone with no SSH keys still resolves.
    hr=$(printf '%s' "$repo" | sed -E 's#git@github\.com:#https://github.com/#')
    if [ "$hr" != "$repo" ]; then
      refs=$(git ls-remote "$hr" 2>"$e" </dev/null); r=$(printf '%s\n' "$refs" | awk '$2=="HEAD"{print $1}')
      errs="$errs"$'\n'"$(cat "$e")"
    fi
  fi
  rm -f "$e"
  if [ -n "$r" ]; then
    local ref_live=""
    # TESTING comes ONLY from an explicit ref= whose branch still exists on the remote we just
    # listed. Never inferred from "this hash is some branch's tip": a branch cut from main sits on
    # a main commit, and a normal user synced there would read TESTING instead of BEHIND and stop
    # updating. A merged and deleted branch falls through to BEHIND/synced. (Offline never reaches
    # here -- an empty listing is reported as unreachable.)
    [ -n "$ref" ] && printf '%s\n' "$refs" | awk -v r="refs/heads/$ref" '$2==r{f=1} END{exit !f}' && ref_live=1
    if [ "$h" = "$r" ]; then echo "$label: synced"
    elif [ -n "$ref_live" ] && [ "$ref" != main ] && [ "$ref" != master ] && [ "$ref" != HEAD ]; then
      echo "$label: TESTING $ref (local=${h:0:7} main=${r:0:7})"
    else echo "$label: BEHIND (local=${h:0:7} remote=${r:0:7})"; fi
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
    # tr -d '\r': a tracker written with CRLF endings (Windows) must not carry the CR into the value.
    probe aios-update "$(grep ^repo= "$cfg" | cut -d= -f2 | tr -d '\r')" "$(grep ^hash= "$cfg" | cut -d= -f2 | tr -d '\r')" "$(grep ^ref= "$cfg" | cut -d= -f2 | tr -d '\r')"
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

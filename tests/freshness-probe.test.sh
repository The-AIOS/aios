#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# freshness-probe.sh reports a REFUSED credential as `access-denied`, never as
# `unreachable` — and still reports a real outage as `unreachable`.
#
# The inline probes this replaced ran `git ls-remote … 2>/dev/null`, so "GitHub
# refused this machine's key" and "no network" printed the same empty result,
# and /today rendered both as "offline — fine for now". An operator whose key
# had been removed from their GitHub account was reassured every morning.
#
# Runs with NO network: a stub `git` on PATH prints the exact strings git emits
# (SSH "Permission denied (publickey)", HTTPS "Repository not found", a DNS
# failure). THE CONTROL re-runs the old inline probe against the same stub and
# asserts it prints `unreachable` for the refused repo — the defect, reproduced
# — so the suite demonstrably separates the two behaviours. Keep the control.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
expect(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$3', got '$2'"; fi; }
S=hooks/freshness-probe.sh
[ -f "$S" ] || { echo "::error::$S missing"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "-- the classifier, on the strings git actually prints --"
expect "ssh key refused"   "$(printf 'git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.\n' | bash "$S" --classify)" access-denied
expect "https repo hidden" "$(printf "remote: Repository not found.\nfatal: repository 'https://github.com/o/r.git/' not found\n" | bash "$S" --classify)" access-denied
expect "https no creds"    "$(printf "fatal: could not read Username for 'https://github.com': terminal prompts disabled\n" | bash "$S" --classify)" access-denied
expect "dns failure"       "$(printf "fatal: unable to access 'https://x/': Could not resolve host: x\n" | bash "$S" --classify)" unreachable
expect "no error text"     "$(printf '' | bash "$S" --classify)" unreachable

# The reason must match the CLASS, not the first pattern that hits. Both attempts' stderr is
# accumulated, so on a network with port 22 blocked and 443 open the SSH error is a network
# one while the HTTPS refusal is what decided the classification. Searching both patterns at
# once printed "access-denied (Connection refused)" -- a line that contradicts itself and
# sends the operator to check their wifi over a credential problem.
echo "-- the quoted reason agrees with the classification --"
BOTH=$(printf 'ssh: connect to host github.com port 22: Connection refused\nfatal: could not read Username for '"'"'https://github.com'"'"': terminal prompts disabled\n')
cls=$(printf '%s' "$BOTH" | bash "$S" --classify)
[ "$cls" = access-denied ] && ok "mixed network+refusal classifies as access-denied" \
  || no "mixed errors classified '$cls'" "the server answered and refused; that is the actionable half"
# extract the shipped reason() and run it, rather than restating its regexes here
eval "$(sed -n '/^ACCESS_RE=/p;/^NET_RE=/p' "$S")"
eval "$(sed -n '/^reason() {/,/^}/p' "$S")"
got=$(reason "$BOTH" access-denied)
printf '%s' "$got" | grep -Eq "$ACCESS_RE" \
  && ok "access-denied quotes the refusal ($got)" \
  || no "access-denied quoted '$got'" "quoting a network error beside access-denied contradicts itself"
got2=$(reason "$BOTH" unreachable)
printf '%s' "$got2" | grep -Eq "$NET_RE" \
  && ok "unreachable quotes the network error ($got2)" \
  || no "unreachable quoted '$got2'"

echo "-- end to end: stub git, a fake root --"
V="$T/root/vault/00 - notes/context/ventures"
mkdir -p "$T/bin" "$V/acme" "$V/beta" "$V/gamma"
cat > "$T/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *denied*)  echo "git@github.com: Permission denied (publickey)." >&2; exit 128 ;;
  *offline*) echo "fatal: unable to access 'https://offline.invalid/': Could not resolve host: offline.invalid" >&2; exit 128 ;;
  *fresh*)   printf 'abc1234000000000000000000000000000000000\tHEAD\n' ;;
esac
STUB
chmod +x "$T/bin/git"
printf 'repo=git@github.com:acme/denied.git\nhash=abc\n' > "$V/acme/.acme-sync"
printf 'repo=https://example.invalid/fresh.git\nhash=abc1234000000000000000000000000000000000\n' > "$V/beta/.beta-sync"
printf 'repo=https://offline.invalid/gamma.git\nhash=abc\n' > "$V/gamma/.gamma-sync"
printf 'repo=https://offline.invalid/aios.git\nhash=abc\n' > "$T/root/.aios-update"
out="$(PATH="$T/bin:$PATH" AIOS_ROOT="$T/root" bash "$S")"
field(){ printf '%s\n' "$out" | grep "^$1:" | cut -d' ' -f2; }
expect "refused company → access-denied" "$(field company-acme)"  access-denied
expect "healthy company → synced"        "$(field company-beta)"  synced
expect "offline company → unreachable"   "$(field company-gamma)" unreachable
expect "offline framework → unreachable" "$(field aios-update)"   unreachable
expect "the refusal is named"            "$(printf '%s\n' "$out" | grep -c '^company-acme: access-denied (Permission denied)$')" 1

echo "-- modes --"
expect "--aios-update prints one line" "$(PATH="$T/bin:$PATH" AIOS_ROOT="$T/root" bash "$S" --aios-update | wc -l | tr -d ' ')" 1
expect "--companies prints three"      "$(PATH="$T/bin:$PATH" AIOS_ROOT="$T/root" bash "$S" --companies | wc -l | tr -d ' ')" 3
expect "no tracker → no-config"        "$(AIOS_ROOT="$T/empty" bash "$S" --aios-update)" "aios-update: no-config"
PATH="$T/bin:$PATH" AIOS_ROOT="$T/root" bash "$S" >/dev/null; expect "exit 0 even when a check fails" "$?" 0

echo "-- CONTROL: the old inline probe hides the refusal --"
old="$(PATH="$T/bin:$PATH"; repo=git@github.com:acme/denied.git
  r=$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1}')
  [ -z "$r" ] && { hr=$(echo "$repo" | sed -E 's#git@github\.com:#https://github.com/#'); r=$(git ls-remote "$hr" HEAD 2>/dev/null | awk '{print $1}'); }
  [ -z "$r" ] && echo unreachable || echo reachable)"
expect "the stock probe calls a refused key 'unreachable'" "$old" unreachable

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

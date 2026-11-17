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
S=hooks/pipeline/freshness-probe.sh
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
printf '%s' "$got" | grep -E "$ACCESS_RE" >/dev/null \
  && ok "access-denied quotes the refusal ($got)" \
  || no "access-denied quoted '$got'" "quoting a network error beside access-denied contradicts itself"
got2=$(reason "$BOTH" unreachable)
printf '%s' "$got2" | grep -E "$NET_RE" >/dev/null \
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

echo "-- a vault on a test branch is TESTING (ahead), never BEHIND --"
# Measured: a release dogfooded from its branch read as BEHIND, and the App offered an update
# that would have pulled main over the test.
TB="$(mktemp -d)"
git init -q --bare "$TB/remote.git"
git -C "$TB" init -q w 2>/dev/null || git init -q "$TB/w"
git -C "$TB/w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
DEF=$(git -C "$TB/w" branch --show-current); MAIN=$(git -C "$TB/w" rev-parse HEAD)
git -C "$TB/w" checkout -q -b rel
git -C "$TB/w" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
TIP=$(git -C "$TB/w" rev-parse HEAD)
git -C "$TB/w" push -q "$TB/remote.git" "$DEF" rel 2>/dev/null
git -C "$TB/remote.git" symbolic-ref HEAD "refs/heads/$DEF"
mkdir -p "$TB/v"
tracker(){ printf 'repo=%s\nhash=%s\n' "$TB/remote.git" "$1" > "$TB/v/.aios-update"; [ -n "${2:-}" ] && printf 'ref=%s\n' "$2" >> "$TB/v/.aios-update"; :; }
run(){ AIOS_ROOT="$TB/v" bash "$S" --aios-update; }
tracker "$MAIN"; expect "on the default branch's head: synced" "$(run)" "aios-update: synced"
tracker "$TIP"; out=$(run); case "$out" in "aios-update: BEHIND "*) ok "another branch's tip WITHOUT ref= reads BEHIND (TESTING is never inferred)" ;; *) no "TESTING inferred from a branch tip: $out" ;; esac
tracker "$TIP" rel; out=$(run); case "$out" in "aios-update: TESTING rel "*) ok "the same tip WITH ref=rel reads TESTING rel" ;; *) no "explicit ref= on a branch tip read as: $out" ;; esac
tracker 0123456789012345678901234567890123456789 rel; out=$(run); case "$out" in "aios-update: TESTING rel "*) ok "ref= names the test even after the branch moved" ;; *) no "ref= ignored: $out" ;; esac
printf 'repo=%s\r\nhash=0123456789012345678901234567890123456789\r\nref=rel\r\n' "$TB/remote.git" > "$TB/v/.aios-update"
out=$(run); case "$out" in "aios-update: TESTING rel (local="*) ok "a CRLF tracker's ref= still names the branch" ;; *) no "CRLF ref= read as: $(printf '%s' "$out" | od -c | head -2)" ;; esac
tracker 0123456789012345678901234567890123456789 gone; out=$(run); case "$out" in "aios-update: BEHIND "*) ok "ref= naming a branch deleted from the remote is not TESTING" ;; *) no "a deleted ref branch pinned the state: $out" ;; esac
git -C "$TB/remote.git" branch -q -D rel
tracker 0123456789012345678901234567890123456789 rel; out=$(run); case "$out" in "aios-update: BEHIND "*) ok "after the test branch is merged+deleted, ref= falls through to BEHIND" ;; *) no "stuck after deletion: $out" ;; esac
tracker "$MAIN" rel; expect "ref= of a deleted branch on main's head: synced" "$(run)" "aios-update: synced"
tracker 0123456789012345678901234567890123456789 rel; out=$(PATH="$T/bin:$PATH" AIOS_ROOT="$TB/v" bash -c 'sed -i.bak "s#^repo=.*#repo=https://offline.invalid/x.git#" "$AIOS_ROOT/.aios-update"; bash "$0" --aios-update' "$S"); case "$out" in "aios-update: unreachable"*) ok "offline with ref=: unreachable, not a guess" ;; *) no "offline ref= read as: $out" ;; esac
tracker 0123456789012345678901234567890123456789; out=$(run); case "$out" in "aios-update: BEHIND "*) ok "control: an old default-branch hash still reads BEHIND" ;; *) no "control broke: $out" ;; esac
tracker 0123456789012345678901234567890123456789 main; out=$(run); case "$out" in "aios-update: BEHIND "*) ok "ref=main is not a test" ;; *) no "ref=main read as: $out" ;; esac
rm -rf "$TB"
grep -F '`TESTING <branch>`' plugins/aios/commands/today.md >/dev/null && grep -F 'Never auto-fire' plugins/aios/commands/today.md >/dev/null \
  && ok "/today renders TESTING and never auto-updates on it" || no "/today has no TESTING rule"
grep -F 'TESTING <branch>' plugins/aios/commands/close-day.md >/dev/null && ok "/close-day renders TESTING" || no "/close-day has no TESTING rule"
grep -F 'delete any `ref=` line' plugins/aios/commands/update.md >/dev/null && ok "/aios:update clears ref= when it syncs the default branch" || no "update never clears ref="

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

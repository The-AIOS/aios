#!/usr/bin/env bash
# Regression test for install-wrappers.sh → detect_primary_session.
#
# This function writes a name into the operator's shell rc, so a wrong answer is not a crash —
# it silently redefines a function they type every day. Two real incidents shaped it:
#   1. It scraped USER.md's EXAMPLE row and wrote `*buddy*` into the rc; zsh globs it, so every
#      new terminal errored on startup, from an installer reporting success.
#   2. The validator added to fix (1) allowed lowercase only, so an operator whose session is
#      `ALI` had their months-old `ALI()` silently renamed to `aios()` on update. Same shape:
#      a check that substitutes a different answer and reports success.
# Both are "the check reads/permits the wrong thing" — see antifragile #88. Hence: every case
# below asserts BOTH that valid names survive AND that hostile ones are still rejected. A guard
# that only ever returns the fallback would pass a one-sided test while protecting nothing.
#
# Canonical-only (Tier 0 — never synced to operator vaults). Run:  bash tests/install-wrappers.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/hooks/claude-identity/install-wrappers.sh"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

[ -f "$SRC" ] || { echo "::error::missing $SRC"; exit 1; }

# Extract ONLY the function under test — sourcing the whole installer would rewrite this
# machine's shell rc as a side effect of running the tests.
FN=$(awk '/^detect_primary_session\(\)/,/^}/' "$SRC")
[ -n "$FN" ] || { echo "::error::could not extract detect_primary_session from $SRC"; exit 1; }
eval "$FN"

# detect_primary_session reads $HOME/aios/USER.md — point HOME at a throwaway per case.
run_with_identity() { # $1 = the raw cell to put in the Identity table's Name column
  local tmp; tmp=$(mktemp -d); mkdir -p "$tmp/aios"
  printf '## Identity\n\n| Name | Role |\n|------|------|\n| %s | primary |\n\n## Settings\n' "$1" > "$tmp/aios/USER.md"
  ( HOME="$tmp" detect_primary_session ) 2>/dev/null
  rm -rf "$tmp"
}

echo "── accepted: valid session-name shapes survive ──"
for n in buddai sarah app-walker ALI Ali a1 x9-y; do
  got=$(run_with_identity "$n")
  [ "$got" = "$n" ] && ok "'$n' preserved" || no "'$n' → '$got' (should survive)"
done

echo "── rejected: anything that could reach a shell as syntax falls back to aios ──"
# NOTE the pairing: if these ever start passing through, the fix above went too wide.
# Deliberately NOT tested here: a backtick (the parser strips those — they're markdown code
# formatting, `| \`buddai\` |` is the vault's own table style) and a raw pipe (that IS the column
# separator, so it cannot occur inside a cell). Both are parser-layer, not validator-layer.
for n in '*buddy*' '_example_' 'my name' 'a;b' 'a$(id)' "a'b" '-lead' 'lead-' '$HOME'; do
  got=$(run_with_identity "$n")
  [ "$got" = "aios" ] && ok "'$n' rejected → aios" || no "'$n' → '$got' (should have fallen back)"
done

echo "── the fallback announces itself (silent substitution is the bug, not the fallback) ──"
# Use a name that SURVIVES the parser but FAILS the validator. An emphasis row is skipped upstream
# as an example, so nothing is ever rejected there — and silence is correct in that case.
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| my name | primary |\n' > "$tmp/aios/USER.md"
msg=$( { HOME="$tmp" detect_primary_session >/dev/null; } 2>&1 )
rm -rf "$tmp"
echo "$msg" | grep 'using "aios"' >/dev/null && ok "rejection is reported on stderr" || no "fell back SILENTLY — the operator can only notice by missing their function"

echo "── but an EXAMPLE row is skipped upstream, so it must NOT announce a rejection ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | EXAMPLE |\n' > "$tmp/aios/USER.md"
msg=$( { HOME="$tmp" detect_primary_session >/dev/null; } 2>&1 )
rm -rf "$tmp"
[ -z "$msg" ] && ok "example row → silent fallback (nothing was rejected)" || no "announced a rejection that never happened: $msg"

echo "── the announcement must not corrupt the return value (stdout is the name) ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | primary |\n' > "$tmp/aios/USER.md"
out=$( HOME="$tmp" detect_primary_session 2>/dev/null )
rm -rf "$tmp"
[ "$out" = "aios" ] && ok "stdout is exactly 'aios', message went to stderr" || no "stdout polluted: '$out'"

echo "── example rows are skipped, real rows below them win ──"
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
printf '## Identity\n\n| Name | Role |\n|------|------|\n| *buddy* | EXAMPLE |\n| `ALI` | primary |\n' > "$tmp/aios/USER.md"
out=$( HOME="$tmp" detect_primary_session 2>/dev/null )
rm -rf "$tmp"
[ "$out" = "ALI" ] && ok "emphasis row skipped, backticked uppercase row used" || no "got '$out', expected ALI"

echo ""
echo "── --effort / --advisor reach the claude command line (and nothing when omitted) ──"
# The REAL spawn + launcher functions against a stand-in claude that records its arguments.
tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin"
# It also copies any --settings file it is handed: the launcher deletes that file when the session
# ends, so reading it after spawn returns would find nothing.
cat > "$tmp/bin/claude" <<STUB
#!/bin/sh
printf "%s\\n" "\$@" > "$tmp/args"
prev=""; for a in "\$@"; do [ "\$prev" = "--settings" ] && cat "\$a" > "$tmp/settings" && printf "%s" "\$a" > "$tmp/settings-path"; prev="\$a"; done
exit 0
STUB
chmod +x "$tmp/bin/claude"
FNS=$( for f in _aios_tmp_dir _spawn_clean_files _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
runspawn(){ env -u CLAUDECODE -u AIOS_GLASS_TERM -u CLAUDE_EFFORT -u CLAUDE_ADVISOR_MODEL HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" "$@" >/dev/null 2>&1; }
rm -f "$tmp/args"; runspawn --effort low --advisor scale worker "task"
A=$(cat "$tmp/args" 2>/dev/null)
printf '%s\n' "$A" | grep -x -- '--effort' >/dev/null && printf '%s\n' "$A" | grep -x low >/dev/null && ok "--effort low reaches claude as --effort low" || no "--effort did not reach claude" "$A"
SET=$(printf '%s\n' "$A" | grep -A1 -x -- '--settings' | tail -1)
[ -n "$SET" ] && grep -q '"advisorModel":"claude-sonnet-5-5"' "$tmp/settings" 2>/dev/null && ok "--advisor scale reaches claude as a settings file naming claude-sonnet-5-5" || no "--advisor did not reach claude" "settings: $SET"
[ -n "$SET" ] && [ ! -e "$SET" ] && ok "the advisor settings file is deleted when the session exits" || no "advisor settings file left behind" "$SET"
rm -f "$tmp/args" "$tmp/settings"; runspawn --advisor claude-opus-5-5 worker "task"
SET=$(grep -A1 -x -- '--settings' "$tmp/args" 2>/dev/null | tail -1)
[ -n "$SET" ] && grep -q '"advisorModel":"claude-opus-5-5"' "$tmp/settings" && ok "--advisor <model id> is passed through as given" || no "--advisor model id not passed"
# The launcher validates too: an inbox request or a hand-set env var reaches it without spawn().
rm -f "$tmp/args" "$tmp/settings"
out=$( env -u CLAUDECODE CLAUDE_ADVISOR_MODEL='x","permissions":{"allow":["Bash"]},"y":"' HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; _claude_with_respawn worker ""' _ "$FNS" 2>&1 )
[ -f "$tmp/args" ] && ! grep -x -- '--settings' "$tmp/args" >/dev/null && case "$out" in *"not a model id"*) true ;; *) false ;; esac \
  && ok "_claude_with_respawn refuses an advisor id that would inject settings JSON (starts without one)" || no "launcher wrote an unvalidated advisor id into settings JSON" "$out"
ls "$tmp"/aios-advisor-* >/dev/null 2>&1 && no "a refused advisor still left a settings file" || ok "no advisor settings file left in TMPDIR"
rm -f "$tmp/args"; runspawn worker "task"
grep -x -- '--effort\|--settings' "$tmp/args" >/dev/null 2>&1 && no "a spawn without the flags passed --effort or --settings" || ok "without the flags, no --effort and no --settings (byte-identical to before)"
out=$( env -u CLAUDECODE HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn --effort ultra worker task' _ "$FNS" 2>&1 ); rc=$?
[ "$rc" != 0 ] && case "$out" in *"unknown --effort"*) true ;; *) false ;; esac && ok "an unknown --effort is refused, naming the flag" || no "--effort ultra not refused (rc=$rc)" "$out"
RT="$tmp/.aios/tmp"
runspawn --tier scale --advisor judgment advw "task" >/dev/null 2>&1
grep -q 'You have an advisor' "$RT"/spawn-task-advw.* 2>/dev/null && ok "an advised scale worker gets the consult instruction" || no "advised scale worker has no consult instruction"
runspawn --advisor frontier advj "task" >/dev/null 2>&1
ls "$RT"/spawn-task-advj.* >/dev/null 2>&1 && ! grep -q 'You have an advisor' "$RT"/spawn-task-advj.* && ok "an advised judgment worker does not (it lowers Opus pass rates)" || no "judgment worker got the consult instruction, or no task file"
grep -q "spawnModel -match 'sonnet|haiku'" "$(dirname "$SRC")/install-wrappers.ps1" && ok "ps1 gates the consult instruction the same way" || no "ps1 consult gate missing"
out=$( env -u CLAUDECODE HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn --advisor '"'"'x","permissions":{"allow":["Bash"]},"y":"'"'"' worker task' _ "$FNS" 2>&1 ); rc=$?
[ "$rc" != 0 ] && case "$out" in *"not a rung or a model id"*) true ;; *) false ;; esac && ok "an --advisor that would inject settings JSON is refused" || no "--advisor with JSON characters accepted (rc=$rc)" "$out"
rm -rf "$tmp"

echo ""
echo "── --profile: an unknown profile fails in spawn(), before any launcher exists ──"
# Validate in spawn(), not in the launcher: a typo'd profile must not open a worker with
# the full default MCP set (which would read as the flag being ignored). Extract only the
# functions the refusal path needs — the installer wraps them in a heredoc, so a line-range
# grab would drag the installer's own machinery in with them.
tmp=$(mktemp -d); mkdir -p "$tmp/aios"
FNS=$( for f in _aios_tmp_dir _spawn_clean_files _spawn_adj_animal spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
out=$( HOME="$tmp" bash -c 'eval "$1"; spawn --profile nope worker "task"' _ "$FNS" 2>&1 ); rc=$?
[ "$rc" != "0" ] && ok "unknown --profile → non-zero exit" || no "unknown --profile exited 0 (a worker would have opened with the default MCP set)"
case "$out" in *"unknown --profile"*) ok "unknown --profile names the flag in its refusal" ;; *) no "refusal does not mention --profile: $out" ;; esac
if ls "$tmp/.aios/tmp"/spawn-launch-worker.* >/dev/null 2>&1; then
  no "a launcher was written for a spawn that should have been refused"
else
  ok "no launcher was written for the refused spawn"
fi
rm -rf "$tmp"

echo "── --profile: the mechanism is wired end to end (static) ──"
grep -q 'CLAUDE_MCP_PROFILE' "$SRC" && ok "launcher exports CLAUDE_MCP_PROFILE for the spawn" || no "CLAUDE_MCP_PROFILE never exported"
grep -q -- '--strict-mcp-config --mcp-config' "$SRC" && ok "_claude_with_respawn passes --strict-mcp-config + --mcp-config" || no "the strict flag pair is missing"
grep -q '"${mcp_args\[@\]}"' "$SRC" && ok "mcp_args reach the claude invocation" || no "mcp_args built but never passed"

echo "── -Effort / -Advisor: the Windows twin is wired end to end (static; the Windows lane runs it) ──"
PS1="$(dirname "$SRC")/install-wrappers.ps1"
grep -q "ValidateSet('low','medium','high','xhigh','max')\] \[string\] \$Effort" "$PS1" && ok "ps1 spawn validates -Effort to the five levels" || no "ps1 -Effort missing or unvalidated"
grep -q "\$effortArgs = @('--effort', \$env:CLAUDE_EFFORT)" "$PS1" && ok "ps1 passes CLAUDE_EFFORT as --effort" || no "ps1 never passes --effort"
grep -q "\$advisorArgs = @('--settings', \$advFile)" "$PS1" && ok "ps1 passes the advisor as a settings file" || no "ps1 never passes the advisor"
grep -q '\$modelArgs + \$effortArgs + \$advisorArgs' "$PS1" && ok "ps1 effort/advisor args reach the claude invocation" || no "ps1 args built but never passed"
grep -q 'CLAUDE_ADVISOR_MODEL = .\$spawnAdvisor' "$PS1" && ok "ps1 new-window path carries the advisor" || no "ps1 new-window path drops the advisor"

echo "── a flag given LAST with no value fails fast (it used to spin the argument loop forever) ──"
# `shift 2` with one argument left fails WITHOUT shifting in bash and zsh, so the loop never ended.
# Each case runs under a watchdog: a hang is reported as a hang, not as a stuck test run.
FNS=$( for f in _aios_tmp_dir _spawn_clean_files _spawn_adj_animal spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
# A stub claude and no CLAUDECODE: if a guard ever regresses, the spawn runs in place against the
# stub instead of opening a real terminal or a real session.
tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { echo "  (skip: $sh not installed)"; continue; }
  for flag in --tier --model --profile --effort --advisor; do
    env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker "$flag" > "$tmp/out" 2>&1 &
    pid=$!; n=0
    while kill -0 "$pid" 2>/dev/null && [ $n -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      no "$sh: spawn worker $flag HANGS (killed after 5s)"
    else
      wait "$pid"; rc=$?
      [ "$rc" != 0 ] && grep -q -- "$flag needs a value" "$tmp/out" && ok "$sh: spawn worker $flag -> rc=$rc with a plain error" || no "$sh: spawn worker $flag -> rc=$rc" "$(cat "$tmp/out")"
    fi
  done
done
rm -rf "$tmp"

echo "── spawn's files live in a private 0700 dir, never under a predictable /tmp name ──"
# A fixed name in a world-writable /tmp can be created first, or symlinked, by another local user:
# they then choose where `cat >` writes, or swap the script Terminal is about to run.
perm(){ ls -ld "$1" 2>/dev/null | cut -c1-10; }
FNS=$( for f in _aios_tmp_dir _spawn_clean_files _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { echo "  (skip: $sh not installed)"; continue; }
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/args"\nenv > "%s/env"\nexit 0\n' "$tmp" "$tmp" > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  RT="$tmp/.aios/tmp"
  env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker "the task" >/dev/null 2>&1
  [ "$(perm "$RT")" = "drwx------" ] && ok "$sh: ~/.aios/tmp is created 0700" || no "$sh: ~/.aios/tmp is $(perm "$RT")"
  tf=$(ls "$RT"/spawn-task-worker.* 2>/dev/null | head -1); lf=$(ls "$RT"/spawn-launch-worker.* 2>/dev/null | head -1)
  [ -n "$tf" ] && [ "$(perm "$tf")" = "-rw-------" ] && grep -q 'the task' "$tf" && ok "$sh: the task file is private (0600) and holds the task" || no "$sh: task file '$tf' $(perm "$tf")"
  [ -n "$lf" ] && [ "$(perm "$lf")" = "-rwx------" ] && grep -q "Read $tf and follow" "$lf" && ok "$sh: the launcher is 0700 and points the worker at that task file" || no "$sh: launcher '$lf' $(perm "$lf")"
  grep -qx "Read $tf and follow the instructions inside." "$tmp/args" 2>/dev/null && ok "$sh: the session is told to read the private task file" || no "$sh: claude was not handed the task file" "$(cat "$tmp/args" 2>/dev/null)"
  grep -qx -- '--name' "$tmp/args" && grep -qx worker "$tmp/args" && ok "$sh: the session keeps its name (--name worker)" || no "$sh: --name worker missing"
  : > "$tmp/args"
  env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker "again" >/dev/null 2>&1
  tf2=$(ls "$RT"/spawn-task-worker.* 2>/dev/null | head -1)
  [ "$(ls "$RT"/spawn-task-worker.* 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && [ "$(ls "$RT"/spawn-launch-worker.* 2>/dev/null | wc -l | tr -d ' ')" = 1 ] \
    && [ "$tf2" != "$tf" ] && grep -q again "$tf2" && grep -qx "Read $tf2 and follow the instructions inside." "$tmp/args" \
    && ok "$sh: a second spawn of the same name succeeds and replaces the first one's files (no pile-up)" || no "$sh: second spawn did not run on fresh files, or files pile up: $(ls "$RT" | tr '\n' ' ')"
  # Cleaning one name never touches another session's files, whatever its name looks like.
  for other in cmd-worker task-worker launch-worker script-worker paste-worker worker-2; do
    for kind in task launch script paste; do : > "$RT/spawn-$kind-$other.KEEPME"; done
  done
  env HOME="$tmp" "$sh" -c 'eval "$1"; _spawn_clean_files worker' _ "$FNS" >/dev/null 2>&1
  [ "$(ls "$RT"/*.KEEPME 2>/dev/null | wc -l | tr -d ' ')" = 24 ] && ok "$sh: cleaning 'worker' leaves sessions named task-worker, launch-worker, ... alone" || no "$sh: cleaning 'worker' removed another session's files: $(ls "$RT" | tr '\n' ' ')"
  rm -f "$RT"/*.KEEPME
  ls "$RT"/spawn-*-worker.* >/dev/null 2>&1 && no "$sh: _spawn_clean_files left files behind" || ok "$sh: _spawn_clean_files removes them (and an empty match is not a zsh error)"
  grep -qx 'CLAUDE_RESPAWN_PROTOCOL=2' "$tmp/env" 2>/dev/null && ok "$sh: the respawn loop announces protocol 2 to _resume.py" || no "$sh: CLAUDE_RESPAWN_PROTOCOL=2 not exported to claude"
  rm -rf "$tmp"
  # A quote in HOME would break the launch command: refused, with a reason.
  tmp=$(mktemp -d); mkdir -p "$tmp/q'h/aios" "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp/q'h" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
  [ "$rc" != 0 ] && case "$out" in *"cannot quote it safely"*) true ;; *) false ;; esac && ok "$sh: a HOME with a quote is refused with a reason" || no "$sh: quoted HOME not refused (rc=$rc): $out"
  rm -rf "$tmp"
  # A symlinked private dir is refused: spawn stops and writes nothing through it.
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin" "$tmp/elsewhere" "$tmp/.aios"; ln -s "$tmp/elsewhere" "$tmp/.aios/tmp"
  printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
  [ "$rc" != 0 ] && [ -z "$(ls -A "$tmp/elsewhere")" ] && case "$out" in *"not a directory you own"*) true ;; *) false ;; esac \
    && ok "$sh: a symlinked ~/.aios/tmp is refused, nothing written through it" || no "$sh: symlinked dir not refused (rc=$rc)" "$out"
  rm -rf "$tmp"
  # A ~/.aios others can write is refused: they could rename tmp away after the check.
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin" "$tmp/.aios"; chmod 777 "$tmp/.aios"
  printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
  [ "$rc" != 0 ] && [ -z "$(ls "$tmp/.aios/tmp" 2>/dev/null)" ] && case "$out" in *"writable by other users"*) true ;; *) false ;; esac \
    && ok "$sh: a group/world-writable ~/.aios is refused" || no "$sh: writable ~/.aios not refused (rc=$rc): $out"
  rm -rf "$tmp"
  # A tmp others could already write is refused, not chmod-ed (their files in it would stay theirs);
  # and on macOS, an ACL granting another account write access is refused although the mode is 0700.
  for case_ in writable acl acl+xattr; do
    tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin" "$tmp/.aios/tmp"; chmod 700 "$tmp/.aios" "$tmp/.aios/tmp"
    printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
    if [ "$case_" = writable ]; then chmod 777 "$tmp/.aios/tmp"
    elif ! chmod +a "everyone allow add_file,delete_child" "$tmp/.aios/tmp" 2>/dev/null; then echo "  (skip: $sh ACL case needs macOS chmod +a)"; rm -rf "$tmp"; continue
    # With an extended attribute too, macOS's ls -ld shows `@`, not `+`: the ACL must still be seen.
    elif [ "$case_" = acl+xattr ]; then xattr -w com.aios.test v "$tmp/.aios/tmp" 2>/dev/null; fi
    out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
    [ "$rc" != 0 ] && [ -z "$(ls "$tmp/.aios/tmp" 2>/dev/null)" ] && case "$out" in *"carries an ACL"*) true ;; *) false ;; esac \
      && ok "$sh: a pre-existing tmp that is $case_ is refused" || no "$sh: $case_ tmp not refused (rc=$rc): $out"
    rm -rf "$tmp"
  done
  # ~/.aios as a symlink to a directory with an ACL: the target is what gets checked.
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin" "$tmp/real/tmp"; chmod 700 "$tmp/real/tmp"; ln -s "$tmp/real" "$tmp/.aios"
  printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  if chmod +a "everyone allow add_file,delete_child" "$tmp/real" 2>/dev/null; then
    out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
    [ "$rc" != 0 ] && [ -z "$(ls "$tmp/real/tmp")" ] && ok "$sh: a symlinked ~/.aios whose target has an ACL is refused" || no "$sh: symlinked ~/.aios with ACL not refused (rc=$rc): $out"
  else
    echo "  (skip: $sh symlinked-parent ACL case needs macOS chmod +a)"
  fi
  rm -rf "$tmp"
  # Any symlinked ~/.aios is refused, even to a clean 0700 directory: its target's parent may be shared.
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin" "$tmp/real/tmp"; chmod 700 "$tmp/real" "$tmp/real/tmp"; ln -s "$tmp/real" "$tmp/.aios"
  printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" PATH="$tmp/bin:$PATH" "$sh" -c 'eval "$1"; shift; spawn "$@"' _ "$FNS" worker task 2>&1 ); rc=$?
  [ "$rc" != 0 ] && [ -z "$(ls "$tmp/real/tmp")" ] && case "$out" in *"is a symlink"*) true ;; *) false ;; esac \
    && ok "$sh: a symlinked ~/.aios is refused outright" || no "$sh: symlinked ~/.aios accepted (rc=$rc): $out"
  rm -rf "$tmp"
done
echo "── the Terminal and IDE launch paths hand over a private launcher that still starts --name <name> ──"
# Stand-ins for osascript, pgrep and the clipboard: the branch runs for real, and the launcher it
# hands to Terminal (or stages for the IDE palette) is then executed against a stub claude.
KFNS=$( for f in _aios_tmp_dir _spawn_clean_files spawn-kill; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
for mode in terminal ide; do
  tmp=$(mktemp -d); mkdir -p "$tmp/aios" "$tmp/bin"; RT="$tmp/.aios/tmp"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/args"\nexit 0\n' "$tmp" > "$tmp/bin/claude"
  # osascript: a -e script is recorded; a script file is recorded AND the palette's staging file it
  # names (f='...') is copied out, since spawn deletes that file as soon as osascript returns.
  cat > "$tmp/bin/osascript" <<OSA
#!/bin/sh
if [ "\$1" = -e ]; then printf "%s\\n" "\$2" >> "$tmp/osa"; exit 0; fi
cat "\$1" >> "$tmp/osa"
f=\$(sed -n "s/.*do shell script \\"f='\\([^']*\\)'.*/\\1/p" "\$1" | head -1)
[ -n "\$f" ] && cat "\$f" > "$tmp/delivered"
exit 0
OSA
  if [ "$mode" = ide ]; then
    printf '#!/bin/sh\ncase "$*" in *"name "*|*"Visual Studio Code"*) exit 0 ;; esac\nexit 1\n' > "$tmp/bin/pgrep"
  else
    printf '#!/bin/sh\ncase "$*" in *"name "*) exit 0 ;; esac\nexit 1\n' > "$tmp/bin/pgrep"
  fi
  printf '#!/bin/sh\ncat >/dev/null\n' > "$tmp/bin/pbcopy"; printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/pbpaste"
  chmod +x "$tmp/bin/"*
  printf '%s\n' "$FNS" > "$tmp/.bashrc"
  env -u AIOS_GLASS_TERM CLAUDECODE=1 SHELL=/bin/bash HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn w1 "the task"' _ "$FNS" >/dev/null 2>&1
  if [ "$mode" = terminal ]; then
    # What Terminal is told to run: the text inside do script "...".
    sed -n 's/.*do script "\(.*\)"$/\1/p' "$tmp/osa" 2>/dev/null | head -1 > "$tmp/delivered"
  else
    ls "$RT"/spawn-paste-w1.* >/dev/null 2>&1 && no "ide: the palette's staging file was left behind" || ok "ide: the palette's staging file is removed after use"
  fi
  dcmd=$(cat "$tmp/delivered" 2>/dev/null)
  case "$dcmd" in "'$RT/spawn-launch-w1."*"'") ok "$mode: what gets run is a quoted private launcher path" ;; *) no "$mode: delivered command is '$dcmd'" ;; esac
  # Run exactly what Terminal / the palette would run, against the stub claude.
  [ -n "$dcmd" ] && env HOME="$tmp" PATH="$tmp/bin:$PATH" sh -c "$dcmd" >/dev/null 2>&1
  grep -qx -- '--remote-control' "$tmp/args" 2>/dev/null && grep -A1 -x -- '--name' "$tmp/args" | tail -1 | grep -x w1 >/dev/null && grep -q "^Read $RT/spawn-task-w1\." "$tmp/args" \
    && ok "$mode: running it starts claude --remote-control --name w1 on the private task file" || no "$mode: the delivered command did not start the session: $(cat "$tmp/args" 2>/dev/null)"
  # spawn-kill with no live process still clears this session's files. Counted with find, one
  # pattern per name, and checked non-zero first so the "after" count cannot pass vacuously.
  count(){ find "$RT" -maxdepth 1 -type f \( -name 'spawn-task-w1.*' -o -name 'spawn-launch-w1.*' -o -name 'spawn-script-w1.*' -o -name 'spawn-paste-w1.*' \) 2>/dev/null | wc -l | tr -d ' '; }
  before=$(count)
  env HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn-kill w1' _ "$KFNS" >/dev/null 2>&1
  after=$(count)
  # (spawn-osascript-<name>.log is a diagnostic log and is kept, as before.)
  [ "$before" -gt 0 ] && [ "$after" = 0 ] && ok "$mode: spawn-kill clears the session's files ($before -> 0)" || no "$mode: spawn-kill left files ($before -> $after): $(ls "$RT" | tr '\n' ' ')"
  rm -rf "$tmp"
done
grep -nE '(^|[^A-Za-z0-9_.])/tmp/(spawn|swap-respawn|resume-prompt|swap-marker)' "$SRC" "$(dirname "$SRC")/_resume.py" >/dev/null \
  && no "a fixed /tmp session-file name is back" "$(grep -nE '(^|[^A-Za-z0-9_.])/tmp/(spawn|swap-respawn|resume-prompt|swap-marker)' "$SRC" "$(dirname "$SRC")/_resume.py")" \
  || ok "no fixed /tmp name left for launcher, task, swap marker or resume prompt"

echo "── the swap-respawn protocol: _resume.py writes, the respawn loop reads, same private dir ──"
# _resume.py needs Python 3.10+; a macOS system python3 can be 3.9, so take uv's when it has to.
PY=""
python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && PY="python3"
[ -z "$PY" ] && command -v uv >/dev/null 2>&1 && UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" uv run --no-project --python '>=3.10' python -c '' >/dev/null 2>&1 \
  && PY="env UV_CACHE_DIR=${TMPDIR:-/tmp}/uv-cache uv run --no-project --python >=3.10 python"
if [ -n "$PY" ]; then
  tmp=$(mktemp -d); mkdir -p "$tmp/bin"; RT="$tmp/.aios/tmp"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/args"\nprintf -- "---\\n" >> "%s/args"\nexit 0\n' "$tmp" "$tmp" > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
  HOME="$tmp" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume; _resume.write_in_place_signal("worker", "sid-123", "PROMPT")' "$(dirname "$SRC")" 2>"$tmp/err" \
    && ok "_resume.py writes the in-place signal" || no "_resume.py could not write the signal" "$(cat "$tmp/err")"
  [ "$(perm "$RT/swap-respawn-worker.flag")" = "-rw-------" ] && [ "$(perm "$RT/resume-prompt-worker.md")" = "-rw-------" ] \
    && ok "signal files are 0600 inside ~/.aios/tmp" || no "signal files: $(ls -l "$RT" 2>&1)"
  FNS=$( for f in _aios_tmp_dir _claude_with_respawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
  env -u CLAUDE_EFFORT -u CLAUDE_ADVISOR_MODEL HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; _claude_with_respawn worker "boot"' _ "$FNS" >/dev/null 2>&1
  second=$(awk 'f{print} /^---$/{f=1}' "$tmp/args")
  printf '%s\n' "$second" | grep -A1 -x -- '--resume' | tail -1 | grep -x 'sid-123' >/dev/null && printf '%s\n' "$second" | grep -x "Read $RT/resume-prompt-worker.md and follow the instructions inside." >/dev/null \
    && ok "the loop picked up the marker and resumed sid-123 with the private resume prompt" || no "the loop did not resume from the private dir" "$(cat "$tmp/args")"
  [ ! -e "$RT/swap-respawn-worker.flag" ] && ok "the loop consumed the marker" || no "marker left behind"
  # A symlink or a foreign file at a signal name is replaced by a fresh file, never written through.
  : > "$tmp/victim"; ln -s "$tmp/victim" "$RT/swap-respawn-worker.flag"
  : > "$tmp/held"; chmod 666 "$tmp/held"; ln "$tmp/held" "$RT/resume-prompt-worker.md"
  HOME="$tmp" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume; _resume.write_in_place_signal("worker", "sid-9", "PROMPT")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
  [ ! -s "$tmp/victim" ] && [ ! -L "$RT/swap-respawn-worker.flag" ] && [ -f "$RT/swap-respawn-worker.flag" ] \
    && ok "_resume.py replaces a symlink at a signal name instead of writing through it" || no "_resume.py followed a planted symlink: $(cat "$tmp/out")"
  [ ! -s "$tmp/held" ] && grep -q PROMPT "$RT/resume-prompt-worker.md" && [ "$(perm "$RT/resume-prompt-worker.md")" = "-rw-------" ] \
    && ok "_resume.py writes a fresh 0600 inode, so a file someone else holds open never sees the prompt" || no "_resume.py reused an existing inode: $(perm "$RT/resume-prompt-worker.md")"
  rm -rf "$tmp"
  # A symlinked ~/.aios/tmp: no snapshot is written anywhere, and the prompt says so.
  tmp=$(mktemp -d); mkdir -p "$tmp/elsewhere" "$tmp/.aios"; ln -s "$tmp/elsewhere" "$tmp/.aios/tmp"
  HOME="$tmp" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
p = _resume.write_swap_marker("worker", "sid", "/nonexistent")
print("path=" + p); print("NOSNAP" if "No pre-swap snapshot" in _resume.build_resume_prompt("worker", "/x", p) else "SNAP")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
  grep -qx 'path=' "$tmp/out" && grep -qx NOSNAP "$tmp/out" && [ -z "$(ls -A "$tmp/elsewhere")" ] \
    && ok "a rejected private dir means no swap snapshot at all, and the resume prompt says so" || no "swap snapshot written through a rejected dir: $(cat "$tmp/out"; ls "$tmp/elsewhere")"
  grep -q 'CLAUDE_RESPAWN_PROTOCOL") == "2"' "$(dirname "$SRC")/_resume.py" && ok "_resume.py stops a session in place only for a protocol-2 loop" || no "_resume.py does not check CLAUDE_RESPAWN_PROTOCOL"
  # A HOME the shell side refuses is refused here too, and no respawn path stops a session first.
  mkdir -p "$tmp/q'h"
  HOME="$tmp/q'h" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
try:
    _resume._private_dir(); print("accepted")
except OSError: print("refused")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
  grep -qx refused "$tmp/out" && [ ! -e "$tmp/q'h/.aios" ] && ok "_resume.py refuses a HOME with a quote, as the shell does" || no "_resume.py accepted a quoted HOME: $(cat "$tmp/out")"
  mkdir -p "$tmp/l/real/tmp"; chmod 700 "$tmp/l/real" "$tmp/l/real/tmp"; ln -s "$tmp/l/real" "$tmp/l/.aios"
  HOME="$tmp/l" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
try:
    _resume._private_dir(); print("accepted")
except OSError: print("refused")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
  grep -qx refused "$tmp/out" && ok "_resume.py refuses a symlinked ~/.aios outright, as the shell does" || no "_resume.py accepted a symlinked ~/.aios: $(cat "$tmp/out")"
  mkdir -p "$tmp/w/.aios"; chmod 777 "$tmp/w/.aios"
  HOME="$tmp/w" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
try:
    _resume._private_dir(); print("accepted")
except OSError: print("refused")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
  grep -qx refused "$tmp/out" && ok "_resume.py refuses a ~/.aios others can write, as the shell does" || no "_resume.py accepted a world-writable ~/.aios: $(cat "$tmp/out")"
  mkdir -p "$tmp/a/.aios/tmp"; chmod 700 "$tmp/a/.aios" "$tmp/a/.aios/tmp"
  if chmod +a "everyone allow add_file,delete_child" "$tmp/a/.aios/tmp" 2>/dev/null; then
    for xa in no yes; do
      [ "$xa" = yes ] && xattr -w com.aios.test v "$tmp/a/.aios/tmp" 2>/dev/null
      HOME="$tmp/a" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
try:
    _resume._private_dir(); print("accepted")
except OSError: print("refused")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
      grep -qx refused "$tmp/out" && ok "_resume.py refuses a tmp with an ACL (xattr too: $xa), as the shell does" || no "_resume.py accepted a tmp with an ACL (xattr: $xa): $(cat "$tmp/out")"
    done
    mkdir -p "$tmp/s/real/tmp"; chmod 700 "$tmp/s/real/tmp"; ln -s "$tmp/s/real" "$tmp/s/.aios"; chmod +a "everyone allow add_file,delete_child" "$tmp/s/real"
    HOME="$tmp/s" $PY -c 'import sys; sys.path.insert(0, sys.argv[1]); import _resume
try:
    _resume._private_dir(); print("accepted")
except OSError: print("refused")' "$(dirname "$SRC")" > "$tmp/out" 2>&1
    grep -qx refused "$tmp/out" && ok "_resume.py checks the ACL of a symlinked ~/.aios's target, as the shell does" || no "_resume.py accepted a symlinked ~/.aios whose target has an ACL: $(cat "$tmp/out")"
  else
    echo "  (skip: Python ACL case needs macOS chmod +a)"
  fi
  # main() for one live session, every side effect stubbed: with a usable private dir it stops the
  # session (the control: the harness reaches os.kill); with a rejected one it never does, on the
  # in-place path (protocol 2) or the legacy path (a loop from before this change).
  cat > "$tmp/probe.py" <<'PROBE'
"""Drive _resume.main() for one fake live session, with every side effect replaced by a recorder.

argv: <hooks/claude-identity dir> <protocol: "2" for an updated loop, "" for a pre-update one>
Prints one line per os.kill(pid, 15) as KILL, and the summary main() prints.
"""
import json, os, sys
sys.path.insert(0, sys.argv[1])
import _resume as r

proto = sys.argv[2]
if len(sys.argv) > 3 and sys.argv[3] == "full-disk":
    def full(path, text):
        raise OSError(28, "No space left on device")
    r._write_private = full
os.makedirs(r.SESSIONS_DIR, exist_ok=True)
with open(os.path.join(r.SESSIONS_DIR, "424242.json"), "w") as f:
    json.dump({"cwd": "/nonexistent"}, f)

r.is_pid_alive = lambda pid: True
r.session_name_from_pid = lambda pid, info=None: "w1"
r.session_id_from_pid = lambda pid, info: "sid-1"
r.tty_for_pid = lambda pid: ""
r.detect_ide = lambda: ""
r.env_var_from_pid = lambda pid, key: {"CLAUDE_RESPAWN_CAPABLE": "1", "CLAUDE_RESPAWN_PROTOCOL": proto}.get(key, "")
r.wait_for_new_claude = lambda name, killed_pid, timeout=8.0: (1, "ok")
r.respawn_session = lambda *a, **k: (True, "stub")
r.time.sleep = lambda s: None
real_kill = os.kill
def kill(pid, sig):
    if pid == 424242 and sig == 15:
        print("KILL")
        return
    return real_kill(pid, sig)
r.os.kill = kill
sys.argv = ["_resume.py"]
r.main()
PROBE
  for proto in 2 ""; do
    lab=${proto:+in-place}; lab=${lab:-legacy}
    h=$(mktemp -d)
    HOME="$h" $PY "$tmp/probe.py" "$(dirname "$SRC")" "$proto" > "$tmp/out" 2>&1
    grep -qx KILL "$tmp/out" && ok "$lab: with a usable private dir, main() does stop the session (control)" || no "$lab: control never reached os.kill: $(cat "$tmp/out")"
    rm -rf "$h"; h=$(mktemp -d); mkdir -p "$h/.aios"; chmod 777 "$h/.aios"
    HOME="$h" $PY "$tmp/probe.py" "$(dirname "$SRC")" "$proto" > "$tmp/out" 2>&1
    ! grep -qx KILL "$tmp/out" && grep -q "not stopped" "$tmp/out" \
      && ok "$lab: with a rejected private dir, main() leaves the session running and says so" || no "$lab: session stopped despite a rejected dir: $(cat "$tmp/out")"
    rm -rf "$h"
    # A usable dir but a failing write (a full disk): the prompt cannot be saved, so no stop either.
    h=$(mktemp -d)
    HOME="$h" $PY "$tmp/probe.py" "$(dirname "$SRC")" "$proto" full-disk > "$tmp/out" 2>&1
    ! grep -qx KILL "$tmp/out" && grep -q "not stopped" "$tmp/out" \
      && ok "$lab: when the resume prompt cannot be written, main() leaves the session running" || no "$lab: session stopped although its prompt was never written: $(cat "$tmp/out")"
    rm -rf "$h"
  done
  rm -rf "$tmp"
else
  echo "  (skip: no Python 3.10+ available)"
fi

echo "── RESULT: $PASS passed, $FAIL failed  (${BASH_VERSION:+bash $BASH_VERSION}${ZSH_VERSION:+zsh $ZSH_VERSION}) ──"
[ "$FAIL" = "0" ] || exit 1

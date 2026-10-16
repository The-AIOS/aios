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
FNS=$( for f in _aios_run_dir _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
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
rm -f "$tmp/.aios/run/spawn-task-advw.md" "$tmp/.aios/run/spawn-task-advj.md"
runspawn --tier scale --advisor judgment advw "task" >/dev/null 2>&1
grep -q 'You have an advisor' "$tmp/.aios/run/spawn-task-advw.md" 2>/dev/null && ok "an advised scale worker gets the consult instruction" || no "advised scale worker has no consult instruction"
runspawn --advisor frontier advj "task" >/dev/null 2>&1
[ -f "$tmp/.aios/run/spawn-task-advj.md" ] && ! grep -q 'You have an advisor' "$tmp/.aios/run/spawn-task-advj.md" && ok "an advised judgment worker does not (it lowers Opus pass rates)" || no "judgment worker got the consult instruction, or no task file"
grep -q "spawnModel -match 'sonnet|haiku'" "$(dirname "$SRC")/install-wrappers.ps1" && ok "ps1 gates the consult instruction the same way" || no "ps1 consult gate missing"
rm -f "$tmp/.aios/run/spawn-task-advw.md" "$tmp/.aios/run/spawn-task-advj.md"
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
FNS=$( for f in _aios_run_dir _spawn_adj_animal spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
out=$( HOME="$tmp" bash -c 'eval "$1"; spawn --profile nope worker "task"' _ "$FNS" 2>&1 ); rc=$?
[ "$rc" != "0" ] && ok "unknown --profile → non-zero exit" || no "unknown --profile exited 0 (a worker would have opened with the default MCP set)"
case "$out" in *"unknown --profile"*) ok "unknown --profile names the flag in its refusal" ;; *) no "refusal does not mention --profile: $out" ;; esac
if [ -e "$tmp/.aios/run/spawn-launch-worker.sh" ]; then
  no "a launcher was written for a spawn that should have been refused"
else
  ok "no launcher was written for the refused spawn"
fi
rm -rf "$tmp"

echo "── spawn/swap scratch files live in a private per-user dir, never at fixed /tmp names ──"
# A fixed name in a shared /tmp can be pre-created by another local user and then executed (the
# launcher, the AppleScript, the pasted launch command) or followed as instructions (the task file,
# the resume prompt) as this user. The files now go to ~/.aios/run (0700, ours); these cases assert
# the move AND that a hostile run dir is refused rather than silently replaced by /tmp.
tmp=$(mktemp -d); mkdir -p "$tmp/bin" "$tmp/aios"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
FNS=$( for f in _aios_run_dir _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
probe="privdir-$$"
env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn "$2" task' _ "$FNS" "$probe" >/dev/null 2>&1
[ -f "$tmp/.aios/run/spawn-task-$probe.md" ] && [ -f "$tmp/.aios/run/spawn-launch-$probe.sh" ] && ok "task file and launcher are written to ~/.aios/run" || no "task file / launcher not in ~/.aios/run" "$(ls -la "$tmp/.aios/run" 2>&1)"
[ ! -e "/tmp/spawn-task-$probe.md" ] && [ ! -e "/tmp/spawn-launch-$probe.sh" ] && ok "nothing is written at the old /tmp names" || no "spawn still wrote to /tmp"
mode=$(stat -c '%a' "$tmp/.aios/run" 2>/dev/null || stat -f '%Lp' "$tmp/.aios/run" 2>/dev/null)  # GNU first: on Linux `stat -f` is filesystem stat and does not fail
[ "$mode" = "700" ] && ok "the run dir is mode 700" || no "run dir mode is $mode, not 700"
grep -q "$tmp/.aios/run/spawn-task-$probe.md" "$tmp/.aios/run/spawn-launch-$probe.sh" && ok "the launcher points the worker at the private task file" || no "launcher does not reference the private task file"
# Control: a run dir that is a symlink (pointing anywhere — here at a world-writable place) is refused.
tmp2=$(mktemp -d); mkdir -p "$tmp2/.aios" "$tmp2/elsewhere" "$tmp2/bin"; cp "$tmp/bin/claude" "$tmp2/bin/"; ln -s "$tmp2/elsewhere" "$tmp2/.aios/run"
out=$( env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp2" TMPDIR="$tmp2" PATH="$tmp2/bin:$PATH" bash -c 'eval "$1"; spawn "$2" task' _ "$FNS" "$probe" 2>&1 ); rc=$?
[ "$rc" != 0 ] && [ -z "$(ls -A "$tmp2/elsewhere")" ] && ok "control: a symlinked run dir is refused and nothing is written through it" || no "symlinked run dir accepted (rc=$rc)" "$out"
[ ! -e "/tmp/spawn-task-$probe.md" ] && ok "control: refusal does not fall back to /tmp" || no "refusal fell back to /tmp"
# The swap loop polls the same private dir; the Python side writes there.
grep -q 'local marker="${run_dir:+$run_dir/swap-respawn-$name.flag}"' "$SRC" && ok "the respawn loop polls the swap marker in the run dir" || no "respawn loop still polls /tmp"
RES="$(dirname "$SRC")/_resume.py"
# _resume.py uses PEP 604 annotations (3.10+); macOS ships 3.9 as python3, so pick one that can import it.
PYR=""; for c in python3.13 python3.12 python3.11 python3.10 python3; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null && { PYR="$c"; break; }
done
if [ -z "$PYR" ]; then
  echo "  - skip: no python >= 3.10 to import _resume.py (its own requirement)"
else
pyout=$( AIOS_RUN_DIR="$tmp/.aios/run" "$PYR" -c '
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.write_in_place_signal("'"$probe"'", "sid-123", "resume prompt")
d = os.environ["AIOS_RUN_DIR"]
print(all(os.path.exists(os.path.join(d, f)) for f in ("swap-respawn-'"$probe"'.flag", "swap-respawn-'"$probe"'.session", "resume-prompt-'"$probe"'.md")))
' "$RES" 2>&1 )
[ "$pyout" = "True" ] && ok "_resume.py writes the swap files to the same run dir" || no "_resume.py did not write to the run dir" "$pyout"
pyout=$( AIOS_RUN_DIR="$tmp2/.aios/run" "$PYR" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
try:
    m.write_in_place_signal("x", "sid", "p"); print("wrote")
except RuntimeError:
    print("refused")
' "$RES" 2>&1 )
[ "$pyout" = "refused" ] && [ -z "$(ls -A "$tmp2/elsewhere")" ] && ok "control: _resume.py refuses a symlinked run dir" || no "_resume.py wrote through a symlinked run dir" "$pyout"
fi
! grep -n '"/tmp/\(spawn\|swap\|resume\)-' "$RES" >/dev/null && ok "_resume.py names no fixed /tmp path" || no "_resume.py still names a fixed /tmp path"
rm -rf "$tmp" "$tmp2"

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
FNS=$( for f in _aios_run_dir _spawn_adj_animal spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
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

echo "── RESULT: $PASS passed, $FAIL failed  (${BASH_VERSION:+bash $BASH_VERSION}${ZSH_VERSION:+zsh $ZSH_VERSION}) ──"
[ "$FAIL" = "0" ] || exit 1

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
FNS=$( for f in _aios_run_dir _aios_handoff_dir _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
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
# --add-dir (#231): under blockReadsOutsideWorkingDirectories a worker cannot read outside its
# working folders, and its task lives under the run dir. The task gets its OWN handoff folder and
# only that folder is granted: the whole run dir would expose every other session's task and the
# launchers the surfaces execute. A folder given to spawn passes through, once.
RUN="$tmp/.aios/run"; adds(){ grep -A1 -x -- '--add-dir' "$tmp/args" 2>/dev/null | grep -v -x -- '--add-dir\|--'; }
H=$(adds | grep "^$RUN/handoff-[0-9a-f]\{16\}$")
[ -n "$H" ] && [ "$(adds | grep -c .)" = 1 ] && ok "a spawn with a task passes --add-dir for ONE handoff folder" || no "the grant is not one handoff folder" "$(adds | tr '\n' ' ')"
adds | grep -q -x "$RUN" && no "the whole run dir was granted" || ok "the run dir itself is never granted"
[ -f "$H/aios-spawn-task-worker.md" ] && ok "the handoff folder holds the worker's task file" || no "no task file in the handoff folder" "$(ls -la "$H" 2>&1)"
HM=$(stat -c '%a' "$H" 2>/dev/null || stat -f '%Lp' "$H" 2>/dev/null); [ "$HM" = 700 ] && ok "the handoff folder is mode 700" || no "handoff folder mode $HM"
NXT=$(grep -A2 -x -- '--add-dir' "$tmp/args" | sed -n 3p); case "$NXT" in --*) ok "--add-dir is followed by a flag, so the prompt is never read as a folder" ;; *) no "--add-dir is followed by '$NXT'" "the flag takes several values; a prompt after it is read as a directory" ;; esac
rm -f "$tmp/args"; mkdir -p "$tmp/extra"; runspawn --add-dir "$tmp/extra" worker "task"
adds | grep -q -x "$tmp/extra" && [ "$(adds | grep -c .)" = 2 ] && ok "a given --add-dir reaches claude beside the handoff folder" || no "a given --add-dir was lost" "$(adds | tr '\n' ' ')"
rm -f "$tmp/args"; runspawn --add-dir "$tmp/extra" --add-dir "$tmp/extra" worker "task"
[ "$(adds | grep -c -x "$tmp/extra")" = 1 ] && ok "a folder given twice arrives once" || no "a given folder was passed twice"
mkdir -p "$RUN/handoff-0000000000000000"; touch -t 202001010000 "$RUN/handoff-0000000000000000"
rm -f "$tmp/args"; runspawn worker "task"
[ ! -e "$RUN/handoff-0000000000000000" ] && ok "a handoff folder older than a day is swept" || no "an old handoff folder survived"
# The Windows twin sweeps %TEMP%, which other programs share: it must match only AIOS's own names.
grep -q "\$_.Name -match '^handoff-\[0-9a-f\]{16}\$'" "$(dirname "$SRC")/install-wrappers.ps1" \
  && ok "Windows: the %TEMP% sweep removes only handoff-<16 hex> folders, never another app's" \
  || no "Windows: the handoff sweep in %TEMP% is not limited to AIOS's own folder names"
rm -f "$tmp/args"
env -u CLAUDECODE -u CLAUDE_ADD_DIRS HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; _claude_with_respawn primary ""' _ "$FNS" >/dev/null 2>&1
[ -f "$tmp/args" ] && [ -z "$(adds)" ] && ok "a launch with no prompt file adds no --add-dir" || no "a plain launch got --add-dir" "$(adds | tr '\n' ' ')"
grep -q 'mv "$run_dir/resume-prompt-$name.md" "$_h/"' "$SRC" && ok "an account-switch resume moves its prompt into a fresh handoff folder" || no "the resume prompt is still read from the run dir itself"
out=$( env -u CLAUDECODE HOME="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn --effort ultra worker task' _ "$FNS" 2>&1 ); rc=$?
[ "$rc" != 0 ] && case "$out" in *"unknown --effort"*) true ;; *) false ;; esac && ok "an unknown --effort is refused, naming the flag" || no "--effort ultra not refused (rc=$rc)" "$out"
runspawn --tier scale --advisor judgment advw "task" >/dev/null 2>&1
grep -q 'You have an advisor' "$tmp"/.aios/run/handoff-*/aios-spawn-task-advw.md 2>/dev/null && ok "an advised scale worker gets the consult instruction" || no "advised scale worker has no consult instruction"
runspawn --advisor frontier advj "task" >/dev/null 2>&1
ADVJ=$(ls "$tmp"/.aios/run/handoff-*/aios-spawn-task-advj.md 2>/dev/null | head -1)
[ -n "$ADVJ" ] && ! grep -q 'You have an advisor' "$ADVJ" && ok "an advised judgment worker does not (it lowers Opus pass rates)" || no "judgment worker got the consult instruction, or no task file"
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
FNS=$( for f in _aios_run_dir _aios_handoff_dir _spawn_adj_animal _spawn_task_preamble _spawn_advisor_block _claude_with_respawn spawn; do sed -n "/^$f() {/,/^}/p" "$SRC"; done )
probe="privdir-$$"
env -u CLAUDECODE -u AIOS_GLASS_TERM HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH" bash -c 'eval "$1"; spawn "$2" task' _ "$FNS" "$probe" >/dev/null 2>&1
PT=$(ls "$tmp"/.aios/run/handoff-*/aios-spawn-task-$probe.md 2>/dev/null | head -1)
[ -n "$PT" ] && [ -f "$tmp/.aios/run/spawn-launch-$probe.sh" ] && ok "task file and launcher are written to ~/.aios/run" || no "task file / launcher not in ~/.aios/run" "$(ls -la "$tmp/.aios/run" 2>&1)"
[ ! -e "/tmp/spawn-task-$probe.md" ] && [ ! -e "/tmp/spawn-launch-$probe.sh" ] && ok "nothing is written at the old /tmp names" || no "spawn still wrote to /tmp"
mode=$(stat -c '%a' "$tmp/.aios/run" 2>/dev/null || stat -f '%Lp' "$tmp/.aios/run" 2>/dev/null)  # GNU first: on Linux `stat -f` is filesystem stat and does not fail
[ "$mode" = "700" ] && ok "the run dir is mode 700" || no "run dir mode is $mode, not 700"
grep -q "$PT" "$tmp/.aios/run/spawn-launch-$probe.sh" && ok "the launcher points the worker at the private task file" || no "launcher does not reference the private task file"
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
# Protocol 2: stop a session in place ONLY for a loop that polls the run dir. A terminal opened
# before the update runs the old loop (polls /tmp, sets only CAPABLE=1); a loop whose run dir
# failed exports no protocol. Both must take the fresh-tab path, or they are stopped with no way back.
pyout=$( "$PYR" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
def env(d): return lambda pid, key: d.get(key, "")
print(m.in_place_capable(1, env({"CLAUDE_RESPAWN_CAPABLE": "1", "CLAUDE_RESPAWN_PROTOCOL": "2"})),
      m.in_place_capable(1, env({"CLAUDE_RESPAWN_CAPABLE": "1"})),
      m.in_place_capable(1, env({"CLAUDE_RESPAWN_PROTOCOL": "2"})))
' "$RES" 2>&1 )
[ "$pyout" = "True False False" ] && ok "in place only for a protocol-2 loop" || no "in-place decision wrong" "$pyout"
pyout=$( "$PYR" -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
def env(d): return lambda pid, key: d.get(key, "")
print(m.swap_mode(1, env({"CLAUDE_RESPAWN_CAPABLE": "1", "CLAUDE_RESPAWN_PROTOCOL": "2"})),
      m.swap_mode(1, env({"CLAUDE_RESPAWN_CAPABLE": "1"})),
      m.swap_mode(1, env({})))
' "$RES" 2>&1 )
[ "$pyout" = "in-place leave-running fresh-tab" ] && ok "an old or run-dir-less loop is left running; only a loop-less session gets a fresh tab" || no "swap_mode wrong" "$pyout"

# What the loop DOES after a swap, not only which path is chosen. A REAL respawn loop whose run dir
# is unusable exports CAPABLE=1 and no protocol, exactly like a terminal opened before the update:
# it cannot see the swap marker, so a stopped claude reads as a crash and it starts another one by
# itself (read -t 60 returns at once on a closed stdin here, standing in for the 60s timeout).
# _resume.main() runs for real against it, with only the OS-facing edges stubbed: the process env
# is read from a file the stand-in claude writes (ps -E is macOS-only), and no tab is opened.
t3=$(mktemp -d); mkdir -p "$t3/bin" "$t3/aios" "$t3/.aios" "$t3/elsewhere" "$t3/sessions"; ln -s "$t3/elsewhere" "$t3/.aios/run"
cat > "$t3/bin/claude" <<STUB
#!/bin/sh
echo start >> "$t3/starts"
env > "$t3/env"
sleep 30 & sp=\$!
trap 'kill \$sp; exit 143' TERM
echo \$\$ > "$t3/pid"
wait
STUB
chmod +x "$t3/bin/claude"
env -u CLAUDECODE -u AIOS_RUN_DIR -u CLAUDE_RESPAWN_PROTOCOL HOME="$t3" PATH="$t3/bin:$PATH" bash -c 'eval "$1"; _claude_with_respawn rprobe' _ "$FNS" </dev/null >"$t3/loop.out" 2>&1 &
loop=$!
i=0; while [ ! -s "$t3/pid" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
cpid=$(cat "$t3/pid" 2>/dev/null)
printf '{"cwd":"%s","sessionId":"sid-rprobe","name":"rprobe"}' "$t3/aios" > "$t3/sessions/$cpid.json"
# _resume.py gets a WORKING run dir unless a case says otherwise: only the loop's must be broken
# (that is what makes it an old-shape loop), or main() would never reach the stop it is tested on.
runresume(){ AIOS_RUN_DIR="${2:-$t3/run-ok}" "$PYR" - "$RES" "$t3" "$1" <<'PY'
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
t3, extra = sys.argv[2], sys.argv[3]
def read(pid, key):
    env = dict(l.rstrip("\n").split("=", 1) for l in open(os.path.join(t3, "env")) if "=" in l)
    if extra:
        env.update(dict([extra.split("=", 1)]))
    return env.get(key, "")
m.env_var_from_pid = read
m.SESSIONS_DIR = os.path.join(t3, "sessions")
m.detect_ide = lambda: ""
m.POST_SWAP_WAIT_SECS = 0
m.respawn_session = lambda *a: (True, "stub tab")
m.wait_for_new_claude = lambda *a, **k: (0, "stub")
m.main()
PY
}
grep -q '^CLAUDE_RESPAWN_CAPABLE=1$' "$t3/env" && ! grep -q '^CLAUDE_RESPAWN_PROTOCOL=' "$t3/env" \
  && ok "setup: the loop runs claude as an old terminal would (CAPABLE=1, no protocol)" || no "setup: loop env is not the old-terminal shape" "$(grep RESPAWN "$t3/env")"
out=$(runresume "" 2>&1)
sleep 3
case "$out" in *"left running"*) ok "_resume.main() leaves the old-loop session running" ;; *) no "old-loop session was not left running" "$out" ;; esac
kill -0 "$cpid" 2>/dev/null && [ "$(grep -c start "$t3/starts")" = 1 ] \
  && ok "after the swap the loop still has ONE claude, the original" || no "the loop restarted or lost claude" "starts=$(grep -c start "$t3/starts")"
# A protocol-2 loop with an unusable run dir: the run dir is checked BEFORE anything is stopped,
# and the failure leaves the session running instead of aborting the restart of every other one.
out=$(runresume "CLAUDE_RESPAWN_PROTOCOL=2" "$t3/.aios/run" 2>&1); rc=$?
[ "$rc" = 0 ] && case "$out" in *"private run dir unusable"*"left running"*) true ;; *) false ;; esac \
  && kill -0 "$cpid" 2>/dev/null && ok "an unusable run dir leaves the session running, and main() does not crash" || no "unusable run dir mishandled (rc=$rc)" "$out"
# Control: stop that claude the way the fresh-tab path does, and the loop starts a second claude
# under the same name -- the duplicate this guards against, and proof the count above can see it.
kill -TERM "$cpid" 2>/dev/null
i=0; while [ "$(grep -c start "$t3/starts")" -lt 2 ] && [ $i -lt 60 ]; do sleep 0.1; i=$((i+1)); done
[ "$(grep -c start "$t3/starts")" = 2 ] && grep -q 'exited with code 143' "$t3/loop.out" \
  && ok "control: stopping claude under an old loop makes it start a duplicate (exit 143 read as a crash)" || no "control: the old loop did not restart" "$(cat "$t3/loop.out")"
kill "$loop" 2>/dev/null; pkill -TERM -f "$t3/bin/claude" 2>/dev/null; wait "$loop" 2>/dev/null
fi
grep -q 'if \[ -n "$run_dir" \]; then export CLAUDE_RESPAWN_PROTOCOL=2; else unset CLAUDE_RESPAWN_PROTOCOL; fi' "$SRC" \
  && ok "the loop announces protocol 2 only when its run dir works" || no "the loop does not gate protocol 2 on its run dir"
grep -q 'mode = swap_mode(pid)' "$RES" && ok "_resume.py decides through swap_mode (the protocol check)" || no "_resume.py still decides on CAPABLE alone"
! grep -n '"/tmp/\(spawn\|swap\|resume\)-' "$RES" >/dev/null && ok "_resume.py names no fixed /tmp path" || no "_resume.py still names a fixed /tmp path"
rm -rf "$tmp" "$tmp2" ${t3:+"$t3"}

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
grep -q '\[string\[\]\] \$AddDir' "$PS1" && ok "ps1 spawn takes -AddDir (twin of --add-dir)" || no "ps1 spawn has no -AddDir"
grep -q "match '\^handoff-\[0-9a-f\]{16}\$'" "$PS1" && ok "ps1 grants only a handoff folder, never %TEMP% itself" || no "ps1 can grant the folder a file merely sits in (all of %TEMP%)"
grep -q 'taskFile = Join-Path \$handoff "aios-spawn-task-' "$PS1" && ok "ps1 spawn writes its task into a fresh handoff folder" || no "ps1 task still written straight into %TEMP%"
grep -q 'Move-Item -LiteralPath \$BootstrapFile -Destination \$h' "$PS1" && ok "ps1 resume moves its prompt into a fresh handoff folder" || no "ps1 resume prompt still read from %TEMP%"
grep -q '\$advisorArgs + \$addDirArgs + \$resumeArgs' "$PS1" && ok "ps1 --add-dir args reach the claude invocation" || no "ps1 --add-dir args built but never passed"
grep -q 'CLAUDE_ADD_DIRS = ' "$PS1" && grep -q '\$addDirStmt' "$PS1" && ok "ps1 in-process and new-window paths both carry -AddDir" || no "a ps1 spawn path drops -AddDir"
# The new-window path writes a script for another shell. PowerShell reads ' and the curly quotes
# as string delimiters, so a folder name spliced into that script as text could run code.
grep -q "CLAUDE_ADD_DIRS = \[System.Text.Encoding\]::UTF8.GetString(\[Convert\]::FromBase64String" "$PS1" \
  && ! grep -q "CLAUDE_ADD_DIRS = '\" + (\$AddDir" "$PS1" \
  && ok "ps1 hands -AddDir to the new shell as base64 data, never as script text" || no "ps1 splices -AddDir into script text"

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


# An alias of the same name made `claude-switch() {` a parse error, and nothing after it loaded.
_al="$(mktemp -d)"
{ printf "alias claude-switch='echo old'\nalias claude-whoami='echo old'\n"
  sed -n '/^# Account commands\./,/^claude-switch()/p' hooks/claude-identity/install-wrappers.sh
  printf 'echo AFTER-OK\n'; } > "$_al/rc"
grep -q '^claude-switch()' "$_al/rc" || no "the managed claude-switch block was not found in the installer"
for _sh in bash zsh; do
  command -v "$_sh" >/dev/null 2>&1 || continue
  _o="$($_sh -c "shopt -s expand_aliases 2>/dev/null; . '$_al/rc'" 2>&1)"
  case "$_o" in *AFTER-OK*) ok "$_sh: an existing claude-switch alias does not stop the rc file loading" ;;
                *) no "$_sh: an existing claude-switch alias broke the rc file: $_o" ;; esac
done
rm -rf "$_al"

echo "── RESULT: $PASS passed, $FAIL failed  (${BASH_VERSION:+bash $BASH_VERSION}${ZSH_VERSION:+zsh $ZSH_VERSION}) ──"
[ "$FAIL" = "0" ] || exit 1

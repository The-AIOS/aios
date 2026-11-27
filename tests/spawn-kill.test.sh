#!/usr/bin/env bash
# spawn-kill (#417): the target is the session whose name in the session registry is EXACTLY the
# name given, and only a group that is provably nothing but that session is closed.
#
# SAFETY, the first rule of this file: nothing here may signal, or read the environment of, a process
# this test did not start. Every session is a TOY: a copy of `sleep` named `claude`, registered in a
# throwaway registry ($CLAUDE_CONFIG_DIR). No pgrep, no pkill, no kill on a pid from `ps`.
#
# Usage: bash tests/spawn-kill.test.sh [repo-root]. bash 3.2; macOS and Linux.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC="$ROOT/hooks/claude-identity/install-wrappers.sh"
H="$ROOT/hooks/claude-identity/_kill_target.py"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "spawn-kill"
case "$(uname -s)" in Darwin|Linux) ;; *) echo "  skip: process groups are macOS/Linux only"; exit 0 ;; esac

T=$(mktemp -d "${TMPDIR:-/tmp}/sk.XXXXXX")
TOYS=""                                  # every pid this test started; the only pids it may signal
# Cleanup signals a toy only while its pid still runs one of our programs (its command line names
# this test's folder: `ps -o args=` carries the path on Linux and macOS alike, where `comm` is the
# short name on Linux), so a number the system has since given to someone else is never touched.
reap(){
  local p a
  for p in $TOYS; do
    a=$(ps -o args= -p "$p" 2>/dev/null) || continue
    case "$a" in
      "$T"/*) kill -KILL "$p" 2>/dev/null ;;
      *"$T"/*) [ "$(ps -o pgid= -p "$p" | tr -d ' ')" = "$p" ] && kill -KILL -- "-$p" 2>/dev/null ;;
    esac
  done
}
cleanup(){ reap; rm -rf "$T"; }
trap cleanup EXIT
# The toy session is a tiny program of our own named `claude` (comm = claude, the only thing the
# helper takes for a session). Built, not copied: macOS kills a copied system binary at exec, and it
# hides the environment of its own system binaries, so `sleep` cannot stand in for a session whose
# environment is read. It ignores its arguments and waits for a signal.
printf '#include <unistd.h>\nint main(void) { alarm(600); for (;;) pause(); }\n' > "$T/toy.c"   # gone in 10 min even if the trap never runs
if ! cc -o "$T/claude" "$T/toy.c" 2>/dev/null; then echo "  skip: no C compiler to build the toy session"; exit 0; fi
# The non-session toy is the same program under another name. Not a link to `sleep`: the Rust
# coreutils on Ubuntu refuse to run a utility called by a name that is not its own, so it died at
# start, and a case that needed it alive passed or failed for that reason instead of its own.
cp "$T/claude" "$T/other"
export CLAUDE_CONFIG_DIR="$T/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
# reg PID NAME [STARTED-EPOCH-SECONDS] [FORMER-NAMES-JSON]
reg(){ printf '{"pid": %s, "name": "%s", "cwd": "%s", "startedAt": %s000, "formerNames": %s}\n' "$1" "$2" "$T" "${3:-$(date +%s)}" "${4:-[]}" > "$CLAUDE_CONFIG_DIR/sessions/$1.json"; }
unreg(){ rm -f "$CLAUDE_CONFIG_DIR/sessions/$1.json"; }
alive(){ kill -0 "$1" 2>/dev/null && ! ps -o stat= -p "$1" 2>/dev/null | grep -q '^Z'; }
# A toy in a process group of its own, led by a plain shell that is not a session leader (as the
# wrapper's in-shell loop is). $1 = command for that shell. Prints the leader's pid (= the group).
grouped(){ perl -MPOSIX -e 'setpgid(0,0) or die; exec @ARGV' sh -c "$1" >/dev/null 2>&1 & echo $!; }
child_of(){ local i; for i in 1 2 3 4 5 6 7 8 9 10; do c=$(ps -axo pid=,ppid=,comm= | awk -v p="$1" -v n="$2" '$2==p && $3 ~ ("(^|/)" n "$") {print $1; exit}'); [ -n "$c" ] && { echo "$c"; return; }; sleep 0.2; done; }
resolve(){ python3 "$H" resolve "$1" 2>"$T/err"; }

# ---- 1. The decision, pure (no process involved) -------------------------------------------------
out=$(python3 - "$H" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("kt", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
rows = m.parse_ps("""\
  1     0     1 /sbin/launchd
 100     1   100 /Applications/Editor.app/Contents/MacOS/Editor
 110   100   100 /usr/local/bin/claude
 200     1   200 -zsh
 210   200   210 bash
 211   210   210 claude
 212   211   210 node
 300     1   300 sh
 310   300   300 claude
 320     1   320 zsh
 330   320   320 claude
 331   320   320 vim
 400     1   400 claude
 401   400   400 node
 500     1   500 -zsh
 510   500   510 -zsh
 511   510   510 claude
 600     1   600 claude
 610     1   600 claude
 700     1   700 sleep
""")
lead = lambda p: p in (200, 500)
loop = {"CLAUDE_RESPAWN_CAPABLE": "1", "CLAUDE_AGENT_NAME": "w"}
cases = [
  ("a session that leads its own group: the group", (400, "w", -1, [], None, None), ("group", 400)),
  ("a session in an editor's group: pid only", (110, "w", -1, [], None, None), "pid"),
  ("the wrapper's launcher leads the group: the group", (211, "w", -1, [], "/bin/zsh /Users/x/.aios/run/spawn-launch-w.sh", None), ("group", 210)),
  ("a login shell running something that looks like the launcher: pid only", (511, "w", -1, [], "-zsh spawn-launch-w.sh", None), "pid"),
  ("the respawn loop (subshell, not a session leader, loop vars on the session): the group", (511, "w", -1, [], "-zsh", loop), ("group", 510)),
  ("the loop vars name another session: pid only", (511, "x", -1, [], "-zsh", loop), "pid"),
  ("no loop vars (cannot read, or not set): pid only", (511, "w", -1, [], "-zsh", None), "pid"),
  ("loop vars, but the parent is a script shell that is not a session leader yet holds a stranger: pid only", (330, "w", -1, [], "zsh", loop), "pid"),
  ("a script's shell leads the group, no marks: pid only", (310, "w", -1, [], "sh deploy.sh", None), "pid"),
  ("another registered session in the same group: pid only", (600, "w", -1, [610], None, None), "pid"),
  ("the caller's own group: pid only", (400, "w", 400, [], None, None), "pid"),
  ("not claude at that pid (a reused number): pid only", (700, "w", -1, [], None, None), "pid"),
  ("not in the table: pid only", (999, "w", -1, [], None, None), "pid"),
]
bad = 0
for label, (pid, name, own, others, pcmd, lv), want in cases:
    got = m.kill_scope(rows, pid, name, own, others, pcmd, lv, lambda p: lead(p))
    good = got == want if isinstance(want, tuple) else got[0] == want
    print(("  ok   " if good else "  FAIL ") + label + ("" if good else " -> %r" % (got,)))
    bad += not good
# a loop leader that IS a session leader (a terminal's own shell): never the group
got = m.kill_scope(rows, 211, "w", -1, [], "bash", loop, lambda p: True)
print(("  ok   " if got[0] == "pid" else "  FAIL ") + "the loop marks on a session whose parent is a session leader: pid only")
bad += got[0] != "pid"
print("PURE %d" % bad)
PY
)
printf '%s\n' "$out" | grep -v '^PURE '
n=$(printf '%s\n' "$out" | grep -c '^  ok'); b=$(printf '%s\n' "$out" | sed -n 's/^PURE //p')
pass=$((pass+n)); fail=$((fail+${b:-1}))

# ---- 2. Resolving by exact name, against toy processes --------------------------------------------
"$T/claude" 300 & D=$!; TOYS="$TOYS $D"
"$T/claude" 300 & E=$!; TOYS="$TOYS $E"
"$T/claude" 300 & F=$!; TOYS="$TOYS $F"
"$T/other" 300 & O=$!; TOYS="$TOYS $O"
reg "$E" deploy-eu
resolve deploy; rc=$?
[ "$rc" = 1 ] && grep -q "no live session named 'deploy'" "$T/err" && ok "only deploy-eu is live: 'deploy' finds nothing (no prefix match)" || no "prefix: rc=$rc $(cat "$T/err")"
reg "$D" deploy
line=$(resolve deploy); rc=$?
case "$line" in *" $D "*) [ "$rc" = 0 ] && ok "deploy and deploy-eu live: 'deploy' is deploy's pid" || no "rc=$rc" ;; *) no "deploy resolved to: $line" ;; esac
reg "$F" deploy
resolve deploy; rc=$?
[ "$rc" = 2 ] && grep -q "2 live sessions are named 'deploy'" "$T/err" && grep -q "pid $D" "$T/err" && grep -q "pid $F" "$T/err" \
  && ok "two sessions named deploy: refuses and lists both" || no "two: rc=$rc $(cat "$T/err")"
unreg "$F"; unreg "$D"; unreg "$E"
reg "$D" a.b
resolve axb; rc=$?
[ "$rc" = 1 ] && ok "a '.' in a name is a character, not 'any character'" || no "a.b matched axb (rc=$rc)"
reg 999999 ghost
resolve ghost; rc=$?
[ "$rc" = 1 ] && ok "a registry entry whose pid is gone is not a session" || no "dead pid: rc=$rc"
if ! alive "$O"; then
  no "test setup did not start: the non-session toy is not running, so 'a registered pid that is not claude' cannot be tested"
else
  reg "$O" imposter
  resolve imposter; rc=$?
  { [ "$rc" = 1 ] && alive "$O"; } && ok "a registered pid that is not claude is not a session" || no "not claude: rc=$rc"
fi
unreg "$O"
reg "$D" stale $(( $(date +%s) - 3600 ))
resolve stale; rc=$?
[ "$rc" = 1 ] && ok "an entry written before its pid's process started (a reused number) is not that session" || no "reused pid taken: rc=$rc"
unreg "$D"
for st in '"soon"' Infinity NaN; do
  printf '{"pid": %s, "name": "nostart", "startedAt": %s}' "$D" "$st" > "$CLAUDE_CONFIG_DIR/sessions/$D.json"
  resolve nostart; rc=$?
  [ "$rc" = 1 ] || no "an entry with startedAt $st was taken (rc=$rc)"
done
printf '{"pid": %s, "name": "nostart"}' "$D" > "$CLAUDE_CONFIG_DIR/sessions/$D.json"
resolve nostart; rc=$?
[ "$rc" = 1 ] && ok "an entry whose start time is missing or not a number is not provably that session" || no "an entry with no startedAt was taken (rc=$rc)"
unreg "$D"
printf 'not json' > "$CLAUDE_CONFIG_DIR/sessions/broken.json"
printf '{"pid": 999998, "name": "junk-a", "formerNames": 5, "startedAt": "soon"}' > "$CLAUDE_CONFIG_DIR/sessions/junk1.json"
printf '{"pid": 999997, "name": "junk-b", "formerNames": "abc", "startedAt": true}' > "$CLAUDE_CONFIG_DIR/sessions/junk2.json"
printf '{"pid": Infinity, "name": "junk-c"}' > "$CLAUDE_CONFIG_DIR/sessions/junk3.json"
printf '{"pid": 1000000000000000000000000000000, "name": "junk-d"}' > "$CLAUDE_CONFIG_DIR/sessions/junk4.json"
python3 -c 'print("[" * 100000)' > "$CLAUDE_CONFIG_DIR/sessions/junk5.json"
printf '{"pid": %s, "name": "deploy"}' "$D" > "$CLAUDE_CONFIG_DIR/sessions/$D.key"
resolve deploy; rc=$?
[ "$rc" = 1 ] && ! grep -q Traceback "$T/err" && ok "only *.json is read, and broken or junk files are skipped, not fatal" || no "non-json/junk files: rc=$rc $(cat "$T/err")"
reg "$D" deploy
line=$(resolve deploy); rc=$?
case "$line" in *" $D "*) ok "a good entry still resolves beside the junk ones" ;; *) no "junk broke the registry: rc=$rc $line $(cat "$T/err")" ;; esac
unreg "$D"
( CLAUDE_CONFIG_DIR="$T/nowhere" python3 "$H" resolve deploy 2>"$T/err" ); rc=$?
[ "$rc" = 3 ] && grep -q "cannot read the session registry" "$T/err" && ok "no registry: refuses (exit 3)" || no "no registry: rc=$rc"
rm -f "$CLAUDE_CONFIG_DIR"/sessions/*

# ---- 3. spawn-kill end to end, on toys -------------------------------------------------------------
mkdir -p "$T/home"; ln -s "$ROOT" "$T/home/aios"
FNS=$(awk '/^_aios_run_dir\(\)/,/^}/; /^_spawn_clean_files\(\)/,/^}/; /^_aios_py\(\)/,/^}/; /^_aios_pyrun\(\)/,/^}/; /^spawn-kill\(\)/,/^}/' "$SRC")
sk(){ HOME="$T/home" bash -c 'eval "$1"; shift; spawn-kill "$@"' _ "$FNS" "$@" > "$T/sk.out" 2>&1; }
RUN="$T/home/.aios/run"; mkdir -p "$RUN"; chmod 700 "$T/home/.aios" "$RUN" 2>/dev/null

# 3a. the wrapper's in-shell loop: a subshell leading its own group, the session carrying the loop's
#     variables, and a fake secret beside them that must never appear in any output.
G=$(grouped "env CLAUDE_RESPAWN_CAPABLE=1 CLAUDE_AGENT_NAME=deploy AIOS_FAKE_SECRET=sk-fake-do-not-print $T/claude 300; while :; do sleep 1; done"); TOYS="$TOYS $G"
C=$(child_of "$G" claude)
"$T/claude" 300 & E=$!; TOYS="$TOYS $E"
reg "$C" deploy; reg "$E" deploy-eu
touch "$RUN/spawn-task-deploy.md" "$RUN/spawn-task-deploy-eu.md"
envs=$(python3 -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("kt",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(sorted((m.loop_vars_of(int(sys.argv[2])) or {}).items()))' "$H" "$C")
[ "$envs" = "[('CLAUDE_AGENT_NAME', 'deploy'), ('CLAUDE_RESPAWN_CAPABLE', '1')]" ] && ok "the environment reader keeps the two loop variables and nothing else" || no "env reader returned: $envs"
line=$(resolve deploy)
case "$line" in "group $G $C "*) ok "the respawn loop's group is the one to close" ;; *) no "loop resolved to: $line" ;; esac
sk deploy; rc=$?
sleep 0.3
if [ "$rc" = 0 ] && ! alive "$C" && ! alive "$G" && alive "$E"; then ok "spawn-kill deploy ends the session AND its loop; deploy-eu lives"; else no "loop kill: rc=$rc C=$(alive "$C" && echo up) G=$(alive "$G" && echo up) E=$(alive "$E" || echo DOWN): $(cat "$T/sk.out")"; fi
[ ! -e "$RUN/spawn-task-deploy.md" ] && [ -e "$RUN/spawn-task-deploy-eu.md" ] && ok "only the ended session's files are removed" || no "files: $(ls "$RUN")"
cat "$T/sk.out" "$T/err" | grep -q 'sk-fake-do-not-print' && no "the fake secret appeared in output" || ok "nothing from the session's environment appears in any output"
unreg "$C"

# 3b. a session inside a group it does not own (a script with other work): only the pid is signalled.
G=$(grouped "$T/claude 300 & $T/other 300 & wait"); TOYS="$TOYS $G"
C=$(child_of "$G" claude); S=$(child_of "$G" other)
if ! { [ -n "$C" ] && [ -n "$S" ] && alive "$C" && alive "$S" && alive "$G"; }; then
  no "test setup did not start: the shared group is not running (C=$C S=$S G=$G), so 'only its pid ends' cannot be tested"
else
  reg "$C" build
  sk build; rc=$?
  sleep 0.3
  if [ "$rc" = 0 ] && ! alive "$C" && alive "$G" && alive "$S"; then ok "a session in someone else's group: only its pid ends, the group's other work lives"; else no "pid-only: rc=$rc C=$(alive "$C" && echo up) G=$(alive "$G" || echo DOWN) S=$(alive "$S" || echo DOWN): $(cat "$T/sk.out")"; fi
  grep -q "its process group was left alone" "$T/sk.out" && ok "and it says why the group was left alone" || no "no reason given: $(cat "$T/sk.out")"
  unreg "$C"
fi

# 3c. nothing live by that name: exit 1, and the files stay.
touch "$RUN/spawn-task-gone.md" "$RUN/spawn-launch-gone.sh"
sk gone; rc=$?
[ "$rc" = 1 ] && [ -e "$RUN/spawn-task-gone.md" ] && [ -e "$RUN/spawn-launch-gone.sh" ] && grep -q "no live session named 'gone'" "$T/sk.out" \
  && ok "no live session: exit 1, nothing removed" || no "none: rc=$rc files=$(ls "$RUN")"

# 3d. two live sessions with the name: exit 2, both live.
"$T/claude" 300 & X=$!; TOYS="$TOYS $X"; "$T/claude" 300 & Y=$!; TOYS="$TOYS $Y"
reg "$X" twin; reg "$Y" twin
sk twin; rc=$?
[ "$rc" = 2 ] && alive "$X" && alive "$Y" && ok "two live sessions named twin: exit 2, neither touched" || no "twins: rc=$rc"

# 3e. a session that renamed itself: the loop still carries the name it started with.
G=$(grouped "env CLAUDE_RESPAWN_CAPABLE=1 CLAUDE_AGENT_NAME=old-name $T/claude; while :; do sleep 1; done"); TOYS="$TOYS $G"
C=$(child_of "$G" claude)
reg "$C" new-name "" '["old-name"]'
sk new-name; rc=$?
sleep 0.3
if [ "$rc" = 0 ] && ! alive "$C" && ! alive "$G"; then ok "a renamed session is closed with its loop (the loop's name is among its former names)"; else no "renamed: rc=$rc C=$(alive "$C" && echo up) G=$(alive "$G" && echo up): $(cat "$T/sk.out")"; fi
unreg "$C"

# 3f. a loop that ignores SIGTERM (a trap in the user's rc): it would start the session again, so it
#     gets SIGKILL after the grace.
G=$(grouped "trap '' TERM; env CLAUDE_RESPAWN_CAPABLE=1 CLAUDE_AGENT_NAME=stubborn $T/claude; while :; do sleep 1; done"); TOYS="$TOYS $G"
C=$(child_of "$G" claude)
reg "$C" stubborn
sk stubborn; rc=$?
sleep 0.3
if [ "$rc" = 0 ] && ! alive "$C" && ! alive "$G"; then ok "a loop that ignores SIGTERM is SIGKILLed after the grace"; else no "trapped loop: rc=$rc C=$(alive "$C" && echo up) G=$(alive "$G" && echo up): $(cat "$T/sk.out")"; fi
unreg "$C"

# ---- 4. Nothing of the old pattern is left -------------------------------------------------------
KILL=$(awk '/^spawn-kill\(\)/,/^}/' "$SRC")
printf '%s' "$KILL" | grep -qE 'pgrep|pkill' && no "spawn-kill still searches command lines" || ok "spawn-kill no longer searches command lines"
grep -qE 'pgrep -f "name \$name"' "$SRC" && no "spawn's start check still matches a pattern" || ok "spawn's start check no longer matches a pattern"
PS1F="$ROOT/hooks/claude-identity/install-wrappers.ps1"
PSK=$(awk '/^function spawn-kill \{/,/^\}/' "$PS1F")
printf '%s' "$PSK" | grep -q 'CommandLine -like' && no "the Windows spawn-kill still matches a command line" || ok "the Windows spawn-kill no longer matches a command line"
printf '%s' "$PSK" | grep -q 'ConvertFrom-Json' && ok "the Windows spawn-kill reads the session registry" || no "the Windows spawn-kill does not read the registry"

# ---- 5. The test leaves nothing behind ------------------------------------------------------------
reap; sleep 0.3
left=""
for p in $TOYS; do case "$(ps -o args= -p "$p" 2>/dev/null)" in *"$T"/*) alive "$p" && left="$left $p" ;; esac; done
[ -z "$left" ] && ok "no toy process is left running" || no "toy processes left running:$left"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

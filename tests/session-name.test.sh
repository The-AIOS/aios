#!/usr/bin/env bash
# tests/session-name.test.sh
#
# One rule for the name a session answers to: the LAST `agent-name` record of its transcript, read
# over the whole file. Both surfaces resolve `resume` by it. Three hooks had their own reader and
# two disagreed: the context-load audit returned the FIRST record, and the account-swap resume let
# the launch-time variable win, so a session that renamed itself was known by its old name there.
#
# This holds the readers together:
#   1. hooks/context/session_name.py (what the Python hooks import) and hooks/context/whoami (bash,
#      its own grep, because it is the first command of every session) are run over the SAME
#      transcripts and must give the same answer.
#   2. the audit and the swap resume answer with the last record.
#   3. the swap resume still addresses a wrapper's restart loop by the name the loop was started
#      with: the loop looks for its signal files under that name and no other.
#   4. no other hook carries a reader of its own.
set -u
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then echo "SKIP: no working Python found (tried python3, python, py -3)" >&2; exit 0; fi

M=hooks/context/session_name.py
W=hooks/context/whoami
[ -f "$M" ] || { echo "::error::$M missing"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P="$T/projects/-some-project"; mkdir -p "$P"

# name → transcript body. Session ids are the file names.
rec(){ printf '{"type":"agent-name","agentName":"%s","sessionId":"x"}\n' "$1"; }
filler(){ printf '{"parentUuid":null,"type":"user","message":{"content":"hello"}}\n'; }
{ rec born; filler; }                                              > "$P/one-name.jsonl"
{ rec born; filler; rec born; filler; rec renamed; rec renamed; }  > "$P/renamed.jsonl"
{ rec born; filler; rec renamed; filler; filler; filler; }         > "$P/renamed-then-quiet.jsonl"
{ filler; filler; }                                                > "$P/no-record.jsonl"
: > "$P/empty.jsonl"
# A tool result that QUOTES a record is not a record: inside a JSON string the quotes are escaped.
{ rec real; printf '{"type":"user","message":{"content":"{\\"type\\":\\"agent-name\\",\\"agentName\\":\\"quoted\\"}"}}\n'; } > "$P/quoted-in-a-result.jsonl"
# The record text in the middle of a line is not a record either.
{ rec real; printf '{"type":"assistant","note":1,"x":{"type":"agent-name","agentName":"nested"}}\n'; } > "$P/nested.jsonl"
# A record with an empty name does not erase the name before it.
{ rec kept; printf '{"type":"agent-name","agentName":"","sessionId":"x"}\n'; } > "$P/empty-name-last.jsonl"
# A last name that is not a plain session name: whoami prints what the transcript says, the swap
# resume (which puts the name in file names and in a typed command) does not use it.
{ rec born; rec 'x; touch pwned'; } > "$P/unsafe-name.jsonl"
# A stray NUL (a crash mid-write) must not make grep call the file binary and find nothing.
{ rec born; printf '{"type":"user","x":"\000"}\n'; rec after-nul; } > "$P/nul-byte.jsonl"
# No newline after the last record.
{ rec born; filler; printf '{"type":"agent-name","agentName":"no-newline","sessionId":"x"}'; } > "$P/no-final-newline.jsonl"
# Windows line ends.
printf '{"type":"agent-name","agentName":"born","sessionId":"x"}\r\n{"type":"agent-name","agentName":"crlf","sessionId":"x"}\r\n' > "$P/crlf.jsonl"

want_of(){ case "$1" in
  one-name) echo born ;; renamed|renamed-then-quiet) echo renamed ;; no-record|empty) echo "" ;;
  quoted-in-a-result|nested) echo real ;; empty-name-last) echo kept ;; unsafe-name) echo "x; touch pwned" ;; nul-byte) echo after-nul ;; no-final-newline) echo no-newline ;; crlf) echo crlf ;;
esac; }

whoami_of(){ env -u CLAUDE_AGENT_NAME CLAUDE_CONFIG_DIR="$T" CLAUDE_CODE_SESSION_ID="$1" bash "$W"; }

echo "── 1. the module and whoami give the same name for the same transcript ──"
for f in "$P"/*.jsonl; do
  id=$(basename "$f" .jsonl); want=$(want_of "$id")
  py=$($PYBIN "$M" "$f" | tr -d '\r'); sh=$(whoami_of "$id" | tr -d '\r')
  [ "$py" = "$want" ] && ok "module: $id → '${want}'" || no "module: $id" "got '$py', want '$want'"
  [ "$sh" = "$py" ] && ok "whoami agrees: $id" || no "whoami disagrees with the module: $id" "whoami '$sh', module '$py'"
done
by_id=$($PYBIN -c 'import sys; sys.path.insert(0, "hooks/context"); import session_name as s
print(s.session_name("renamed", sys.argv[1]), "|", s.session_name("no-such", sys.argv[1]), "|", s.session_name("*", sys.argv[1]), "|", s.session_name("../x", sys.argv[1]))' "$T" | tr -d '\r')
[ "$by_id" = "renamed |  |  | " ] && ok "by session id: the last name; an unknown id and an id that is a glob or a path find nothing" || no "session_name(id) wrong" "$by_id"

echo "── 2. the context-load audit names a session by its last record ──"
got=$($PYBIN -c 'import importlib.util, sys
s = importlib.util.spec_from_file_location("a", "hooks/context/context-load-audit.py"); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.agent_name(sys.argv[1]), m.agent_name(sys.argv[2]))' "$P/renamed-then-quiet.jsonl" "$P/no-record.jsonl" 2>&1 | tr -d '\r')
[ "$got" = "renamed None" ] && ok "audit: last record, and None without one" || no "audit reads another record" "$got"

echo "── 3. the account-swap resume: last record for the session, the launch name for its loop ──"
PYR=""
for c in python3.13 python3.12 python3.11 python3.10 python3 python; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null && { PYR="$c"; break; }
done
if [ -z "$PYR" ]; then
  echo "  - skip: no python >= 3.10 to import _resume.py (its own requirement)"
else
  got=$(CLAUDE_CONFIG_DIR="$T" "$PYR" - <<'PY' 2>&1
import importlib.util
s = importlib.util.spec_from_file_location("r", "hooks/claude-identity/_resume.py"); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
env = {}
m.env_var_from_pid = lambda pid, key: env.get(key, "")
m.session_name_from_ps = lambda pid: "from-args"
def both(info):
    return "%s/%s" % (m.session_name_from_pid(1, info), m.loop_key_from_pid(1, m.session_name_from_pid(1, info)))
out = []
env["CLAUDE_AGENT_NAME"] = "born"
out.append(both({"sessionId": "renamed", "name": "registry"}))        # renamed live session, started by the wrapper
out.append(both({"sessionId": "one-name", "name": "registry"}))       # never renamed
out.append(both({"sessionId": "no-record", "name": "registry"}))      # transcript without a record: the variable
out.append(both({"sessionId": "no-such", "name": "registry"}))        # no transcript: the variable
out.append(both({"sessionId": "unsafe-name", "name": "registry"}))    # a name that is not plain is not used
env.clear()
out.append(both({"sessionId": "renamed", "name": "registry"}))        # no variable: the loop key is the session's name
out.append(both({"sessionId": "no-record", "name": "registry"}))      # then the registry name
out.append(both({"sessionId": "no-record"}))                          # then --name
out.append(both(None))
print(" ".join(out))
PY
)
  want="renamed/born born/born born/born born/born born/born renamed/renamed registry/registry from-args/from-args from-args/from-args"
  [ "$got" = "$want" ] && ok "name = last record, then variable, registry, --name; loop key = the variable when set" || no "resume names wrong" "got  $got
     want $want"

  # main(), for real, on a renamed session inside a wrapper loop: the signal files go under the
  # name the loop polls, and everything said about the session uses the name it answers to.
  R="$T/run"; S="$T/sessions"; mkdir -p "$S" "$T/cwd"
  printf '{"cwd":"%s","sessionId":"renamed","name":"renamed"}' "$T/cwd" > "$S/4242.json"
  out=$(CLAUDE_CONFIG_DIR="$T" AIOS_RUN_DIR="$R" "$PYR" - "$S" <<'PY' 2>&1
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("r", "hooks/claude-identity/_resume.py"); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.SESSIONS_DIR = sys.argv[1]
m.env_var_from_pid = lambda pid, key: {"CLAUDE_AGENT_NAME": "born"}.get(key, "")
m.is_pid_alive = lambda pid: True
m.swap_mode = lambda pid: "in-place"
m.detect_ide = lambda: ""
m.tty_for_pid = lambda pid: ""
m.POST_SWAP_WAIT_SECS = 0
m.os.kill = lambda pid, sig: None
waited = []
m.wait_for_new_claude = lambda name, **k: (waited.append(name), (7, "stub"))[1]
m.respawn_session = lambda *a: (_ for _ in ()).throw(AssertionError("fresh tab opened for an in-place session"))
os.name == "nt" or m.main()
print("WAITED", ",".join(waited))
PY
)
  if [ "$(uname -s 2>/dev/null | cut -c1-5)" = "MINGW" ] || [ "${OS:-}" = "Windows_NT" ]; then
    echo "  - skip: the swap resume leaves sessions running on Windows (#303)"
  else
    [ -f "$R/swap-respawn-born.flag" ] && [ ! -e "$R/swap-respawn-renamed.flag" ] \
      && ok "the restart signal is written under the name the loop was started with" || no "the loop would not find its signal" "$(ls "$R" 2>&1 | tr '\n' ' ')"
    case "$out" in *"WAITED born"*) ok "and the restarted process is looked for under that same name" ;; *) no "waited for the wrong name" "$out" ;; esac
    case "$out" in *"renamed@"*) ok "the session is reported by the name it answers to" ;; *) no "the summary names the session by its old name" "$out" ;; esac
    ls "$R" 2>/dev/null | grep -q 'renamed' && ok "its swap marker carries the name it answers to" || no "no file under the current name" "$(ls "$R" 2>&1 | tr '\n' ' ')"
  fi
fi

# The reader is found through a symlink too (abspath would look beside the link and the resume
# would silently go back to launch names).
if [ -n "$PYR" ] && ln -s "$PWD/hooks/claude-identity/_resume.py" "$T/linked_resume.py" 2>/dev/null; then
  got=$(CLAUDE_CONFIG_DIR="$T" "$PYR" -c 'import importlib.util, sys
s = importlib.util.spec_from_file_location("r", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m._transcript_name("renamed"))' "$T/linked_resume.py" 2>&1 | tr -d '\r')
  [ "$got" = renamed ] && ok "the swap resume finds the shared reader when run through a symlink" || no "reader not found through a symlink" "$got"
fi

echo "── 4. no other hook reads the record by itself ──"
# whoami (bash, held to the module by section 1) and transcript-inventory.py (first records only,
# by design: it asks whether a transcript is named, over thousands of files) are the two exceptions.
# Every file under hooks/ that names the record's field, whatever its extension (docs aside).
bad=$(grep -rlE 'agentName' hooks 2>/dev/null | grep -vE '\.md$|__pycache__' | sort -u \
  | grep -vE '^(hooks/context/session_name\.py|hooks/context/whoami|hooks/security/transcript-inventory\.py)$' | tr '\n' ' ')
[ -z "$bad" ] && ok "only the shared module, whoami and the inventory parse agentName" || no "a hook parses the record itself" "$bad"
grep -q 'session_name' hooks/security/transcript-inventory.py && ok "the inventory says why it is not on the shared reader" || no "transcript-inventory.py does not say why it reads on its own"
for u in hooks/context/context-load-audit.py hooks/claude-identity/_resume.py hooks/agents/session-names.py; do
  grep -qE '^ *(import|from) session_name' "$u" && ok "$u uses the shared reader" || no "$u does not import session_name"
done

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/usr/bin/env bash
# tests/install-settings.test.sh
#
# hooks/install-settings.py wires SETUP §10's universal hooks without asking a new operator to
# approve raw JSON. Asserts: it changes nothing without --apply; --apply adds every hook and keeps
# every other key; a second run changes nothing (byte-identical); an operator's own statusLine is
# never replaced; invalid JSON is refused untouched; and every command it writes is one SETUP §10
# prints, on both platforms -- so the helper and the manual reference cannot drift apart.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/install-settings.py"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/settings.json"
run(){ AIOS_ROOT="$T/aios" $PYBIN "$H" --settings "$S" "$@"; }
mkdir -p "$T/aios"

printf '{\n  "model": "x",\n  "permissions": {"allow": ["Bash(ls:*)"]}\n}\n' > "$S"
cp "$S" "$T/orig.json"
out=$(run --platform posix)
cmp -s "$S" "$T/orig.json" && ok "without --apply nothing is written" || no "dry run changed the file"
case "$out" in *"+ add   A"*"+ add   D"*"+ add   E"*"+ add   F"*"+ add   B"*) ok "the summary lists A, B, D, E, F in plain language" ;; *) no "summary incomplete" "$out" ;; esac
case "$out" in *'"hooks"'*|*'"command"'*) no "the summary shows raw JSON" ;; *) ok "the summary shows no JSON" ;; esac

run --platform posix --apply >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "--apply exits 0 after verifying its own write" || no "--apply exit $rc"
$PYBIN - "$S" <<'PY' && ok "every hook present, statusLine set, existing keys kept" || no "merged file wrong" "$(cat "$S")"
import json,sys
d=json.load(open(sys.argv[1]))
h=d["hooks"]; cmds=json.dumps(h)
need=["inject-datetime.sh","provenance.py --prompt","bus_log.py --hook","provenance.py --tool","floor-at-start.py","model-switch-log.py"]
assert all(n in cmds for n in need), cmds
assert d["model"]=="x" and d["permissions"]["allow"]==["Bash(ls:*)"]
assert d["statusLine"]["command"].endswith("context-monitor.py") and "tee" not in d["statusLine"]["command"]  # one program (#292)
assert "guard-venture-mount" not in cmds  # no company mounted
PY
ls "$T"/settings.json.bak-aios-* >/dev/null 2>&1 && ok "the previous file was backed up" || no "no backup written"
cp "$S" "$T/once.json"; out=$(run --platform posix --apply)
cmp -s "$S" "$T/once.json" && case "$out" in *"Nothing to change"*) ok "a second run changes nothing" ;; *) no "second run did something" "$out" ;; esac || no "second run altered the file"

printf '{"statusLine": {"type": "command", "command": "my-own-line"}}\n' > "$S"
out=$(run --platform posix --apply)
grep '"my-own-line"' "$S" >/dev/null && ok "an operator's own statusLine is kept" || no "statusLine replaced"
case "$out" in *"! note  B"*) ok "and the summary says what that costs" ;; *) no "no note about the kept statusLine" "$out" ;; esac

printf '{ not json' > "$S"; cp "$S" "$T/bad.json"
run --platform posix --apply >/dev/null; rc=$?
[ "$rc" = 1 ] && cmp -s "$S" "$T/bad.json" && ok "invalid JSON is refused and left untouched" || no "invalid JSON handling (rc=$rc)"

mkdir -p "$T/aios/vault/00 - notes/context/ventures/acme"; : > "$T/aios/vault/00 - notes/context/ventures/acme/.acme-sync"
rm -f "$S"; run --platform posix --apply >/dev/null
grep 'guard-venture-mount' "$S" >/dev/null && ok "a mounted company brings in the venture guard (C)" || no "venture guard not added with a mount"

rm -f "$S"; printf '{}' > "$S"; chmod 600 "$S"; run --platform posix --apply >/dev/null
perm=$($PYBIN -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$S")
[ "$perm" = "0o600" ] && ok "a 0600 settings.json stays 0600 after --apply" || no "permissions loosened to $perm"
rm -f "$S"; run --platform posix --apply >/dev/null
perm=$($PYBIN -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$S")
[ "$perm" = "0o600" ] && ok "a new settings.json is created 0600" || no "new file created $perm"

echo "── a symlinked settings.json stays a link; surprising shapes exit 1 with no backup ──"
mkdir -p "$T/real"; printf '{"model": "x"}\n' > "$T/real/target.json"; rm -f "$S"
if ln -s "$T/real/target.json" "$S" 2>/dev/null && [ -L "$S" ]; then
  out=$(run --platform posix --apply); rc=$?
  [ "$rc" = 0 ] && [ -L "$S" ] && ok "a symlinked settings.json is still a link after --apply" || no "symlink replaced (rc=$rc)" "$out"
  grep -q 'floor-at-start' "$T/real/target.json" && ok "and the file it points to was updated" || no "link target not updated"
  ls "$T/real"/target.json.bak-aios-* >/dev/null 2>&1 && ok "the backup sits beside the real file" || no "no backup of the link target"
  rm -f "$S"
else ok "skip: this filesystem cannot make a symlink"; fi
shape(){ # $1 label, $2 file content
  local D="$T/shape"; rm -rf "$D"; mkdir -p "$D"; printf '%s\n' "$2" > "$D/settings.json"; cp "$D/settings.json" "$D/orig"
  out=$(AIOS_ROOT="$T/aios" $PYBIN "$H" --settings "$D/settings.json" --platform posix --apply 2>&1); rc=$?
  if [ "$rc" = 1 ] && cmp -s "$D/settings.json" "$D/orig" && ! ls "$D"/settings.json.bak-aios-* >/dev/null 2>&1 \
     && ! ls "$D"/*.aios-tmp >/dev/null 2>&1 && case "$out" in *Traceback*) false ;; *"Nothing was changed"*) true ;; *) false ;; esac
  then ok "$1: exit 1, plain error, file untouched, no backup"
  else no "$1 (rc=$rc)" "$out"; fi
}
shape '"statusLine": null' '{"statusLine": null}'
shape 'a hooks event that is not a list' '{"hooks": {"SessionStart": {"hooks": []}}}'
shape '"hooks": null' '{"hooks": null}'
shape 'a hooks entry that is not an object' '{"hooks": {"UserPromptSubmit": ["bash x"]}}'
shape 'a top-level []' '[]'
R="$T/rel"; mkdir -p "$R"; printf '{}\n' > "$R/s.json"
out=$(cd "$R" && AIOS_ROOT="$T/aios" $PYBIN "$H" --settings s.json --platform posix --apply 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q floor-at-start "$R/s.json" && case "$out" in *Traceback*) false ;; *) true ;; esac \
  && ok "a relative --settings path works" || no "relative --settings (rc=$rc)" "$out"
rm -f "$S"; AIOS_WIN_PYTHON=python AIOS_ROOT="D:/tools/aios" $PYBIN "$H" --settings "$S" --platform windows --apply >/dev/null
grep -q 'D:/tools/aios/hooks/claude-identity/context-monitor.py' "$S" && ! grep -q 'HOME/aios' "$S" \
  && ok "the Windows status line uses the framework root, not \$HOME/aios" || no "Windows status line ignores the root" "$(grep statusLine -A2 "$S")"
out=$(AIOS_WIN_PYTHON=python AIOS_ROOT="D:/tools/aios" $PYBIN "$H" --settings "$S" --platform windows)
case "$out" in *"! note"*) no "the helper's own Windows status line is reported as foreign" "$out" ;; *) ok "a second Windows run recognises its own status line" ;; esac

echo "── parity: every command written is one SETUP §10 prints ──"
for plat in posix windows; do
  rm -f "$S"; AIOS_WIN_PYTHON=python AIOS_ROOT="C:/Users/<you>/aios" $PYBIN "$H" --settings "$S" --platform $plat --apply >/dev/null
  missing=$($PYBIN - "$S" "$ROOT/SETUP.md" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); setup=open(sys.argv[2],encoding="utf-8").read()
cmds=[hk["command"] for groups in d["hooks"].values() for g in groups for hk in g["hooks"]]+[d["statusLine"]["command"]]
for c in cmds:
    if json.dumps(c)[1:-1] not in setup: print(c)
PY
)
  [ -z "$missing" ] && ok "$plat: all commands match SETUP §10 verbatim" || no "$plat: commands SETUP does not print" "$missing"
done

echo "── a missing hook file is a no-op, never a block (exit 2 = BLOCK in Claude Code) ──"
# Every hook command the installer writes and every one SETUP §10 prints, run with a HOME that has
# no aios/ at all (the framework moved or a hook was renamed): none may exit 2.
E="$T/empty-home"; mkdir -p "$E"
CMDS="$T/cmds.txt"
$PYBIN - "$H" "$ROOT/SETUP.md" > "$CMDS" <<'PY'
import importlib.util, json, re, sys
spec = importlib.util.spec_from_file_location("ins", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for plat in ("posix", "windows"):
    for row in m.plan(plat, "/nonexistent/aios", True)[0]:
        print(row[3])
for lit in re.findall(r'"command":\s*("(?:[^"\\]|\\.)*")', open(sys.argv[2], encoding="utf-8").read()):
    c = json.loads(lit)
    if "hooks/" in c and "claude-identity.sh" not in c:
        print(c)
PY
n=0; bad=""; unguarded=""
while IFS= read -r c; do
  [ -n "$c" ] || continue; n=$((n+1))
  case "$c" in "[ ! -f "*) ;; *) unguarded="$unguarded | $c";; esac
  HOME="$E" bash -c "$c" </dev/null >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && bad="$bad | $c"
done < "$CMDS"
[ "$n" -ge 20 ] && ok "checked $n registered hook commands (installer, both platforms, + SETUP §10)" || no "only $n commands found" "the extraction is too narrow to be a real check"
[ -z "$unguarded" ] && ok "every one is guarded with [ ! -f FILE ] ||" || no "unguarded hook commands" "$unguarded"
[ -z "$bad" ] && ok "none exits 2 when its file is missing" || no "hook commands that BLOCK on a missing file" "$bad"
# Controls: the unguarded form really does exit 2 (so the check above can fail), and a PRESENT hook
# that means to block still blocks through the guard.
HOME="$E" bash -c 'python3 ~/aios/hooks/provenance.py --prompt' </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "control: the bare form exits 2 on a missing file" || no "control: bare form exited $rc" "the no-block check could not have failed"
mkdir -p "$E/aios/hooks"; printf 'import sys\nsys.exit(2)\n' > "$E/aios/hooks/provenance.py"
G=$($PYBIN -c "import importlib.util as u;s=u.spec_from_file_location('i','$H');m=u.module_from_spec(s);s.loader.exec_module(m);print(m.guard('python3 ~/aios/hooks/provenance.py --prompt'))")
HOME="$E" bash -c "$G" </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "control: a present hook keeps its own exit code through the guard" || no "the guard swallowed a real block (exit $rc)"

echo "── existing installs: bare AIOS hooks are wrapped in place, the rest untouched ──"
S="$T/legacy.json"
cat > "$S" <<'JSON'
{"model":"opus","hooks":{
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash ~/aios/hooks/inject-datetime.sh"},{"type":"command","command":"python3 ~/aios/hooks/provenance.py --prompt","timeout":10}]}],
 "PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"python3 \"$HOME/aios/hooks/guard-venture-mount.py\"","timeout":10}]},{"matcher":"Bash","hooks":[{"type":"command","command":"python3 /opt/mine/check.py"}]}]}}
JSON
out=$(run --platform posix)
case "$out" in *"~ guard A"*"~ guard C"*"~ guard D"*) ok "dry run lists the guards it would add (A, C, D)" ;; *) no "dry run did not list the guards" "$out" ;; esac
run --platform posix --apply >/dev/null
$PYBIN - "$S" <<'PY' && ok "bare hooks wrapped with their own path spelling; an operator's own hook untouched" || no "migration wrong" "$(cat "$S")"
import json, sys
s = json.load(open(sys.argv[1])); cmds = [h["command"] for gs in s["hooks"].values() for g in gs for h in g["hooks"]]
assert '[ ! -f "$HOME/aios/hooks/guard-venture-mount.py" ] || python3 "$HOME/aios/hooks/guard-venture-mount.py"' in cmds, cmds
assert "[ ! -f ~/aios/hooks/provenance.py ] || python3 ~/aios/hooks/provenance.py --prompt" in cmds, cmds
assert "python3 /opt/mine/check.py" in cmds, cmds
assert s["model"] == "opus"
PY
out=$(run --platform posix)
case "$out" in *"Nothing to change."*) ok "a second run changes nothing" ;; *) no "second run still wants changes" "$out" ;; esac

echo "── R: transcript retention is set when absent, and an operator's own value is never changed ──"
# Claude Code deletes transcripts after 30 days by default, at every session start, silently.
printf '{}\n' > "$S"; out=$(run --platform posix --apply)
case "$out" in *"+ set   R"*) ok "a file with no cleanupPeriodDays is offered R" ;; *) no "R not offered" "$out" ;; esac
[ "$($PYBIN -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cleanupPeriodDays"))' "$S")" = 3650 ] \
  && ok "--apply sets cleanupPeriodDays to 3650" || no "cleanupPeriodDays not written"
printf '{"cleanupPeriodDays": 30}\n' > "$S"; out=$(run --platform posix --apply)
case "$out" in *"! note  R"*"your setting, left as it is"*) ok "an operator's 30 is noted, not overridden" ;; *) no "own value not noted" "$out" ;; esac
[ "$($PYBIN -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cleanupPeriodDays"))' "$S")" = 30 ] \
  && ok "an operator's own value stays 30 after --apply" || no "the operator's retention was overridden"
out=$(run --platform posix)
case "$out" in *"= keep  R"*|*"! note  R"*) ok "a later run does not offer R again" ;; *) no "R offered twice" "$out" ;; esac

echo "── B: the two-program status line AIOS wrote before #292 becomes one program; anything else is kept ──"
OLDP="bash -c 'tee >(\$HOME/aios/hooks/claude-identity/claude-identity.sh cache > /dev/null) | python3 \$HOME/aios/hooks/claude-identity/context-monitor.py'"
$PYBIN -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":sys.argv[2]}}, open(sys.argv[1],"w"))' "$S" "$OLDP"
out=$(run --platform posix)
case "$out" in *"~ update B"*) ok "the old macOS/Linux form is offered as an update" ;; *) no "old posix form not recognised" "$out" ;; esac
run --platform posix --apply >/dev/null
[ "$($PYBIN -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$S")" = '[ ! -f $HOME/aios/hooks/claude-identity/context-monitor.py ] || python3 $HOME/aios/hooks/claude-identity/context-monitor.py' ] \
  && ok "--apply replaces it with the one-program form" || no "old posix form not replaced" "$(cat "$S")"
OLDW='bash -c '"'"'tee >("C:/Users/x/aios/hooks/claude-identity/claude-identity.sh" cache > /dev/null) | py -3 "C:/Users/x/aios/hooks/claude-identity/context-monitor.py"'"'"
$PYBIN -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":sys.argv[2]}}, open(sys.argv[1],"w"))' "$S" "$OLDW"
AIOS_WIN_PYTHON="py -3" AIOS_ROOT="C:/Users/x/aios" $PYBIN "$H" --settings "$S" --platform windows --apply >/dev/null
grep -q '|| py -3 \\"C:/Users/x/aios/hooks/claude-identity/context-monitor.py\\""' "$S" && ! grep -q tee "$S" \
  && ok "the old Windows form (quoted paths, py -3) is replaced too" || no "old Windows form not replaced" "$(cat "$S")"
ABS="bash -c 'tee >($T/aios/hooks/claude-identity/claude-identity.sh cache > /dev/null) | python3 $T/aios/hooks/claude-identity/context-monitor.py'"
$PYBIN -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":sys.argv[2]}}, open(sys.argv[1],"w"))' "$S" "$ABS"
run --platform posix --apply >/dev/null
[ "$($PYBIN -c 'import json,sys; print(json.load(open(sys.argv[1]))["statusLine"]["command"])' "$S")" = "[ ! -f $T/aios/hooks/claude-identity/context-monitor.py ] || python3 $T/aios/hooks/claude-identity/context-monitor.py" ] \
  && ok "a hand-written absolute-root form of this framework is upgraded, keeping its own root" || no "absolute-root form not upgraded" "$(cat "$S")"
OTHER="bash -c 'tee >(/opt/fork/hooks/claude-identity/claude-identity.sh cache > /dev/null) | python3 /opt/fork/hooks/claude-identity/context-monitor.py'"
$PYBIN -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":sys.argv[2]}}, open(sys.argv[1],"w"))' "$S" "$OTHER"
out=$(run --platform posix --apply)
grep -q '/opt/fork/' "$S" && case "$out" in *"! note  B"*"two programs"*) ok "another root is kept, and the summary says it still runs two programs" ;; *) no "no note for a leftover two-program line" "$out" ;; esac || no "a line for another root was replaced"
CUSTOM="bash -c 'tee >(\$HOME/aios/hooks/claude-identity/claude-identity.sh cache > /dev/null) | my-own-monitor'"
$PYBIN -c 'import json,sys; json.dump({"statusLine":{"type":"command","command":sys.argv[2]}}, open(sys.argv[1],"w"))' "$S" "$CUSTOM"
cp "$S" "$T/custom.json"; out=$(run --platform posix --apply)
cmp -s "$S" "$T/custom.json" >/dev/null 2>&1 || grep -q 'my-own-monitor' "$S"
grep -q 'my-own-monitor' "$S" && case "$out" in *"~ update B"*) no "a custom line that feeds the cache was offered as an update" ;; *) ok "a custom status line that feeds the cache is kept, unflagged" ;; esac || no "custom line replaced"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]

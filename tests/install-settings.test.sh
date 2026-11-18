#!/usr/bin/env bash
# tests/install-settings.test.sh
#
# hooks/install/install-settings.py wires SETUP §10's universal hooks without asking a new operator to
# approve raw JSON. Asserts: it changes nothing without --apply; --apply adds every hook and keeps
# every other key; a second run changes nothing (byte-identical); an operator's own statusLine is
# never replaced; invalid JSON is refused untouched; and every command it writes is one SETUP §10
# prints, on both platforms -- so the helper and the manual reference cannot drift apart.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/install/install-settings.py"
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
case "$out" in *"+ add   A"*"+ add   D"*"+ add   E"*"+ add   F"*"+ add   G"*"+ add   B"*) ok "the summary lists A, B, D, E, F, G in plain language" ;; *) no "summary incomplete" "$out" ;; esac
case "$out" in *'"hooks"'*|*'"command"'*) no "the summary shows raw JSON" ;; *) ok "the summary shows no JSON" ;; esac

run --platform posix --apply >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "--apply exits 0 after verifying its own write" || no "--apply exit $rc"
$PYBIN - "$S" <<'PY' && ok "every hook present, statusLine set, existing keys kept" || no "merged file wrong" "$(cat "$S")"
import json,sys
d=json.load(open(sys.argv[1]))
h=d["hooks"]; cmds=json.dumps(h)
need=["inject-datetime.sh","provenance.py --prompt","bus_log.py --hook","provenance.py --tool","floor-at-start.py","model-switch-log.py","suggest-agent-hint.py"]
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
HOME="$E" bash -c 'python3 ~/aios/hooks/context/provenance.py --prompt' </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "control: the bare form exits 2 on a missing file" || no "control: bare form exited $rc" "the no-block check could not have failed"
mkdir -p "$E/aios/hooks/context"; printf 'import sys\nsys.exit(2)\n' > "$E/aios/hooks/context/provenance.py"
G=$($PYBIN -c "import importlib.util as u;s=u.spec_from_file_location('i','$H');m=u.module_from_spec(s);s.loader.exec_module(m);print(m.guard('python3 ~/aios/hooks/context/provenance.py --prompt'))")
HOME="$E" bash -c "$G" </dev/null >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "control: a present hook keeps its own exit code through the guard" || no "the guard swallowed a real block (exit $rc)"

echo "── #309: a hook registered at its old top-level path moves to its folder, keeping interpreter and root ──"
S="$T/moved.json"
printf '%s' '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"[ ! -f ~/aios/hooks/inject-datetime.sh ] || bash ~/aios/hooks/inject-datetime.sh"}]},{"hooks":[{"type":"command","command":"/opt/py/bin/python3 ROOTX/hooks/provenance.py --prompt","timeout":10},{"type":"command","command":"python3 ~/.claude/hooks/provenance.py --prompt"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"[ ! -f ~/aios/hooks/floor-at-start.py ] || python3 ~/aios/hooks/floor-at-start.py"}]}]},"statusLine":{"type":"command","command":"my-own-line"},"cleanupPeriodDays":30}' > "$S"
sed -i.bak "s|ROOTX|$T/aios|" "$S"
out=$(HOME="$T" run --platform posix)
case "$out" in *"~ move  A"*"~ move  D"*"~ move  E"*) ok "the summary names each hook that moves" ;; *) no "no move lines" "$out" ;; esac
HOME="$T" run --platform posix --apply >/dev/null
$PYBIN - "$S" "$T/aios" <<'PY' && ok "old paths moved; interpreter, root and guard kept; nothing else changed" || no "move wrong" "$(cat "$S")"
import json,sys
d=json.load(open(sys.argv[1])); c=[h["command"] for ev in d["hooks"].values() for g in ev for h in g["hooks"]]
assert "[ ! -f ~/aios/hooks/context/inject-datetime.sh ] || bash ~/aios/hooks/context/inject-datetime.sh" in c, c
r=sys.argv[2]
assert "[ ! -f %s/hooks/context/provenance.py ] || /opt/py/bin/python3 %s/hooks/context/provenance.py --prompt" % (r, r) in c, c
assert any("~/.claude/hooks/provenance.py --prompt" in x for x in c), "an operator's own hooks/ path was moved: %s" % c
assert "[ ! -f ~/aios/hooks/context/floor-at-start.py ] || python3 ~/aios/hooks/context/floor-at-start.py" in c, c
assert not any(("aios/hooks/inject-datetime" in x or "aios/hooks/provenance.py" in x or "aios/hooks/floor-at-start.py" in x) for x in c), c
assert d["statusLine"]["command"]=="my-own-line" and d["cleanupPeriodDays"]==30
PY
$PYBIN - "$H" "$T/my vault/aios" <<'PY' && ok "a quoted root with a space moves too (C:/Users/John Smith/aios)" || no "a quoted root with a space was not moved"
import importlib.util as u, os, sys
os.environ["AIOS_ROOT"] = sys.argv[2]
s = u.spec_from_file_location("i", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
r = sys.argv[2]
assert m.moved('python3 "%s/hooks/provenance.py" --prompt' % r) == 'python3 "%s/hooks/context/provenance.py" --prompt' % r
assert m.moved('bash ~/elsewhere/hooks/inject-datetime.sh; true') is None
PY
cp "$S" "$T/moved-once.json"; out=$(HOME="$T" run --platform posix --apply)
cmp -s "$S" "$T/moved-once.json" && case "$out" in *"Nothing to change"*) ok "a second run moves nothing" ;; *) no "second run did something" "$out" ;; esac || no "second run altered the moved file"

echo "── existing installs: bare AIOS hooks are wrapped in place, the rest untouched ──"
S="$T/legacy.json"
cat > "$S" <<'JSON'
{"model":"opus","hooks":{
 "UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash ~/aios/hooks/context/inject-datetime.sh"},{"type":"command","command":"python3 ~/aios/hooks/context/provenance.py --prompt","timeout":10}]}],
 "PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"python3 \"$HOME/aios/hooks/context/guard-venture-mount.py\"","timeout":10}]},{"matcher":"Bash","hooks":[{"type":"command","command":"python3 /opt/mine/check.py"}]}]}}
JSON
out=$(run --platform posix)
case "$out" in *"~ guard A"*"~ guard C"*"~ guard D"*) ok "dry run lists the guards it would add (A, C, D)" ;; *) no "dry run did not list the guards" "$out" ;; esac
run --platform posix --apply >/dev/null
$PYBIN - "$S" <<'PY' && ok "bare hooks wrapped with their own path spelling; an operator's own hook untouched" || no "migration wrong" "$(cat "$S")"
import json, sys
s = json.load(open(sys.argv[1])); cmds = [h["command"] for gs in s["hooks"].values() for g in gs for h in g["hooks"]]
assert '[ ! -f "$HOME/aios/hooks/context/guard-venture-mount.py" ] || python3 "$HOME/aios/hooks/context/guard-venture-mount.py"' in cmds, cmds
assert "[ ! -f ~/aios/hooks/context/provenance.py ] || python3 ~/aios/hooks/context/provenance.py --prompt" in cmds, cmds
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

# #334: the guard turns a missing hook file into a silent skip, so the installer must say when it
# happens. Fixture home + framework; each case fails without the check (no `!` line is printed).
G="$T/g334"; mkdir -p "$G/home" "$G/fw/hooks/context" "$G/fw/hooks/claude-identity" "$G/other/hooks/context"
touch "$G/fw/hooks/context/floor-at-start.py" "$G/other/hooks/context/floor-at-start.py"
cat > "$G/s.json" <<'J'
{"hooks":{"UserPromptSubmit":[{"hooks":[
 {"type":"command","command":"[ ! -f ~/aios/hooks/context/no-such-hook.py ] || python3 ~/aios/hooks/context/no-such-hook.py"},
 {"type":"command","command":"[ ! -f \"$HOME/aios/hooks/context/floor-at-start.py\" ] || python3 \"$HOME/aios/hooks/context/floor-at-start.py\""},
 {"type":"command","command":"[ ! -f ~/aios/hooks/floor-at-start.py ] || python3 ~/aios/hooks/floor-at-start.py"}]}]},
 "statusLine":{"type":"command","command":"[ ! -f ~/aios/hooks/claude-identity/gone.py ] || python3 ~/aios/hooks/claude-identity/gone.py"}}
J
g(){ HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/s.json" --platform posix; }
out=$(g)
case "$out" in *"! link  ~/aios does not exist"*"ln -s"*) ok "no ~/aios: one line says every hook is skipped, with the fix" ;; *) no "no ~/aios link line" "$out" ;; esac
case "$out" in *"! missing"*"aios/hooks"*) no "per-hook lines repeat what the link line already says" "$out" ;; *) ok "no ~/aios: the hooks under it are not listed one by one" ;; esac
ln -s "$G/fw" "$G/home/aios"; out=$(g)
case "$out" in *"! link"*) no "a correct ~/aios link was flagged" "$out" ;; *) ok "a correct ~/aios link prints no link line" ;; esac
case "$out" in *"! missing  UserPromptSubmit  "*"no-such-hook.py  this hook is being skipped"*) ok "a guarded hook whose file is gone is named" ;; *) no "dangling hook not named" "$out" ;; esac
case "$out" in *"! missing  statusLine  "*"gone.py"*) ok "a guarded status line whose file is gone is named" ;; *) no "dangling status line not named" "$out" ;; esac
case "$out" in *"floor-at-start.py  this hook"*) no "a hook whose file exists (quoted \$HOME form) was flagged" "$out" ;; *) ok "a hook whose file exists is not flagged, quoted \$HOME form included" ;; esac
case "$out" in *"hooks/floor-at-start.py  this hook"*) no "a hook the installer is about to move was flagged as missing" "$out" ;; *) ok "a hook ~ move repoints is not reported missing" ;; esac
rm "$G/home/aios"; ln -s "$G/other" "$G/home/aios"; out=$(g)
case "$out" in *"! note  ~/aios leads to another copy of AIOS"*) ok "~/aios on another copy: a note, not a skip warning" ;; *) no "other-copy note missing" "$out" ;; esac
case "$out" in *"! link "*) no "another copy was reported as skipping every hook" "$out" ;; *) ok "another copy is not reported as skipping" ;; esac
# Review round: quoting forms, forged lines, odd shapes.
rm "$G/home/aios"; ln -s "$G/fw" "$G/home/aios"; touch "$G/fw/hooks/context/single.py"
cat > "$G/q.json" <<'J'
{"hooks":{"Stop":[{"hooks":[
 {"type":"command","command":"[ ! -f \"$HOME/aios/hooks/context/absent.py\" ] || python3 \"$HOME/aios/hooks/context/absent.py\""},
 {"type":"command","command":"[ ! -f 'HOMEDIR/aios/hooks/context/single.py' ] || true"},
 {"type":"command","command":"[ ! -f \"/nope\n  ! link  forged line\" ] || true"}]}],
 "Odd":{"hooks":[]}, "Odd2":[{"hooks":["echo hi"]}], "Odd3":["x"]}}
J
sed -i.bak "s#HOMEDIR#$G/home#" "$G/q.json"
out=$(HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/q.json" --platform posix 2>&1); rc=$?
case "$out" in *"! missing  Stop  "*"absent.py"*) ok "a double-quoted \$HOME hook whose file is gone is named" ;; *) no "quoted \$HOME missing hook not named" "$out" ;; esac
case "$out" in *"single.py  this hook"*) no "a single-quoted path that exists was flagged" "$out" ;; *) ok "a single-quoted path that exists is not flagged" ;; esac
case "$out" in *"forged line"*) no "a path with a newline printed a line of its own" "$out" ;; *) ok "a path with a control character never prints text of its own" ;; esac
case "$out" in *Traceback*) no "odd hook shapes crash the installer" "$out" ;; *) ok "odd hook shapes (not lists, not dicts) do not crash it" ;; esac
# Second review round.
cat > "$G/r2.json" <<J
{"hooks":{"Stop":[{"hooks":[
 {"type":"command","command":"[ ! -f '$G/fw/hooks/context/single-absent.py' ] || true"},
 {"type":"command","command":"[ ! -f ~/aios/hooks/context/*.py ] || true"},
 {"type":"command","command":"[ ! -f \"~/aios/hooks/context/floor-at-start.py\" ] || true"}]}],
 "Stop\n  ! missing  forged by event":[{"hooks":[{"type":"command","command":"[ ! -f /nope/x.py ] || true"}]}]}}
J
out=$(HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/r2.json" --platform posix 2>&1)
case "$out" in *"! missing  Stop  "*"single-absent.py"*) ok "a single-quoted path whose file is gone is named" ;; *) no "single-quoted missing path not named" "$out" ;; esac
case "$out" in *'*.py  this hook'*) no "a glob path the shell expands was flagged" "$out" ;; *) ok "a path the shell globs is not judged" ;; esac
case "$out" in *"floor-at-start.py  this hook is being skipped (a quoted ~ is not expanded"*) ok "a quoted ~ is named with why the shell skips it" ;; *) no "quoted ~ not explained" "$out" ;; esac
case "$out" in *"forged by event"*) no "an event key printed a line of its own" "$out" ;; *) ok "an event key with a control character prints nothing" ;; esac
# Absolute-root hooks with no ~/aios at all: every hook runs, so no link line.
rm -f "$G/home/aios"; ABS="$G/fw/hooks"
HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/abs.json" --platform posix --apply >/dev/null 2>&1
$PYBIN - "$G/abs.json" "$G/home" "$G/fw" <<'PY'
import json,sys
p,home,fw=sys.argv[1:]; s=open(p).read().replace("~/aios",fw).replace("$HOME/aios",fw); open(p,"w").write(s)
PY
out=$(HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/abs.json" --platform posix 2>&1)
case "$out" in *"! link"*) no "absolute-root hooks with no ~/aios got a link warning" "$out" ;; *) ok "absolute-root hooks with no ~/aios get no link warning" ;; esac
# A dangling ~/aios link: say so, and offer to move it aside before ln -sn.
ln -s "$G/gone" "$G/home/aios"; out=$(HOME="$G/home" AIOS_ROOT="$G/fw" $PYBIN "$H" --settings "$G/s.json" --platform posix 2>&1)
case "$out" in *"! link  ~/aios is a link to"*"which no longer exists"*"move ~/aios aside, then ln -sn"*) ok "a dangling ~/aios link is named, with move-aside then ln -sn" ;; *) no "dangling link not handled" "$out" ;; esac
rm -f "$G/home/aios"

grep -q '^### 6\.85\. Hooks that are being skipped' "$ROOT/plugins/aios/commands/update.md" && grep -q "install-settings.py\" | grep '^  ! missing'" "$ROOT/plugins/aios/commands/update.md" \
  && ok "/aios:update relays the ! lines on every run (Step 6.85)" || no "update.md lacks the every-run Step 6.85"

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ]

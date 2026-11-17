#!/usr/bin/env bash
# tests/floor-at-start.test.sh
#
# hooks/context/floor-at-start.py delivers a COMPACT context floor at session start (the pointer to the
# full floor file, INTENT's boundary sections, the newest entries' titles) as SessionStart
# additionalContext. It skips resumes, honours AIOS_FLOOR_AT_START=0/1, keeps EVERY mode under
# its character ceiling with the pointer first, falls back to INTENT when the floor refuses the
# vault, fires only when the session's cwd is inside the vault, and never fails a session
# start. Runs against a throwaway vault. bash 3.2-safe.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/context/floor-at-start.py"
PYBIN=""; for c in python3 python "py -3"; do if $c -c 'import sys' >/dev/null 2>&1; then PYBIN="$c"; break; fi; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
V="$T/vault-root"; C="$V/vault/00 - notes/context"
mkdir -p "$C/declared" "$C/observed" "$V/hooks/context"
cp "$ROOT/hooks/context/context-floor.py" "$ROOT/hooks/context/floor-at-start.py" "$V/hooks/context/"
printf '# Index\n' > "$C/declared/_index.md"; printf '# Index\n' > "$C/observed/_index.md"
printf '# About\n## Who\nprose\n' > "$C/declared/about_me.md"
{ printf '# Patterns\n'; for i in 1 2 3 4 5 6 7; do printf '### Pattern %s (2026-10-0%s)\nbody-%s\n' "$i" "$i" "$i"; done; } > "$C/observed/patterns.md"
printf '# Intent\n## Autonomy levels\nintent-marker-xyz\n' > "$V/INTENT.md"
printf '# User\n## Identity\n| Name | Role | Greeting style |\n|---|---|---|\n| `lead` | primary | hi |\n\n## Other\n' > "$V/USER.md"
export TMPDIR="$T"
hook(){ # $1 source · rest: env assignments. Runs with the vault as cwd (the hook only fires inside it).
  local src="$1"; shift
  ( cd "$V" && printf '{"session_id":"s1","source":"%s"}' "$src" | env -u AIOS_FLOOR_AT_START -u CLAUDE_AGENT_NAME "$@" $PYBIN "$V/hooks/context/floor-at-start.py" )
}
ctx(){ $PYBIN -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception: pass'; }
nchars(){ $PYBIN -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))'; }
CEIL=$(sed -n 's/^CEILING_CHARS = \([0-9]*\).*/\1/p' "$H")

echo "-- what is delivered --"
OUT=$(hook startup CLAUDE_CODE_ENTRYPOINT=cli | ctx)
case "$OUT" in *intent-marker-xyz*) ok "INTENT.md's boundary section is delivered" ;; *) no "INTENT missing" "$(printf '%s' "$OUT" | head -3)" ;; esac
case "$OUT" in *"patterns.md: Pattern 7"*) ok "the newest entries' titles are delivered" ;; *) no "newest titles missing" ;; esac
printf '%s' "$OUT" | grep 'body-7' >/dev/null && no "an entry BODY was delivered" "compact = titles only" || ok "entry bodies stay in the full file"
printf '%s' "$OUT" | grep 'Pattern 1 ' >/dev/null && no "an old entry's title was delivered" || ok "only the newest titles, not every title"
case "$(printf '%s' "$OUT" | head -2)" in *"Read "*"context-floor-s1.md"*"END OF FLOOR"*) ok "it opens with the pointer to the full floor file" ;; *) no "no pointer to the full file first" ;; esac
[ -f "$V/.aios-run/floor/context-floor-s1.md" ] && ok "the full floor file is written inside the framework root" || no "full floor file missing under .aios-run/floor/"
printf '%s' "$OUT" | grep 'NOT LOADED YET' >/dev/null && no "the compact floor still says the floor is not loaded" || ok "it does not tell the session the floor is missing"
hook startup CLAUDE_CODE_ENTRYPOINT=cli | $PYBIN -c 'import json,sys; d=json.load(sys.stdin)["hookSpecificOutput"]; assert d["hookEventName"]=="SessionStart"' \
  && ok "SessionStart output is the hook JSON shape" || no "bad SessionStart JSON"

echo "-- who gets it --"
R=$(hook startup CLAUDE_CODE_ENTRYPOINT=sdk-cli | ctx)
case "$R" in *intent-marker-xyz*) ok "a routine (sdk-*) gets INTENT.md" ;; *) no "a routine got no INTENT" ;; esac
printf '%s' "$R" | grep -E 'Pattern 7|context-floor-s1' >/dev/null && no "a routine got titles or the map" "routines get INTENT alone" || ok "…and INTENT alone, no titles or map"
case "$(hook startup CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_AGENT_NAME=some-worker | ctx)" in *"patterns.md: Pattern 7"*) ok "a named worker (not a primary) gets the compact floor" ;; *) no "a named worker was skipped" ;; esac
[ -n "$(hook resume CLAUDE_CODE_ENTRYPOINT=cli)" ] && no "a resume got it again" || ok "a resume is skipped (the transcript already holds it)"
[ -n "$(hook compact CLAUDE_CODE_ENTRYPOINT=cli)" ] && ok "after a compaction it is delivered again" || no "not delivered after compaction"
[ -n "$(hook startup CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_AGENT_NAME=lead)" ] && ok "a USER.md primary gets it" || no "primary skipped"
[ -n "$(hook startup CLAUDE_CODE_ENTRYPOINT=sdk-cli AIOS_FLOOR_AT_START=1)" ] && ok "AIOS_FLOOR_AT_START=1 opts any session in" || no "opt-in ignored"
[ -n "$(hook startup CLAUDE_CODE_ENTRYPOINT=cli AIOS_FLOOR_AT_START=0)" ] && no "opt-out ignored" || ok "AIOS_FLOOR_AT_START=0 opts any session out"

echo "-- never in the way --"
out=$(cd "$V" && printf 'not json' | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$V/hooks/context/floor-at-start.py"); rc=$?
[ "$rc" = 0 ] && ok "malformed stdin: exit 0" || no "malformed stdin rc=$rc"
mv "$C/observed" "$C/observed.off"
out=$(hook startup CLAUDE_CODE_ENTRYPOINT=cli); rc=$?
OUT=$(printf '%s' "$out" | ctx)
[ "$rc" = 0 ] && case "$OUT" in *"INTENT.md"*intent-marker-xyz*) true ;; *) false ;; esac \
  && ok "a vault the floor refuses (fresh): exit 0, INTENT still delivered" || no "broken vault rc=$rc" "$(printf '%s' "$out" | head -c 200)"
mv "$C/observed.off" "$C/observed"

echo "-- the ceiling (Claude Code previews SessionStart context past ~10,000 chars) --"
[ -n "$CEIL" ] && [ "$CEIL" -lt 10000 ] && ok "the ceiling is one named constant under 10,000 ($CEIL)" || no "no CEILING_CHARS constant under 10,000" "$CEIL"
cp "$V/INTENT.md" "$T/intent.small"
cat > "$T/heavy.py" <<'PY'
import sys, os
pad = ('é wide prose that runs on and on ' * 3 + '\n') * 120
open(sys.argv[1], 'w', encoding='utf-8').write(
    '# Intent\n' + pad + '## Autonomy levels\nintent-marker-xyz\n' + pad +
    '## Venture notes\nventure-marker-qq\n' + pad +
    '## Global decision boundaries\nboundary-marker-yy\n' + pad +
    '## Global communication rules\ncomms-marker-zz\n' + pad)
for n in range(12):
    with open(os.path.join(sys.argv[2], 'heavy%02d.md' % n), 'w', encoding='utf-8') as f:
        f.write('# Heavy\n')
        for i in range(1, 8):
            f.write('### A long title for heavy entry %d of file %d, padded to be realistic and long (2026-10-0%d)\nbody\n' % (i, n, i))
PY
$PYBIN "$T/heavy.py" "$V/INTENT.md" "$C/observed"
for spec in "startup CLAUDE_CODE_ENTRYPOINT=cli" "startup CLAUDE_CODE_ENTRYPOINT=sdk-cli" "startup CLAUDE_CODE_ENTRYPOINT=sdk-cli AIOS_FLOOR_AT_START=1" "compact CLAUDE_CODE_ENTRYPOINT=cli"; do
  OUT=$(hook $spec | ctx); n=$(printf '%s' "$OUT" | nchars)
  [ "$n" -gt 0 ] && [ "$n" -le "$CEIL" ] && ok "under the ceiling: $spec ($n chars)" || no "over the ceiling or empty: $spec" "$n chars"
  case "$(printf '%s' "$OUT" | head -3)" in *"BEFORE ACTING"*) ok "…and it opens with the pointer" ;; *) no "pointer not first: $spec" ;; esac
done
OUT=$(hook startup CLAUDE_CODE_ENTRYPOINT=cli | ctx)
case "$OUT" in *"context-floor-s1.md"*"END OF FLOOR"*) ok "INTENT alone over the cap: the floor pointer survives" ;; *) no "floor pointer lost when INTENT exceeds the cap" ;; esac
case "$(printf '%s' "$OUT" | head -3)" in *"in these parts (line ranges, each fits one Read): 1-"*) ok "the pointer passes on the floor's own read parts" ;; *) no "the pointer has no computed read parts" "a fixed line count overflows one Read in a large floor" ;; esac
case "$OUT" in *boundary-marker-yy*comms-marker-zz*) ok "boundary sections are chosen by heading, in order" ;; *) no "boundary sections missing" ;; esac
printf '%s' "$OUT" | grep 'venture-marker-qq' >/dev/null && no "a non-boundary section was delivered" || ok "a non-boundary section is left out"
case "$OUT" in *"(truncated; full text in "*"INTENT.md)"*) ok "trimmed INTENT names its full text" ;; *) no "no truncation marker" ;; esac
case "$OUT" in *"heavy"*) ok "the newest titles still get room" ;; *) no "titles crowded out" ;; esac
R=$(hook startup CLAUDE_CODE_ENTRYPOINT=sdk-cli | ctx)
case "$(printf '%s' "$R" | head -3)" in *"INTENT.md in full"*) ok "a routine's first lines point at INTENT.md" ;; *) no "routine pointer missing" ;; esac
rm -f "$C/observed/heavy"*.md; cp "$T/intent.small" "$V/INTENT.md"

echo "-- only inside the vault (the hook is registered for every session) --"
OUTSIDE="$T/elsewhere"; mkdir -p "$OUTSIDE"
o=$(cd "$OUTSIDE" && printf '{"session_id":"s1","source":"startup"}' | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$V/hooks/context/floor-at-start.py"); rc=$?
[ "$rc" = 0 ] && [ -z "$o" ] && ok "process cwd outside the vault: exit 0, silent" || no "fired outside the vault" "$(printf '%s' "$o" | head -c 120)"
j=$(cd "$OUTSIDE" && $PYBIN -c 'import json,os; print(json.dumps({"session_id":"s1","source":"startup","cwd":os.getcwd()}))')
o=$(cd "$V" && printf '%s' "$j" | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$V/hooks/context/floor-at-start.py")
[ -z "$o" ] && ok "stdin cwd outside wins over a process cwd inside: silent" || no "stdin cwd ignored"
o=$(cd "$OUTSIDE" && printf '{"source":"startup"}' | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=sdk-cli $PYBIN "$V/hooks/context/floor-at-start.py")
[ -z "$o" ] && ok "a routine outside the vault gets nothing either" || no "routine fired outside the vault"
j=$(cd "$V/hooks" && $PYBIN -c 'import json,os; print(json.dumps({"session_id":"s1","source":"startup","cwd":os.getcwd()}))')
o=$(cd "$OUTSIDE" && printf '%s' "$j" | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$V/hooks/context/floor-at-start.py" | ctx)
case "$o" in *intent-marker-xyz*) ok "stdin cwd in a vault subfolder: delivered" ;; *) no "subfolder cwd skipped" ;; esac
ln -s "$V" "$T/link-to-vault" 2>/dev/null
if [ -L "$T/link-to-vault" ]; then
  o=$(cd "$T/link-to-vault" && printf '{"session_id":"s1","source":"startup"}' | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$V/hooks/context/floor-at-start.py" | ctx)
  case "$o" in *intent-marker-xyz*) ok "cwd through a symlink into the vault: delivered" ;; *) no "symlinked cwd skipped" ;; esac
  o=$(cd "$V" && printf '{"session_id":"s1","source":"startup"}' | env -u AIOS_FLOOR_AT_START CLAUDE_CODE_ENTRYPOINT=cli $PYBIN "$T/link-to-vault/hooks/context/floor-at-start.py" | ctx)
  case "$o" in *intent-marker-xyz*) ok "hook reached through a symlinked root (~/aios): delivered" ;; *) no "symlinked root skipped" ;; esac
else
  echo "  skip symlink cases (no symlinks on this filesystem)"
fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]

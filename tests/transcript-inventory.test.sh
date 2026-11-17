#!/usr/bin/env bash
# tests/transcript-inventory.test.sh
#
# hooks/security/transcript-inventory.py sorts Claude Code's session transcripts and proposes only the
# throwaways (headless and temp-folder runs past an age) for archiving. It must never propose a
# named or interactive session, and --archive must delete nothing it did not first verify in the
# archive. Fixture transcripts only: the real ~/.claude is never read here.
set -u
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
PYBIN=""; for c in python3 python "py -3"; do $c -c 'import sys' >/dev/null 2>&1 && { PYBIN="$c"; break; }; done
[ -n "$PYBIN" ] || { echo "  - skip: no python"; exit 0; }
H=hooks/security/transcript-inventory.py
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P="$T/cfg/projects/-proj"; mkdir -p "$P"
mk(){ printf '%s\n' "$2" > "$P/$1.jsonl"; touch -t "$3" "$P/$1.jsonl"; }
OLD=202001010000; NEW=$(date +%Y%m%d%H%M)
mk named-old    '{"type":"agent-name","agentName":"lawyer"}'                  $OLD
mk headless-old '{"type":"user","entrypoint":"sdk-cli","cwd":"/Users/x/aios"}' $OLD
mk headless-new '{"type":"user","entrypoint":"sdk-cli","cwd":"/Users/x/aios"}' $NEW
mk temprun-old  '{"type":"user","entrypoint":"cli","cwd":"/private/var/folders/ab/T/run1"}' $OLD
mk unnamed-old  '{"type":"user","entrypoint":"cli","cwd":"/Users/x/aios"}'    $OLD
run(){ CLAUDE_CONFIG_DIR="$T/cfg" $PYBIN "$H" "$@"; }

echo "── classes come from each transcript's own records ──"
J=$(run --json)
cls(){ printf '%s' "$J" | $PYBIN -c 'import json,sys; d=json.load(sys.stdin); print({r["path"].split("/")[-1][:-6]: r["class"] for r in d["transcripts"]}[sys.argv[1]])' "$1"; }
[ "$(cls named-old)" = named ] && [ "$(cls headless-old)" = headless ] && [ "$(cls temprun-old)" = temp-run ] && [ "$(cls unnamed-old)" = unnamed ] \
  && ok "named, headless, temp-run and unnamed are told apart" || no "a transcript was misclassified"

echo "── only old headless and temp-run transcripts are proposed ──"
C=$(printf '%s' "$J" | $PYBIN -c 'import json,sys; print(" ".join(sorted(r["path"].split("/")[-1][:-6] for r in json.load(sys.stdin)["transcripts"] if r["candidate"])))')
[ "$C" = "headless-old temprun-old" ] && ok "candidates: the old headless and temp-folder runs, nothing else" || no "wrong candidates" "$C"

echo "── --archive: verified in the archive first, then deleted; nothing else touched ──"
run --archive --to "$T/arch" >/dev/null
A=$(ls "$T/arch"/transcripts-*.tar.gz 2>/dev/null | head -1)
[ -n "$A" ] && tar -tzf "$A" | grep -q headless-old.jsonl && tar -tzf "$A" | grep -q temprun-old.jsonl \
  && ok "both candidates are in the archive" || no "the archive is missing a candidate"
[ ! -e "$P/headless-old.jsonl" ] && [ ! -e "$P/temprun-old.jsonl" ] && ok "and were deleted after it was written" || no "a candidate was not removed"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *)
  FP=$(stat -c '%a' "$A" 2>/dev/null || stat -f '%Lp' "$A"); DP=$(stat -c '%a' "$T/arch" 2>/dev/null || stat -f '%Lp' "$T/arch")
  [ "$FP" = 600 ] && [ "$DP" = 700 ] && ok "the archive is private: file 600, folder 700" || no "archive file $FP / folder $DP" "transcripts are whole sessions" ;;
esac
[ -e "$P/named-old.jsonl" ] && [ -e "$P/unnamed-old.jsonl" ] && [ -e "$P/headless-new.jsonl" ] \
  && ok "named, unnamed and recent transcripts are untouched" || no "a non-candidate was deleted"

echo "── an archive that cannot be written deletes nothing ──"
mk headless-old '{"type":"user","entrypoint":"sdk-cli"}' $OLD
: > "$T/blocker"
out=$(run --archive --to "$T/blocker/sub" 2>&1); rc=$?
[ "$rc" = 1 ] && [ -e "$P/headless-old.jsonl" ] && ok "a failed archive exits 1 and keeps every transcript" || no "a failed archive still deleted (rc=$rc)" "$out"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

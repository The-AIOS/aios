#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one. Same probe
# hooks/claude-identity/claude-identity.sh and mcps/setup.sh already use.
# $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# hooks/recall.py — the on-demand index over observed/ that the floor cannot be.
#
# The floor names every TITLE and prints the newest few bodies. An old lesson whose title does
# not name the concept is therefore invisible to a session looking for the concept, and nothing
# in the output says so. recall exists to end that miss, so the property that matters most is
# the POSITIVE CONTROL: an entry whose body holds the concept and whose title does not, among
# decoys, must come back FIRST. A recall that stops finding must fail this file, not pass it.
#
# The other properties are the contract the hook was accepted under:
#   * a hard output budget no flag can exceed (measured on the whole rendered text)
#   * it writes NOTHING -- not into the vault, not beside the hook
#   * it reads observed/ only
#   * "no results" and "could not look" are different exit codes (a silent empty screen
#     looks the same for both), and a Python without FTS5 fails LOUDLY
#   * text typed by a person (quotes, operators, '*') never reaches the FTS5 parser as syntax
# Refusal cases first, per the repo's convention for tools that must not report a partial answer.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/recall.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OBS_REL="vault/00 - notes/context/observed"

run(){ # run <args...>  -> sets OUT, ERR, RC
  OUT="$($PYBIN "$H" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}
chars(){ printf '%s\n' "$1" | $PYBIN -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))'; }
# Every file AND directory under $1 with its content hash: a before/after of this is the
# definition of "wrote nothing".
tree_state(){ $PYBIN - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
for d, dirs, files in sorted(os.walk(root)):
    dirs.sort()
    print("D", os.path.relpath(d, root))
    for f in sorted(files):
        p = os.path.join(d, f)
        print("F", os.path.relpath(p, root), os.path.getsize(p), hashlib.sha256(open(p, "rb").read()).hexdigest())
PY
}
no_traceback(){ # $1 label
  if printf '%s\n%s' "$OUT" "$ERR" | grep -E 'Traceback|sqlite3\.|OperationalError|fts5: syntax|syntax error near' >/dev/null; then
    no "$1: a raw error leaked" "$(printf '%s\n%s' "$OUT" "$ERR" | head -3)"; return 1
  fi
  return 0
}

# ── a small invented vault: generic content, no real operator data ─────────────
V="$TMP/vault1"
O="$V/$OBS_REL"
mkdir -p "$O" "$V/vault/00 - notes/context/declared" "$V/vault/00 - notes/context/ventures/acme"
cat > "$O/lessons.md" <<'EOF'
---
updated: 2026-03-02
---
# Lessons

### Cache headers for the marketing site (2026-01-10)
Set long cache headers on static assets and a short one on the HTML shell.

### Baked values outlive the thing they were baked from (2026-03-02)
The deploy kept signing in with the old token. An intermediate layer of the build cache still held
the stale secret after the rotation, so every image rebuilt from it carried the previous
credentials. Invalidate that layer whenever a secret changes.

### Build cache sizing (2026-02-14)
The runner disk fills at about eighty percent. Prune the oldest layers weekly.

### Credentials belong in the password manager (2026-02-20)
Never paste an account password into a chat window.

### Naming the weekly review (2026-02-01)
Call it the review, not the retro.

#### A fourth-level heading is not an entry
Nothing here.

###not-an-entry-without-a-space
Nothing here either.
EOF
cat > "$O/rules.md" <<'EOF'
# Rules

## Meta-patterns -- read these first

### Permisos de pago (2026-02-05)
La autorización de pagos requiere doble firma antes de enviar el archivo.

### Retry with backoff (2026-01-20)
Exponential backoff with jitter; cap at one minute.
EOF
printf '# Index\nlist of files\n' > "$O/_index.md"
printf '# Me\n### Zebracorn declared note\nzebracorn lives in declared, which recall must never read.\n' > "$V/vault/00 - notes/context/declared/about.md"
printf '# Acme\n### Zebracorn venture note\nzebracorn lives in ventures, which recall must never read.\n' > "$V/vault/00 - notes/context/ventures/acme/about.md"
ENTRIES=$(cat "$O"/*.md | grep -c '^### ')

echo
echo " refusal cases -- 'could not look' must never read as 'nothing relevant'"

run --vault "$TMP/no-such-vault" cache
[ $RC -eq 2 ] && ok "missing observed/ exits 2" || no "missing observed/ exited $RC" "an empty screen would read as 'nothing relevant'"
printf '%s' "$ERR" | grep -i 'not found' >/dev/null && [ -z "$OUT" ] \
  && ok "...says so on stderr and prints no result" || no "missing observed/ gave no stderr message or printed a result" "stdout=[$OUT] stderr=[$ERR]"

mkdir -p "$TMP/empty/$OBS_REL"
run --vault "$TMP/empty" cache
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -E 'NO MATCH' >/dev/null && printf '%s' "$OUT" | grep -E ' 0 sections in 0 files' >/dev/null; then
  ok "observed/ present but empty is exit 1 with the counts, a different answer from missing"
else
  no "empty observed/ was not 'no match, 0 sections' (rc=$RC)" "$OUT"
fi

run --vault "$V" zzqqxx
if [ $RC -eq 1 ] && printf '%s' "$OUT" | grep -E "NO MATCH.*$ENTRIES sections in 3 files" >/dev/null && [ -z "$ERR" ]; then
  ok "no results is exit 1, stdout only, and states how much it searched ($ENTRIES sections, 3 files)"
else
  no "no-results answer was wrong (rc=$RC)" "$OUT | $ERR"
fi

# A fake sqlite3 whose virtual-table creation fails the way a Python built without FTS5 does.
mkdir -p "$TMP/nofts"
cat > "$TMP/nofts/sqlite3.py" <<'EOF'
class Error(Exception): pass
class OperationalError(Error): pass
class _Conn:
    def execute(self, sql, *a, **k):
        if "fts5" in sql.lower():
            raise OperationalError("no such module: fts5")
    def executemany(self, *a, **k): pass
    def close(self): pass
def connect(*a, **k): return _Conn()
EOF
OUT="$(PYTHONPATH="$TMP/nofts" $PYBIN "$H" --vault "$V" cache 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -i 'FTS5' >/dev/null && [ -z "$OUT" ]; then
  ok "no FTS5: exit $RC, message on stderr, nothing on stdout"
else
  no "no FTS5 did not fail loudly (rc=$RC)" "stdout=[$OUT] stderr=[$ERR]"
fi
printf '%s' "$ERR" | grep 'Traceback' >/dev/null && no "no FTS5 leaked a traceback" "$ERR" || ok "...and without a traceback"
OUT="$($PYBIN "$H" --vault "$V" cache 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "control: the same call WITHOUT the fake sqlite3 works" || no "control failed (rc=$RC)" "the fake would be proving nothing"

run --vault "$V" '!!! ???'
[ $RC -eq 2 ] && printf '%s' "$ERR" | grep -i 'no searchable word' >/dev/null && ok "punctuation-only query exits 2 with a message" \
  || no "punctuation-only query (rc=$RC)" "$ERR"
no_traceback "punctuation-only" && true
for bad in "--limit 0" "--limit abc" "--excerpt -3" "--max-chars 10" "--no-such-flag"; do
  run --vault "$V" $bad cache
  if [ $RC -eq 2 ] && ! printf '%s' "$ERR" | grep 'Traceback' >/dev/null; then ok "bad usage [$bad] exits 2, no traceback"; else no "bad usage [$bad] gave rc=$RC" "$ERR"; fi
done
run --vault "$V"
[ $RC -eq 2 ] && ok "no query exits 2" || no "no query exited $RC"

echo
echo " THE POSITIVE CONTROL -- the body names the concept, the title does not"

TITLE_LINE="$(grep -F 'Baked values outlive' "$O/lessons.md")"
if printf '%s' "$TITLE_LINE" | grep -iE 'cache|credential|stale|build' >/dev/null; then
  no "fixture invalid: the target's title names the concept" "$TITLE_LINE"
else
  ok "fixture check: the target's title contains none of the query words"
fi
run --vault "$V" build cache stale credentials
FIRST="$(printf '%s\n' "$OUT" | grep -E '^1\. ')"
if [ $RC -eq 0 ] && printf '%s' "$FIRST" | grep -F 'Baked values outlive' >/dev/null; then
  ok "the entry that only the BODY names comes back FIRST, past four decoys that share its words"
else
  no "the body-only entry was not first (rc=$RC)" "first=[$FIRST]"
fi
printf '%s\n' "$OUT" | grep -iE 'stale secret|previous' >/dev/null \
  && ok "its excerpt shows the passage that matched" || no "excerpt does not show the matching passage" "$OUT"
# The mutant that makes the control bite is demonstrated in the PR, not shipped: index titles only.

echo
echo " the same sections the floor sees, and a path that is the same on every platform"

HDR="$(printf '%s\n' "$OUT" | head -1)"
printf '%s' "$HDR" | grep -E "searched $ENTRIES sections in 3 files" >/dev/null \
  && ok "indexes $ENTRIES sections: every '### ' entry, not '####' or '###x'" \
  || no "section count differs from the entries on disk ($ENTRIES)" "$HDR"
LINE_REF="$(printf '%s' "$FIRST" | sed -E 's/^1\. ([^:]*):([0-9]+) :: .*/\1|\2/')"
RELP="${LINE_REF%%|*}"; LN="${LINE_REF##*|}"
[ "$RELP" = "$OBS_REL/lessons.md" ] && ok "path is relative to the root, with forward slashes" || no "path was [$RELP]" "expected $OBS_REL/lessons.md"
printf '%s' "$OUT" | grep -F "$TMP" >/dev/null && no "output leaks the absolute temp path" || ok "no absolute path in the output"
[ "$(sed -n "${LN}p" "$V/$RELP" | tr -d '\r')" = "$TITLE_LINE" ] \
  && ok "path:line points at the entry's own heading (line $LN)" || no "line $LN is not the entry heading" "$(sed -n "${LN}p" "$V/$RELP")"
run --vault "$V" 'cache'; printf '%s' "$OUT" | grep -F '####' >/dev/null && no "a '####' heading was indexed as an entry" || ok "a fourth-level heading is not a section"

echo
echo " observed/ only, and zero writes"

run --vault "$V" zebracorn
[ $RC -eq 1 ] && ok "a word present only in declared/ and ventures/ finds nothing" || no "recall read outside observed/ (rc=$RC)" "$OUT"
cp "$V/vault/00 - notes/context/declared/about.md" "$TMP/declared.bak"
printf '### Zebracorn control (2026-03-03)\nzebracorn control entry.\n' >> "$O/rules.md"
run --vault "$V" zebracorn
[ $RC -eq 0 ] && ok "control: the same word placed in observed/ is found" || no "control failed (rc=$RC)" "$OUT"
ENTRIES=$((ENTRIES+1))

B1="$(tree_state "$V")"; HK_B="$(tree_state hooks)"
for q in 'build cache' 'autoriza' 'zzqqxx' '"' 'NEAR(' ; do $PYBIN "$H" --vault "$V" "$q" >/dev/null 2>&1; done
$PYBIN "$H" --vault "$V" --exact --all --limit 20 --excerpt 600 build cache >/dev/null 2>&1
A1="$(tree_state "$V")"; HK_A="$(tree_state hooks)"
[ "$B1" = "$A1" ] && ok "the vault is byte-identical after 7 runs (every file and directory, with hashes)" \
  || no "the vault changed" "$(diff <(printf '%s\n' "$B1") <(printf '%s\n' "$A1") | head -5)"
[ "$HK_B" = "$HK_A" ] && ok "nothing is written beside the hook either (no compiled copy, no cache)" \
  || no "hooks/ changed" "$(diff <(printf '%s\n' "$HK_B") <(printf '%s\n' "$HK_A") | head -5)"
[ ! -e "$V/.aios-run" ] && ok "no .aios-run/ folder was created" || no ".aios-run/ appeared"

echo
echo " the output budget is a ceiling no flag can pass"

# A vault built to blow the budget: many matching sections, a 5,000-character title, a 200-character
# file name, 60 KB bodies.
HV="$TMP/vault-huge"
HO="$HV/$OBS_REL"
mkdir -p "$HO"
$PYBIN - "$HO" <<'PY'
import os, sys
d = sys.argv[1]
longname = "n" * 200 + ".md"
with open(os.path.join(d, longname), "w", encoding="utf-8") as f:
    f.write("# Big\n\n")
    f.write("### " + "enormous title about widgets " * 180 + "\n")
    f.write(("widgets and gadgets and sprockets " * 2000) + "\n\n")
    for i in range(60):
        f.write("### widget entry %d\n" % i)
        f.write(("filler text with widgets " * 40) + "\n\n")
with open(os.path.join(d, "other.md"), "w", encoding="utf-8") as f:
    for i in range(40):
        f.write("### sprocket notes %d about widgets\n%s\n\n" % (i, "sprockets widgets " * 200))
PY
CAP=$(grep -E '^MAX_TOTAL_CHARS' "$H" | head -1 | sed -E 's/^MAX_TOTAL_CHARS *= *([0-9]+).*/\1/')
[ -n "$CAP" ] && ok "the ceiling is one constant in the hook (MAX_TOTAL_CHARS = $CAP)" || { no "cannot read MAX_TOTAL_CHARS"; CAP=6000; }
run --vault "$HV" widgets
N=$(chars "$OUT")
[ $RC -eq 0 ] && [ "$N" -le "$CAP" ] && ok "default flags: $N chars <= $CAP, on 100 matching sections" || no "default output was $N chars (rc=$RC)" ""
run --vault "$HV" --limit 20 --excerpt 600 widgets
printf '%s' "$OUT" | grep -iE '^\[trimmed: the [0-9]+-char cap' >/dev/null && ok "when the cap drops results the output says so" || no "the cap dropped results without saying so" "$(printf '%s\n' "$OUT" | tail -2)"
printf '%s' "$OUT" | grep -E 'more matches? not shown' >/dev/null && ok "...and says how many matches it did not show" || no "no count of unshown matches"
run --vault "$HV" enormous
printf '%s' "$OUT" | grep -iE 'trimmed' >/dev/null && ok "a shortened title or path is reported as trimmed too" || no "a 5,000-character title was cut without saying so" "$(printf '%s\n' "$OUT" | tail -2 | cut -c1-200)"

WORST=0; BAD=""
for lim in 1 5 20 999; do for ex in 1 240 99999; do for mc in 300 1000 6000 99999; do
  run --vault "$HV" --limit $lim --excerpt $ex --max-chars $mc widgets sprockets
  N=$(chars "$OUT"); EFF=$mc; [ "$EFF" -gt "$CAP" ] && EFF=$CAP
  [ "$N" -gt "$WORST" ] && WORST=$N
  if [ "$N" -gt "$EFF" ] || [ $RC -ne 0 ]; then BAD="$BAD [limit=$lim excerpt=$ex max=$mc -> $N chars rc=$RC]"; fi
done; done; done
[ -z "$BAD" ] && ok "48 flag combinations at their maxima: none exceeded its cap (largest output $WORST chars)" || no "a flag combination exceeded the cap" "$BAD"
[ "$WORST" -gt $((CAP / 2)) ] && ok "control: the cap was actually exercised (largest output is over half of it)" \
  || no "the largest output was only $WORST chars, so the cap test proves nothing" ""
run --vault "$HV" --max-chars 99999 --limit 999 --excerpt 99999 widgets
[ "$(chars "$OUT")" -le "$CAP" ] && ok "--max-chars above the ceiling is clamped to it" || no "--max-chars raised the ceiling" ""
run --vault "$HV" --max-chars 400 widgets
[ "$(chars "$OUT")" -le 400 ] && ok "--max-chars can lower the budget (400)" || no "--max-chars 400 gave $(chars "$OUT") chars" ""
run --vault "$HV" --limit 1 --max-chars 6000 widgets
[ "$(printf '%s\n' "$OUT" | grep -cE '^[0-9]+\. ')" -eq 1 ] && ok "--limit 1 shows one result" || no "--limit 1 did not limit"
printf '%s' "$OUT" | awk '{ if (length($0) > 400) bad=1 } END { exit bad }' && ok "a 5,000-character title and a 200-character file name are shortened, not printed" \
  || no "a very long line escaped the shortening"

echo
echo " a query typed by a person never reaches FTS5 as syntax"

for q in '"quoted phrase"' 'build-cache' '(cache' 'cache)' 'cache AND' 'NOT cache' 'a OR b' 'NEAR(cache credentials, 2)' 'cache*' '"unclosed' "it's" 'title:cache' '^cache' 'cache AND NOT' '{cache}' 'snowman: ☃ cache'; do
  run --vault "$V" -- "$q"
  if { [ $RC -eq 0 ] || [ $RC -eq 1 ]; } && no_traceback "query [$q]"; then ok "query [$q] -> exit $RC, no raw error"; else [ $RC -gt 1 ] && no "query [$q] -> exit $RC" "$ERR"; fi
done
run --vault "$V" -- '-cache'
{ [ $RC -le 1 ] && no_traceback "leading dash"; } && ok "a leading '-' after '--' is a plain word" || no "leading dash broke it (rc=$RC)" "$ERR"
run --vault "$V" 'NEAR(cache credentials, 2)'
printf '%s' "$OUT" | grep -F 'Baked values' >/dev/null && ok "control: operators are plain words, so the query still finds the entry" || no "operator-laden query found nothing" "$OUT"
# Past the word limit the query is cut. The dropped words were never looked for, so a NO MATCH
# has to say so: the word that would have matched sits at the end, past the limit.
LONG_Q="$($PYBIN -c 'print(" ".join("zq%d" % i for i in range(30)) + " cache")')"
run --vault "$V" "$LONG_Q"
[ $RC -eq 1 ] && printf '%s' "$OUT" | grep -F 'only the first 24 words were searched, 7 ignored' >/dev/null \
  && ok "a query cut at the word limit says so instead of a bare NO MATCH" \
  || no "the cut query did not report the words it ignored (rc=$RC)" "$OUT"
run --vault "$V" cache credentials
printf '%s' "$OUT" | grep -F 'words were searched' >/dev/null && no "control: a short query reported ignored words" "$OUT" || ok "control: a short query reports nothing ignored"

echo
echo " Spanish has no stemmer in SQLite: prefix matching is the documented answer"

run --vault "$V" autoriza
printf '%s' "$OUT" | grep -F 'Permisos de pago' >/dev/null && ok "'autoriza' finds 'autorización' (prefix, accent-insensitive)" || no "'autoriza' did not find the entry" "$OUT"
run --vault "$V" autorizacion
printf '%s' "$OUT" | grep -F 'Permisos de pago' >/dev/null && ok "'autorizacion' (no accent) finds 'autorización'" || no "accent folding failed" "$OUT"
run --vault "$V" --exact autoriza
[ $RC -eq 1 ] && ok "control: --exact does NOT find it, so the prefix is what finds it" || no "--exact still found 'autoriza' (rc=$RC)" "$OUT"
run --vault "$V" --all cache zzqqxx
[ $RC -eq 1 ] && ok "--all demands every word" || no "--all matched without every word (rc=$RC)"
run --vault "$V" cache zzqqxx
[ $RC -eq 0 ] && ok "control: the default (any word) finds it with one stray word" || no "default did not tolerate a stray word (rc=$RC)"

echo
echo " files it cannot read or decode are named, never dropped in silence"

BV="$TMP/vault-bytes"
mkdir -p "$BV/$OBS_REL"
printf '### Good entry before the bytes (2026-03-04)\nthe uniquemarker is here.\n### Bad bytes \xff\xfe entry\nmore uniquemarker \xc3\x28 text\n' > "$BV/$OBS_REL/mixed.md"
run --vault "$BV" uniquemarker
if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -i 'undecodable' >/dev/null && printf '%s' "$OUT" | grep -F 'mixed.md' >/dev/null && ! printf '%s%s' "$OUT" "$ERR" | grep Traceback >/dev/null; then
  ok "an undecodable file is indexed, flagged by name in the output, no traceback"
else
  no "undecodable bytes were mishandled (rc=$RC)" "$OUT | $ERR"
fi
if [ "$(id -u 2>/dev/null || echo 1)" != "0" ] && chmod 000 "$BV/$OBS_REL/mixed.md" 2>/dev/null && [ ! -r "$BV/$OBS_REL/mixed.md" ]; then
  printf '### Readable entry\nuniquemarker readable.\n' > "$BV/$OBS_REL/ok.md"
  run --vault "$BV" uniquemarker
  chmod 644 "$BV/$OBS_REL/mixed.md"
  if [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -E 'NOT indexed.*mixed.md' >/dev/null; then
    ok "an unreadable file is named as NOT indexed; the readable ones still answer"
  else
    no "an unreadable file was dropped silently or crashed (rc=$RC)" "$OUT | $ERR"
  fi
else
  echo "  SKIP  unreadable-file case: cannot make a file unreadable here (root, or a filesystem without modes)"
fi

echo
echo " files saved the way other platforms save them"

SV="$TMP/vault-shapes"
mkdir -p "$SV/$OBS_REL"
printf '\xef\xbb\xbf### Entry after a byte-order mark\nbommarker\n' > "$SV/$OBS_REL/bom.md"
printf '### Entry with Windows line endings\r\nbody with crlfmarker\r\n' > "$SV/$OBS_REL/crlf.md"
printf '### Decomposed accent\nautorizacio\xcc\x81n de pagos\n' > "$SV/$OBS_REL/nfd.md"
for w in bommarker crlfmarker autorizacion; do
  run --vault "$SV" "$w"
  [ $RC -eq 0 ] && ok "[$w] is found (BOM, CRLF and a decomposed accent all index like plain text)" || no "[$w] was not found (rc=$RC)" "$OUT"
done
printf '%s' "$OUT" | grep -F $'\r' >/dev/null && no "a carriage return reached the output" || ok "no carriage return in the output"

echo
echo " where the root comes from, and the prescribed invocation"

OUT="$(AIOS_ROOT="$V" $PYBIN "$H" cache 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "\$AIOS_ROOT is honoured when --vault is absent" || no "\$AIOS_ROOT ignored (rc=$RC)" "$OUT"
OUT="$(AIOS_ROOT="$TMP/no-such-vault" $PYBIN "$H" --vault "$V" cache 2>&1)"; RC=$?
[ $RC -eq 0 ] && ok "--vault wins over \$AIOS_ROOT" || no "--vault did not override the environment (rc=$RC)" "$OUT"
if grep -E 'hooks/recall\.py' hooks/_index.md | grep -F 'UV_CACHE_DIR="${TMPDIR:-/tmp}/uv-cache" uv run' >/dev/null; then
  ok "hooks/_index.md documents the sandbox-safe uv invocation"
else
  no "hooks/_index.md lacks the 'UV_CACHE_DIR=... uv run' invocation for recall.py"
fi
grep -F 'tests/recall.test.sh' hooks/_index.md >/dev/null && ok "hooks/_index.md names this test as its guard" || no "hooks/_index.md does not name tests/recall.test.sh"
if command -v uv >/dev/null 2>&1; then
  OUT="$(UV_CACHE_DIR="$TMP/uv-cache" uv run "$H" --vault "$V" build cache 2>&1)"; RC=$?
  [ $RC -eq 0 ] && ok "runs under 'uv run' with a throwaway cache" || no "uv run failed (rc=$RC)" "$OUT"
else
  echo "  SKIP  uv run: uv not on PATH"
fi
# Opt-in: nothing wires it up.
if grep -rn 'recall\.py' hooks/context-floor.py hooks/floor-at-start.py hooks/install-settings.py CLAUDE.md >/dev/null 2>&1; then
  no "recall.py is referenced from the floor, a session hook or CLAUDE.md" "it is opt-in by contract"
else
  ok "opt-in: the floor, the session hooks and CLAUDE.md do not call it"
fi
if grep -nE 'split_entries' "$H" >/dev/null && ! grep -nE '^ENTRY *=|re\.compile\(r"\^\\#\{3\}' "$H" >/dev/null; then
  ok "the section rule lives only in the floor (imported, not copied)"
else
  no "recall.py carries its own copy of the floor's entry rule" "two copies of one rule drift"
fi

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

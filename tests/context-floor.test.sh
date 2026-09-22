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
# hooks/context-floor.py — the one-call context floor
#
# The floor used to be headings only. A session could then hold every title in
# the vault and behave exactly like one that read nothing: it knew what EXISTED
# and nothing the system had LEARNED. Every /close-session and /close-day appends
# to observed/, so a titles-only floor means the compounding loop never closes at
# session start -- the operator maintains files that change no later behaviour.
#
# So the properties under test are: it emits entry BODIES and not just headings;
# the slice is BOUNDED (ten times the entries costs the same, which is what makes
# it safe where an unbounded volume was not); it globs rather than naming files;
# and it REFUSES rather than printing a short floor that looks like a full one.
# Refusal cases first (#110).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/context-floor.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# $1 root · $2 entries-per-observed-file · $3 body-words-per-entry
mkvault(){
  local r="$1" n="$2" w="$3" base i j
  base="$r/vault/00 - notes/context"; mkdir -p "$base/declared" "$base/observed"
  printf '# Index\n' > "$base/declared/_index.md"
  printf '# Index\n' > "$base/observed/_index.md"
  printf '# Quien soy\n## Origen\nprose here\n' > "$base/declared/quien-soy.md"
  { printf '# Aprendizajes\n'
    for i in $(seq 1 "$n"); do
      printf '### Entry %s\n' "$i"
      for j in $(seq 1 "$w"); do printf 'w%s ' "$j"; done
      printf '\n'
    done; } > "$base/observed/aprendizajes.md"
}

echo
echo " refusal -- a short floor looks exactly like a complete one"
$PYBIN "$H" "$TMP/absent" >/dev/null 2>&1
[ $? -eq 2 ] && ok "absent vault exits 2" || no "absent vault printed a floor" "a session cannot tell an empty floor from a full one"
mkdir -p "$TMP/half/vault/00 - notes/context/declared"
OUT="$($PYBIN "$H" "$TMP/half" 2>&1 >/dev/null)"; RC=$?
{ [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q observed; } \
  && ok "one folder present -> refuses and names the missing one" \
  || no "a half floor was emitted (rc=$RC)" "partial floors are indistinguishable from complete ones"
$PYBIN "$H" --recent notanumber >/dev/null 2>&1
[ $? -eq 2 ] && ok "a non-numeric --recent exits 2" || no "--recent accepted garbage" "it would silently fall back to a default"

echo
echo " the floor emits BODIES, not only headings"
mkvault "$TMP/v" 12 40
F="$($PYBIN "$H" "$TMP/v")"
printf '%s' "$F" | grep -q 'Entry 12' \
  && ok "the newest entry is present" || no "newest entry missing" "the last close-day's write never reaches the next session"
printf '%s' "$F" | grep -q 'w40' \
  && ok "entry BODY text is present, not just its title" \
     || no "only headings were emitted" "then the floor teaches a session nothing that was learned"
# Scope this to the RECENCY section: the map above it legitimately lists every title,
# including Entry 1, so grepping the whole output tests nothing. (First version did
# exactly that and failed on correct output.)
RECENT_ONLY="$(printf '%s\n' "$F" | awk '/MOST RECENT/{f=1} f')"
printf '%s' "$RECENT_ONLY" | grep -qE '^### Entry 1$' \
  && no "the OLDEST entry body was included" "the slice is not a tail -- it is unbounded" \
  || ok "older entry bodies are left to the map (slice is a tail)"
MAP_ONLY="$(printf '%s\n' "$F" | awk '/MOST RECENT/{exit} {print}')"
printf '%s' "$MAP_ONLY" | grep -qE '### Entry 1$' \
  && ok "older entries still appear as titles in the map" \
     || no "older entries vanished entirely" "recency is not relevance -- they must stay indexed"

echo
echo " the slice is BOUNDED -- this is what makes it safe where a volume was not"
mkvault "$TMP/small" 10 40
mkvault "$TMP/big"  100 40
WS=$($PYBIN "$H" "$TMP/small" | wc -w | tr -d ' ')
WB=$($PYBIN "$H" "$TMP/big"   | wc -w | tr -d ' ')
# 10x the entries adds 90 more TITLES to the map but the same 5 bodies. Growth must be
# roughly linear in titles, never in bodies -- a doubling here would mean it is unbounded.
if [ "$WB" -lt $(( WS * 3 )) ]; then
  ok "10x the entries grows the floor sub-linearly ($WS -> $WB words)"
else
  no "the floor grew with the corpus ($WS -> $WB words)" \
     "an unbounded floor is the original bug wearing a new name"
fi

echo
echo " ventures are LISTED, never read whole, at the floor"
# Partitioned rather than global: the floor says which ventures exist and what each
# holds; the worker opens the one its task touches. Reading them all at the floor would
# more than double it (108,646 words on a live vault).
VD="$TMP/v/vault/00 - notes/context/ventures"
mkdir -p "$VD/acme" "$VD/globex"
printf '# Ventures\n' > "$VD/_index.md"
printf '# Acme\n' > "$VD/acme/about_venture.md"
for i in $(seq 1 300); do printf 'secretword '; done >> "$VD/acme/pricing.md"
printf '# Globex\n' > "$VD/globex/about_venture.md"
FV="$($PYBIN "$H" "$TMP/v")"
printf '%s' "$FV" | grep -q 'acme' && printf '%s' "$FV" | grep -q 'globex' \
  && ok "every venture is listed at the floor" \
  || no "a venture was not listed" "a worker cannot open what it does not know exists"
printf '%s' "$FV" | grep -q 'pricing.md' \
  && ok "each venture's files are named" || no "venture files not listed" "the listing is the index into the folder"
printf '%s' "$FV" | grep -q 'secretword' \
  && no "a venture's BODY was read at the floor" "that more than doubles the floor on a real vault" \
  || ok "venture bodies are NOT read at the floor"

echo
echo " arbitrary vault shape"
printf '%s' "$F" | grep -q 'aprendizajes.md' \
  && ok "globs files matching no canonical name" \
     || no "a non-canonically-named file was skipped" "operators rename these and write them in their own language"
$PYBIN tests/lint-no-hardcoded-context-names.py "$H" >/dev/null 2>&1 \
  && ok "no canonical filename is matched on in the hook's logic" \
  || no "the hook hardcodes a canonical filename in CODE" "that matcher goes stale silently, per the renamed-vault case"

echo
echo " --json carries the same thing the text does"
$PYBIN "$H" --json "$TMP/v" | $PYBIN -c "
import json,sys
d=json.load(sys.stdin)
assert d['recent_per_file']==5, d['recent_per_file']
o=[x for x in d['observed'] if x['file']=='aprendizajes.md'][0]
assert len(o['recent'])==5, len(o['recent'])
assert len(o['headings'])>=12, len(o['headings'])
assert 'w40' in o['recent'][-1], 'bodies missing from json'
" 2>/dev/null \
  && ok "--json: 5 recent bodies plus the full heading map" \
  || no "--json shape is wrong" "the machine-readable path must match the human one"

echo
echo " rule-library detection (#150) -- the index is the SECTION, marked by a section heading"
# One fixture per failure the audit named. Each builds only what it needs, so a failure
# names exactly one cause.
lib(){ # $1 root · stdin = the observed file's body → prints the hook's antifragile block
  local base="$1/vault/00 - notes/context"; mkdir -p "$base/declared" "$base/observed"
  printf '# Index\n' > "$base/declared/_index.md"; printf '# Index\n' > "$base/observed/_index.md"
  printf '# Quien soy\n' > "$base/declared/quien-soy.md"
  cat > "$base/observed/antifragile.md"
  $PYBIN "$H" "$1" 2>&1 | awk '/^### FILE: antifragile\.md/{f=1} f&&/^### FILE: /&&!/antifragile/{exit} f'
}

# (a) the canonical seed's own heading, plural, and nothing else that could match
OUT=$(printf '# Antifragile\n## Patterns of fragility (what breaks and why)\n### N. Short description (date)\nbody\n## Meta-patterns (what the failures have in common)\n### A. First pattern\nprose A\n' | lib "$TMP/lib-a")
printf '%s' "$OUT" | grep -q 'RULE LIBRARY' \
  && ok "(a) the seed's plural '## Meta-patterns' marks a rule library" \
  || no "(a) '## Meta-patterns' is not detected" "a vault running the seed as shipped gets its newest bodies instead of its index"

# (b) an ENTRY whose title says "index" must never classify the file
OUT=$(printf '# Aprendizajes\n### 1. First lesson (2026-01-01)\nbody one\n### 12. Index updated without updating project note (2026-02-01)\nbody twelve\n' | lib "$TMP/lib-b")
printf '%s' "$OUT" | grep -q 'RULE LIBRARY' \
  && no "(b) a ### entry titled 'Index …' classified the file as a rule library" "an entry title is not a section marker -- the first hit won" \
  || ok "(b) a ### entry titled 'Index …' does not make a file a rule library"

# (c) the section includes its ### children and stops at the next ## -- and control
OUT=$(printf '# Antifragile\n## Meta-patterns (read these first)\nintro\n### A. Pattern alpha\nalpha body\n### B. Pattern beta\nbeta body\n## Patterns of fragility (numbered entries)\n### 1. Not part of the index\nentry body\n' | lib "$TMP/lib-c")
if printf '%s' "$OUT" | grep -q 'alpha body' && printf '%s' "$OUT" | grep -q 'beta body'; then
  ok "(c) the index carries its ### patterns, not just the heading and one sentence"
else
  no "(c) the index stopped at the first ###" "sessions get the heading and none of the patterns -- 0 of 23 on a live vault"
fi
printf '%s' "$OUT" | grep -q 'Not part of the index' \
  && no "(c) control: the index ran past the next ## section" "the section boundary is not being honoured" \
  || ok "(c) control: the index stops at the next ## -- a numbered entry is not swept in"

# (d) an unreadable observed file must refuse, like a missing folder does
D="$TMP/lib-d/vault/00 - notes/context"; mkdir -p "$D/declared" "$D/observed"
printf '# Index\n' > "$D/declared/_index.md"; printf '# Index\n' > "$D/observed/_index.md"
printf '# Quien soy\n' > "$D/declared/quien-soy.md"; printf '# Readable\n### One\nbody\n' > "$D/observed/fine.md"
printf '# Hidden\n### Two\nbody\n' > "$D/observed/locked.md"; chmod 000 "$D/observed/locked.md"
if [ -r "$D/observed/locked.md" ]; then
  printf '  SKIP  (d) running as a user who can read a mode-000 file (root?) -- cannot reproduce\n'
else
  $PYBIN "$H" "$TMP/lib-d" >/dev/null 2>"$TMP/lib-d.err"; rc=$?
  { [ "$rc" -eq 2 ] && grep -q 'locked.md' "$TMP/lib-d.err"; } \
    && ok "(d) an unreadable observed file refuses (exit 2) and names the file" \
    || no "(d) an unreadable file dropped out silently" "exit=$rc -- the floor printed as complete with a file missing"
fi
chmod 644 "$D/observed/locked.md" 2>/dev/null

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

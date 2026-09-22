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
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

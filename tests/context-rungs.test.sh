#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hooks/context-rungs.py — the measurement behind /aios:housekeeping Bucket 31
# and the `right-context` skill.
#
# The whole reason this tool exists is that a CONSTANT was baked into a rule
# about a quantity that grows: "read everything" was correct when written (a
# fresh clone's whole context is a few thousand tokens) and silently stopped
# being correct as vaults grew past six figures. Nothing reported the crossing.
#
# So the two properties that matter are (a) the verdict FLIPS with vault size --
# a tool that always says the same thing is a constant with extra steps -- and
# (b) it REFUSES rather than reporting a partial ladder, because a total built
# from one folder reads as SMALL, which is the answer that talks a session out
# of loading anything. Refusal cases first, per antifragile #110.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/context-rungs.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Build a vault whose declared/ and observed/ hold N words each, in `###` entries.
mkvault(){ # $1 root · $2 declared-words · $3 observed-words
  local r="$1" d="$2" o="$3" base
  base="$r/vault/00 - notes/context"
  mkdir -p "$base/declared" "$base/observed"
  printf '# Index\nfile list\n' > "$base/declared/_index.md"
  printf '# Index\nfile list\n' > "$base/observed/_index.md"
  { printf '### Entry one\n'; for _ in $(seq 1 "$d"); do printf 'word '; done; printf '\n'; } > "$base/declared/about_me.md"
  { printf '### Entry one\n'; for _ in $(seq 1 "$o"); do printf 'word '; done; printf '\n'; } > "$base/observed/patterns.md"
}

echo
echo " refusal cases -- a measurement that cannot fail reports 'fine' when broken"

python3 "$H" "$TMP/nothing-here" >/dev/null 2>&1
[ $? -eq 2 ] && ok "absent vault exits 2, does not print a ladder" \
             || no "absent vault did not exit 2" "a zero-word ladder reads as 'cheap, read it all'"

mkdir -p "$TMP/half/vault/00 - notes/context/declared"
OUT="$(python3 "$H" "$TMP/half" 2>&1 >/dev/null)"; RC=$?
if [ $RC -eq 2 ] && printf '%s' "$OUT" | grep -q "observed"; then
  ok "one folder present -> refuses AND names the missing folder"
else
  no "a half-measured vault produced a ladder (rc=$RC)" \
     "a total built from one folder reads as SMALL -- the answer that skips context entirely"
fi

mkdir -p "$TMP/half/vault/00 - notes/context/observed"
python3 "$H" "$TMP/half" >/dev/null 2>&1
[ $? -eq 2 ] && ok "both folders present but empty exits 2" \
             || no "an empty context measured as a real ladder" "empty must resolve to a refusal, not to zero"

echo
echo " the verdict FLIPS with vault size -- the property the tool exists for"

mkvault "$TMP/small" 300 300
S="$(python3 "$H" "$TMP/small")"
if printf '%s' "$S" | grep -qi "read ALL of it"; then
  ok "small vault is told to read everything"
else
  no "small vault was not told to read everything" \
     "the ladder is not for a vault whose whole context is cheaper than the rule describing it"
fi

mkvault "$TMP/big" 4000 60000
B="$(python3 "$H" "$TMP/big")"
if printf '%s' "$B" | grep -qi "too much to spend"; then
  ok "grown vault is told to floor at rung 1"
else
  no "grown vault was not told to narrow" "that is the case the whole ladder exists for"
fi

# THE CONTROL. If both sizes produce the same verdict, the tool is a constant with
# extra steps and every assertion above is vacuous.
if [ "$(printf '%s' "$S" | grep -ci 'read ALL of it')" != "$(printf '%s' "$B" | grep -ci 'read ALL of it')" ]; then
  ok "control: the two verdicts genuinely differ"
else
  no "control FAILED: small and grown vaults got the same verdict" \
     "a verdict that never changes is a hardcoded constant -- exactly what this replaces"
fi

echo
echo " the ladder is monotonic and complete"

J="$(python3 "$H" --json "$TMP/big")"
python3 - "$J" <<'PY'
import json, sys
d = json.loads(sys.argv[1]); r = d["rungs"]
assert len(r) == 4, "expected 4 rungs, got %d" % len(r)
w = [x["words"] for x in r]
assert w == sorted(w), "rungs are not monotonic: %s" % w
assert w[0] > 0, "rung 0 is zero -- an index that costs nothing was not measured"
assert all(x["tokens_est"] > 0 for x in r), "a rung reported zero tokens"
PY
[ $? -eq 0 ] && ok "--json: 4 rungs, strictly non-decreasing, none zero" \
             || no "--json ladder is malformed or non-monotonic" "a rung that shrinks as you climb is a counting bug"

printf '%s' "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d['ratio_observed_to_declared']>1 else 1)" \
  && ok "--json reports the observed/declared ratio" \
  || no "ratio missing or wrong" "the ratio is what the prose files cite instead of a hardcoded volume"

echo
echo " no consumer hardcodes a volume the tool is supposed to answer"

# CLAUDE.md and the wrappers may name a MAGNITUDE ("six figures of tokens") -- that is a
# statement about scale that stays true. What they must not carry is a specific vault's
# number, which is the thing that silently went stale.
for f in CLAUDE.md AGENTS.md; do
  if grep -qE '~[0-9]+k words' "$f"; then
    no "$f hardcodes a per-vault word count" "that number is why the old rule went stale unnoticed"
  else
    ok "$f states no hardcoded context volume"
  fi
done

grep -q 'context-rungs.py' plugins/aios/commands/housekeeping.md \
  && ok "housekeeping Bucket 31 calls the tool" \
  || no "no bucket runs the measurement" "an unmeasured ladder goes stale exactly like the constant did"

grep -q 'context-rungs.py' skills/aios/right-context/SKILL.md \
  && ok "the right-context skill sends you to measure before reasoning about cost" \
  || no "the skill reasons about cost without measuring" "that is how the original constant got written down"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

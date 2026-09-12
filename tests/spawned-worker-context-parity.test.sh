#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A spawned worker's context rule is stated TWICE — the two copies must agree
#
# A worker is born on two paths, and only one of them reads the wrapper:
#   · `spawn` typed in a terminal  → hooks/claude-identity/install-wrappers.sh
#                                    injects the preamble into the task file
#   · a surface fulfilling an inbox request → never reads that file, and is
#                                    governed by CLAUDE.md § Identity & Greeting
#                                    step 4 alone
#
# So the rule lives in two hand-maintained places that are read by different
# audiences at different moments. The dangerous half of the rule is the FLOOR —
# the observed files a worker reads every time regardless of the task — because
# dropping it fails silently: the worker still answers, still sounds right, and
# is simply missing the context that made the answer this operator's rather than
# merely correct. No error, no tell, and the surface-fulfilled path is the one
# with no second copy to fall back on.
#
# This asserts AGREEMENT, deriving the floor from the preamble rather than
# hardcoding a list of its own — a canonical-side list would be a third copy,
# which is the thing being prevented. It also refuses to pass vacuously on an
# empty floor, because "every file in an empty set is present" is true and
# useless.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

CM="CLAUDE.md"
WR="hooks/claude-identity/install-wrappers.sh"

printf '\n spawned-worker context parity\n\n'

# ── the wrapper path ────────────────────────────────────────────────────────
PREAMBLE="$(sed -n '/^_spawn_task_preamble() {/,/^}/p' "$WR")"
if [ -n "$PREAMBLE" ]; then
  ok "the wrapper defines _spawn_task_preamble"
else
  no "the wrapper defines _spawn_task_preamble" "not found in $WR"
fi

if grep -q '_spawn_task_preamble; printf' "$WR"; then
  ok "the preamble is actually written into the task file"
else
  no "the preamble is actually written into the task file" \
     "defining it is not wiring it — the task file must open with it"
fi

# ── the floor, derived from the preamble ────────────────────────────────────
FLOOR="$(printf '%s\n' "$PREAMBLE" | grep -oE 'observed/[a-z-]+\.md' | sort -u)"
COUNT="$(printf '%s' "$FLOOR" | grep -c . || true)"

if [ "$COUNT" -ge 2 ]; then
  ok "the preamble names a floor of observed files ($COUNT)"
else
  no "the preamble names a floor of observed files" \
     "found $COUNT — an empty or near-empty floor would make the parity check below vacuous"
fi

# ── CLAUDE.md step 4 ────────────────────────────────────────────────────────
STEP4="$(grep -n '^4\. After greeting' "$CM" | head -1 | cut -d: -f2-)"
if printf '%s' "$STEP4" | grep -q 'on demand'; then
  ok "CLAUDE.md step 4 states the on-demand rule"
else
  no "CLAUDE.md step 4 states the on-demand rule" "got: ${STEP4:0:80}"
fi

# ── the assertion that matters ──────────────────────────────────────────────
MISSING=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base="${f#observed/}"
  printf '%s' "$STEP4" | grep -q "$base" || MISSING="$MISSING $base"
done <<< "$FLOOR"

if [ -z "$MISSING" ] && [ "$COUNT" -ge 2 ]; then
  ok "every floor file in the preamble is also named in CLAUDE.md step 4"
else
  no "every floor file in the preamble is also named in CLAUDE.md step 4" \
     "missing from step 4:${MISSING:- (floor was empty)} — a surface-spawned worker would skip them silently"
fi

# ── the floor files exist in the shipped template vault ─────────────────────
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -f "vault/00 - notes/context/$f" ]; then
    ok "floor file ships in the template vault: $f"
  else
    no "floor file ships in the template vault: $f" "a floor pointing at a file no vault has is a dead rule"
  fi
done <<< "$FLOOR"

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

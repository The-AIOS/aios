#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A spawned worker's context rule is stated in FOUR places — all four must agree
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
#
# EXTENDED after review: there were FOUR copies, not two, and the two that were
# missed are the wrapper's own DEFAULT TASK on each platform — the text used when
# `spawn <name>` is called with no task. That default said "load my declared +
# observed context" while the preamble beside it said not to preload, so a
# no-task spawn wrote both instructions into one file and told the worker to do
# opposite things. Windows had no preamble at all, so the change reached two
# platforms of three. A parity suite that compares only the copies you remembered
# is the same failure it exists to prevent, one level up.
#
# Comments are STRIPPED before matching (antifragile #105): the fix's own comment
# quotes the string it removed, and a whole-file grep cannot tell an explanation
# from an instruction.
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
# Step 4 is a BLOCK, not a line: it carries sub-points (the floor, the output
# question, the unsure case). Extracting only the first line -- which the first
# version did, when step 4 happened to be one line -- silently measures a fraction
# of the rule and reports on the rest. Read to the start of step 5.
STEP4="$(awk '/^4\. After greeting/{f=1} f&&/^5\. \*\*When the task is done/{exit} f' "$CM")"
# Assert the RULE, not the wording (#105): a check pinned to the phrase "on demand"
# fails the moment the prose improves, which is exactly what happened on review.
# What must be true is that step 4 sizes the read to the work and names a floor.
if printf '%s' "$STEP4" | grep -qiE 'always, whatever the task|floor' \
   && printf '%s' "$STEP4" | grep -qiE 'the map is enough|only what this task touches|only the files this task touches'; then
  ok "CLAUDE.md step 4 states both halves: an unconditional read and a sized one"
else
  no "CLAUDE.md step 4 must state a floor AND a sized read" "got: ${STEP4:0:120}"
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

# ── the copies the first version missed ─────────────────────────────────────
echo
echo " the wrapper's DEFAULT TASK must not restate the rule"
PS1="hooks/claude-identity/install-wrappers.ps1"
# Strip comments first. The commit that removed the contradicting string explains
# itself in a comment that necessarily contains it (#105) -- matching raw text here
# would report a defect that is only an explanation.
code_sh="$(sed 's/^[[:space:]]*#.*//' "$WR")"
code_ps="$(sed 's/^[[:space:]]*#.*//' "$PS1")"
for pair in "sh:$code_sh" "ps1:$code_ps"; do
  label="${pair%%:*}"; body="${pair#*:}"
  if printf '%s' "$body" | grep -q 'load my declared + observed context'; then
    no "$label default task tells the worker to preload" \
       "the preamble in the same file says the opposite; a no-task spawn gets both"
  else
    ok "$label default task does not contradict the preamble"
  fi
done

echo
echo " Windows gets the preamble too, or the change reaches two platforms of three"
if grep -qiE 'Before the task' "$PS1" && grep -q 'taskPreamble' "$PS1"; then
  ok "the .ps1 injects a context preamble"
else
  no "the .ps1 writes its task file with no preamble" \
     "a Windows-spawned worker then boots with no operator context at all"
fi
# the floor must be the SAME two files on both platforms -- derived, never restated
floor_sh="$(printf '%s' "$PREAMBLE" | grep -oE 'observed/[a-z]+\.md' | sort -u | tr '\n' ' ')"
floor_ps="$(grep -oE 'observed/[a-z]+\.md' "$PS1" | sort -u | tr '\n' ' ')"
if [ -z "$floor_sh" ]; then
  no "no floor derivable from the wrapper preamble — this check would pass vacuously"
elif [ "$floor_sh" = "$floor_ps" ]; then
  ok "both platforms name the same floor ($floor_sh)"
else
  no "the floor differs by platform" "sh: $floor_sh | ps1: $floor_ps"
fi

echo
echo " the rule is keyed on the WORK, not on being a worker"
# The review that produced this: keying on identity makes every spawned agent
# permanently thinner than the primary session -- including the agents whose whole
# job is to sound like the operator. The discriminator must be the output.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  # Match the RULE, not the phrasing (#105). The .ps1 says "the words of the operator"
  # because it must avoid apostrophes -- it lives inside a single-quoted here-string --
  # and a check pinned to one file's wording fails on a change that is purely mechanical.
  # What must be true everywhere: the test is keyed on the OUTPUT acting for the operator.
  if grep -qiE "act on their behalf|act on behalf of the operator|words of the operator" "$f"; then
    ok "$label asks the output question"
  else
    no "$label does not state the work-shape test" \
       "without it the rule reads as 'workers get less', which is the thing being avoided"
  fi
done
grep -qiE 'unsure is not a third answer|[Uu]nsure .*read the full' "$CM" \
  && ok "CLAUDE.md resolves the unsure case toward the full ritual" \
  || no "the unsure case is unresolved" "the two errors are asymmetric; silence favours under-reading"

echo
echo " the skipped context is named as available, not merely skipped"
# Operator-raised. Without this the rule reads as a one-time boot decision, and a worker that
# discovers mid-task that it needed the voice file has no signal that reaching for it is allowed.
# Naming what was NOT read -- and that it can be opened later -- is what makes a narrowed floor
# recoverable instead of a silent ceiling.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  # Match fragments that survive LINE WRAPPING. The full sentence "NOT because it is off
  # limits" wraps between "it" and "is" in the preambles, so a single-line grep for it
  # scores zero on text that plainly contains it -- the check failed on correct files.
  # Two short, distinctive fragments, each of which fits on one line by construction.
  if grep -qi "off limits" "$f" && grep -qi "not exceptional" "$f"; then
    ok "$label tells the worker the rest is available mid-task"
  else
    no "$label does not say the unread context may be opened later" \
       "a narrowed floor with no route back is a ceiling"
  fi
done
# and it must name the scale, or "the rest" is an abstraction nobody acts on
grep -qiE '150k tokens|100k words|120k words|six figures of tokens' "$CM" \
  && ok "CLAUDE.md names how much is being skipped" \
  || no "the skipped volume is unquantified" "a worker cannot weigh a cost it cannot see"

echo
echo " the two folders are read differently -- the split that makes this work"
# Measured: a worker told to read ALL of both folders for a two-sentence task spent 38 tool
# calls and never delivered. Told to read the MAP plus declared/, it delivered in 26 -- in
# the operator's voice, applying a per-surface rule from their own files. declared/ is
# identity prose that does not index; observed/ is entries that do. Collapsing the two back
# into "read everything" is the failure that made the original rule get ignored.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  if grep -qiE "ALL of .?context/declared|all of .vault/00 - notes/context/declared" "$f"; then
    ok "$label routes operator-voice work to declared/"
  else
    no "$label does not name declared/ as the voice-work read" "that folder is what makes output sound like them"
  fi
  if grep -qiE "does not index|indexes beautifully|titles are a better index" "$f"; then
    ok "$label explains WHY the two folders are read differently"
  else
    no "$label states the split without its reason" "an unexplained rule gets collapsed back on the next edit"
  fi
done
grep -qiE "not need 100k words|do NOT also preload all of observed" "$WR" \
  && ok "the wrapper warns against preloading all of observed for voice work" \
  || no "nothing stops the yes-branch collapsing into read-everything" "that shape spent 38 calls and delivered nothing"

echo
echo " the narrowing stays measured"
HK="plugins/aios/commands/housekeeping.md"
if grep -q "Spawned workers that loaded no operator context" "$HK"; then
  ok "housekeeping reports workers that loaded nothing"
else
  no "nothing measures whether the floor is firing" \
     "a narrowing justified by a measurement must keep being measured, or the justification expires silently"
fi
grep -qiE 'Primary sessions are the CONTROL' "$HK" \
  && ok "and that check carries its own control" \
  || no "the bucket has no control" "a scan that cannot see a primary's reads cannot be trusted about a worker's"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

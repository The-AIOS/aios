#!/usr/bin/env bash
# tests/ci-failure-explainer.test.sh
#
# Asserts the failed-check explainer stays wired, and that what it writes is usable by someone
# who does not read CI logs.
#
# WHY THE WIRING NEEDS A TEST OF ITS OWN. The explainer is a job that runs only when another job
# failed, and it reaches only the jobs named in its `needs:`. A job added later and not wired in
# therefore fails while the summary reports a clean run — the failure mode is a CONFIDENT LIE,
# and it shows up on the one run where someone is already confused. So the job list is derived
# from the workflow here and compared against the `needs:` block, with a control proving the
# comparison can fail.
#
# The rendering is tested offline, from a fixed table of failures, because a summary generator
# that can only be exercised by pushing a deliberately broken branch is one that gets verified
# once and then drifts.
#
# Run:  bash tests/ci-failure-explainer.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WF="$REPO/.github/workflows/validate.yml"
SCRIPT="$REPO/.github/scripts/explain-failure.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

[ -f "$WF" ]     || { printf '  FAIL  %s missing\n' "$WF"; exit 1; }
[ -f "$SCRIPT" ] || { printf '  FAIL  %s missing\n' "$SCRIPT"; exit 1; }

# Job ids are the two-space-indented keys under `jobs:`; the explainer is the one being checked.
job_ids() { awk '/^jobs:/{injobs=1; next} injobs && /^  [A-Za-z0-9_-]+:$/{gsub(/[ :]/,""); print}' "$WF"; }
explain_block() { awk '/^  explain:$/{on=1; next} on && /^  [A-Za-z0-9_-]+:$/{exit} on' "$WF"; }
needs_list() {
  awk '/^  explain:$/{injob=1} injob && /^    needs:$/{inneeds=1; next}
       inneeds && /^      - /{sub(/^      - /,""); print; next}
       inneeds && !/^      - /{exit}' "$WF"
}

echo "-- 1. every job reaches the explainer --"
MISSING=""
for j in $(job_ids); do
  [ "$j" = "explain" ] && continue
  needs_list | grep -qx "$j" || MISSING="$MISSING $j"
done
if [ -z "$MISSING" ]; then ok "every job in validate.yml is in explain's needs"
else no "jobs missing from explain's needs:$MISSING" "a job outside that list fails while the summary says nothing"; fi

# CONTROL: the comparison must be able to fail, or it is measuring nothing.
if needs_list | grep -qx "a-job-that-does-not-exist"; then
  no "the control matched a job that does not exist — the needs parser is not reading the file"
else ok "control: the needs parser answers no for a job that is not listed"; fi
[ "$(job_ids | grep -c .)" -ge 10 ] && ok "the job parser sees the real job list ($(job_ids | grep -c .) jobs)" \
  || no "the job parser found almost nothing — it is not reading validate.yml"

echo
echo "-- 2. the explainer only runs on failure, and cannot be skipped by one --"
explain_block | grep -q "always()" \
  && ok "gated with always(), so a failed dependency does not skip it" \
  || no "explain has no always() — a failed job would SKIP its own explainer"
explain_block | grep -q "contains(needs.\*.result, 'failure')" \
  && ok "and it writes nothing on a green run" \
  || no "explain is not restricted to failed runs"
explain_block | grep -q 'actions: read' \
  && explain_block | grep -q 'checks: read' \
  && ok "it asks for the two read scopes it needs (jobs + annotations)" \
  || no "explain cannot read this run's jobs or its annotations" "the summary would be empty"

echo
echo "-- 3. the local command is DERIVED from the workflow, never from a table --"
# A step whose run: is a single line must yield exactly that line.
STEP="$(awk '/^      - name: /{n=$0; sub(/^      - name: /,"",n)} /^        run: bash tests\//{print n; exit}' "$WF")"
EXPECT="$(awk -v want="$STEP" '/^      - name: /{n=$0; sub(/^      - name: /,"",n)} n==want && /^        run: /{c=$0; sub(/^        run: /,"",c); print c; exit}' "$WF")"
GOT="$(bash "$SCRIPT" --command-for "$STEP")"
[ -n "$STEP" ] && [ "$GOT" = "$EXPECT" ] \
  && ok "\"$STEP\" -> $GOT" \
  || no "derivation returned '$GOT' for \"$STEP\"" "expected '$EXPECT'"

# A multi-line run: block has no single command, and saying so beats inventing one.
MULTI="$(awk '/^      - name: /{n=$0; sub(/^      - name: /,"",n)} /^        run: \|/{print n; exit}' "$WF")"
[ -z "$(bash "$SCRIPT" --command-for "$MULTI")" ] \
  && ok "an inline check answers empty instead of a command that does not exist" \
  || no "a multi-line step produced a command" "it would print the first line of a script as if it were runnable"

[ -z "$(bash "$SCRIPT" --command-for 'no such step exists here')" ] \
  && ok "an unknown step answers empty rather than failing" \
  || no "an unknown step produced output"

echo
echo "-- 4. what it writes is readable by someone who does not read CI logs --"
TSV="$(mktemp)"; OUT="$(mktemp)"
printf 'Repo structure\tRequired top-level files exist\tMissing required file: TOOLS.md\n' > "$TSV"
printf '%s\t%s\t\n' "Commit primitives" "$STEP" >> "$TSV"
( cd "$REPO" && bash "$SCRIPT" --render "$TSV" > "$OUT" )

grep -q 'Missing required file: TOOLS.md' "$OUT" && ok "it repeats the check's own error message" \
  || no "the error message the check emitted is not in the summary"
grep -q "$(printf '%s' "$EXPECT" | cut -c1-40)" "$OUT" && ok "it names the command to run locally" \
  || no "no local command in the summary"
grep -qi 'nothing on your computer is broken' "$OUT" && ok "it says what did NOT happen, which is the first question" \
  || no "the summary does not say the operator's machine is fine"
grep -qi 'paste this into your AIOS session' "$OUT" && ok "and it offers a copy-paste route for a non-technical author" \
  || no "no copy-paste fallback — the summary assumes the reader can act on it alone"
# It must not answer with jargon only a maintainer can decode.
grep -qiE 'annotation_level|check-run id|::error::' "$OUT" \
  && no "the summary leaks CI internals into the operator-facing text" \
  || ok "no CI internals in the text"

# An empty run (cancelled, or a job that died before starting) must still say something.
: > "$TSV"
( cd "$REPO" && bash "$SCRIPT" --render "$TSV" > "$OUT" )
grep -qi 'no failed step was reported' "$OUT" && ok "an empty collection still explains itself" \
  || no "an empty collection renders a summary with no verdict"
rm -f "$TSV" "$OUT"

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

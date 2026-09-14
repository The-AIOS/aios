#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Write the run summary a failed check points at — in plain language.
#
# WHAT THIS FIXES. When a check fails, GitHub emails the author one line:
#
#     [The-AIOS/aios] PR run failed: <workflow> - <PR title> (<sha>)
#
# and a link. The link opens a run page whose summary is empty, so the only
# place the reason exists is a log inside one of fifteen jobs, in a workflow
# 1,900 lines long. A contributor who reads code finds it in a few minutes. A
# contributor who does not is told, in effect, "something you did is wrong,
# somewhere" — which is the one message a first contribution cannot survive.
#
# Reported by a contributor who received exactly that mail and could not act on
# it. The fix is not a kinder subject line: it is that the page the mail already
# links to says what failed, what it means, and what to run.
#
# WHAT IT WRITES. For every failed step: the check's own error message (the
# `::error::` annotation the step already emits), and the command that
# reproduces it locally — DERIVED FROM THE WORKFLOW, never from a table kept
# here. A table would be a second copy of a fact that moves, and it would go
# stale in the direction that matters: silently, while still printing something.
#
# Usage:
#   explain-failure.sh                  # in CI: this run's failures → $GITHUB_STEP_SUMMARY
#   explain-failure.sh --render FILE    # render from a collected TSV (tests)
#   explain-failure.sh --command-for "<step name>"   # just the derivation (tests)
#
# The three modes exist so the rendering and the derivation are testable with no
# network and no GitHub: a summary generator nobody can run offline is one that
# gets verified by pushing a deliberately broken branch, which is how a failure
# explainer ends up untested.
# ─────────────────────────────────────────────────────────────────────────────
set -u

WORKFLOW="${AIOS_WORKFLOW_FILE:-.github/workflows/validate.yml}"

# ── the derivation ───────────────────────────────────────────────────────────
# A step's local command is the single-line `run:` in its own block. Steps whose
# `run:` is a multi-line block (`run: |`) are inline checks with no local
# equivalent; those answer empty, and the caller says so in words rather than
# printing a command that does not exist.
command_for() {
  awk -v want="$1" '
    # a step begins at "- name: <something>"; anything before the next step
    # belongs to it
    /^[[:space:]]*-[[:space:]]+name:[[:space:]]/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "", line)
      inblock = (line == want)
      next
    }
    /^[[:space:]]*-[[:space:]]+uses:[[:space:]]/ { inblock = 0; next }
    inblock && /^[[:space:]]*run:[[:space:]]*\|/ { inblock = 0; next }   # multi-line: no single command
    inblock && /^[[:space:]]*run:[[:space:]]/ {
      cmd = $0
      sub(/^[[:space:]]*run:[[:space:]]*/, "", cmd)
      print cmd
      exit
    }
  ' "$WORKFLOW"
}

# ── collect (the only part that needs the network) ───────────────────────────
# Emits one TSV line per failed step: job <TAB> step <TAB> message
# The message is the step's own `::error::` annotation when it emitted one —
# GitHub records those per check run, and a job's id IS its check-run id.
collect() {
  local run_id="${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
  local repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
  local jobs job_id job_name

  jobs="$(gh api "repos/$repo/actions/runs/$run_id/jobs?per_page=100" \
          --jq '.jobs[] | select(.conclusion == "failure") | "\(.id)\t\(.name)"')" || return 1

  printf '%s\n' "$jobs" | while IFS="$(printf '\t')" read -r job_id job_name; do
    [ -n "${job_id:-}" ] || continue

    # the failed steps of this job
    local steps
    steps="$(gh api "repos/$repo/actions/runs/$run_id/jobs?per_page=100" \
             --jq ".jobs[] | select(.id == $job_id) | .steps[] | select(.conclusion == \"failure\") | .name")"
    # the annotations this job produced — the check's own ::error:: text.
    # `Process completed with exit code N` is the RUNNER's
    # annotation, not the check's: it appears on every failure and says nothing, so it is
    # dropped rather than printed as if it were a finding.
    local notes
    notes="$(gh api "repos/$repo/check-runs/$job_id/annotations" \
             --jq '.[] | select(.annotation_level == "failure") | .message' 2>/dev/null \
             | grep -v '^Process completed with exit code' | head -3)"

    if [ -z "$steps" ]; then steps="(the job itself)"; fi
    printf '%s\n' "$steps" | while IFS= read -r step; do
      printf '%s\t%s\t%s\n' "$job_name" "$step" "$(printf '%s' "$notes" | head -1)"
    done
  done
}

# ── render (pure) ────────────────────────────────────────────────────────────
render() {
  local any=0 job step msg cmd
  printf '## A check did not pass — here is what to do\n\n'
  printf 'Nothing on your computer is broken, and nothing was published. These checks run on\n'
  printf "GitHub's machines against the change in this pull request.\n\n"

  while IFS="$(printf '\t')" read -r job step msg; do
    [ -n "${job:-}" ] || continue
    any=1
    printf '### %s — %s\n\n' "$job" "$step"
    if [ -n "${msg:-}" ]; then
      printf '**What it found:** %s\n\n' "$msg"
    fi
    cmd="$(command_for "$step")"
    if [ -n "$cmd" ]; then
      printf '**Run this on your machine to see the same thing:**\n\n```bash\n%s\n```\n\n' "$cmd"
    else
      printf '**This check runs inline in CI** — there is no single command for it. Open the job\n'
      printf 'named above in the job list on the left of this page, and read the line that begins
'
      printf 'with `Error:` — it names the file and the rule.

'
    fi
  done

  if [ "$any" = 0 ]; then
    printf 'No failed step was reported — the run may have been cancelled, or a job failed before\n'
    printf 'it started. Re-running the workflow is a safe first move.\n\n'
    return 0
  fi

  printf -- '---\n\n'
  printf '### If that means nothing to you, paste this into your AIOS session\n\n'
  printf '```\n'
  printf 'A check failed on my pull request: %s\n' "${AIOS_RUN_URL:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-The-AIOS/aios}/actions/runs/${GITHUB_RUN_ID:-}}"
  printf 'Read the run summary at that link, tell me in plain language what it is asking for,\n'
  printf 'and fix it in my branch.\n'
  printf '```\n\n'
  # An absolute link, not a relative one: a run-summary link resolves against the RUN url,
  # where ../blob/main points at nothing.
  printf 'What each check protects is listed in [CONTRIBUTING.md](%s/%s/blob/main/CONTRIBUTING.md#before-you-open-a-pr-checklist).
' \
    "${GITHUB_SERVER_URL:-https://github.com}" "${GITHUB_REPOSITORY:-The-AIOS/aios}"
}

# ── modes ────────────────────────────────────────────────────────────────────
case "${1:-}" in
  --command-for) command_for "${2:?a step name is required}" ;;
  --render)      render < "${2:?a TSV file is required}" ;;
  "")
    out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
    tsv="$(mktemp)"
    collect > "$tsv" || printf '' > "$tsv"
    render < "$tsv" >> "$out"
    rm -f "$tsv"
    ;;
  *) printf 'usage: explain-failure.sh [--render FILE | --command-for "<step name>"]\n' >&2; exit 2 ;;
esac

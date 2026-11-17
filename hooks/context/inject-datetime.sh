#!/usr/bin/env bash
# UserPromptSubmit hook — inject current system date/time into Claude's context.
#
# Hook event: UserPromptSubmit (runs after user submits prompt, before Claude reads it).
# stdout from this hook is appended to Claude's view of the prompt as additional context.
#
# Eliminates the failure mode: Claude infers time-of-day from conversational context
# (e.g. "we started this morning" → assumes still morning hours later) instead of
# checking the system clock. The system clock is always 1 tool-call away — but Claude
# tends to use conversational inference when not forced to verify.
#
# Ref: antifragile.md 2026-05-18 "Check `date` before reasoning about time-of-day".
#
# Output format: structured multi-line tag. Claude parses each field independently.
# weekday + ISO date + 24h time + tz name + UTC offset + unix epoch.

set -euo pipefail

cat <<EOF
<system-time>
weekday: $(date '+%A')
date: $(date '+%Y-%m-%d')
time: $(date '+%H:%M:%S')
timezone: $(date '+%Z') ($(date '+%z'))
unix: $(date '+%s')
</system-time>
EOF

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The two skill registrars skip the same sources
#
# WHY
# skills/setup.sh stopped skipping anthropic/ once it was measured that no
# marketplace provides those skills; skills/setup.ps1 kept skipping it. So on
# Windows every agent declaring an Anthropic skill (doc-coauthoring,
# internal-comms, theme-factory, mcp-builder, skill-creator) got nothing, with
# no error. Two implementations of one list drift; this pins them together.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
SH="${SETUP_SH:-skills/setup.sh}"; PS="${SETUP_PS1:-skills/setup.ps1}"
sh_skip=$(sed -nE 's/^[[:space:]]*([a-z|]+)\)[[:space:]]*skipped_sources=.*/\1/p' "$SH" | tr '|' '\n' | sort | tr '\n' ' ')
ps_skip=$(sed -nE "s/^\\\$skipSources = @\((.*)\)/\1/p" "$PS" | tr -d "' " | tr ',' '\n' | sort | tr '\n' ' ')
[ -n "$sh_skip" ] && [ -n "$ps_skip" ] || { no "could not read a skip list" "sh='$sh_skip' ps1='$ps_skip' — the check proves nothing"; }
[ "$sh_skip" = "$ps_skip" ] && ok "both registrars skip: $sh_skip" || no "setup.sh skips '$sh_skip', setup.ps1 skips '$ps_skip'" "one platform's agents silently lose skills"
case " $ps_skip " in *" anthropic "*) no "setup.ps1 still skips anthropic/" "no marketplace provides those skills";; *) ok "anthropic/ is registered on Windows";; esac
printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

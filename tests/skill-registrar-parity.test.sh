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
# Since #313 neither registrar has a fixed skip list: both skip superpowers/ only when a
# Superpowers plugin is installed, and both register anthropic/. Check the rule, per script.
sh_plugin=$(grep -c 'plugins/marketplaces/\*superpowers\*' "$SH")
ps_plugin=$(tr -d '\r' < "$PS" | grep -c "Filter '\*superpowers\*'")
[ "$sh_plugin" -ge 1 ] && [ "$ps_plugin" -ge 1 ] && ok "both registrars skip superpowers/ only when a Superpowers plugin is installed" \
  || no "the plugin check is missing" "setup.sh=$sh_plugin setup.ps1=$ps_plugin"
grep -qE "^[[:space:]]*superpowers\)[[:space:]]*skipped_sources=" "$SH" && no "setup.sh still skips superpowers/ unconditionally" "a machine without the plugin gets no Superpowers" || ok "setup.sh has no unconditional superpowers skip"
tr -d '\r' < "$PS" | grep -q "^\$skipSources = @('superpowers')" && no "setup.ps1 still skips superpowers/ unconditionally" "" || ok "setup.ps1 has no unconditional superpowers skip"
grep -q 'old copy, left as it is' "$SH" && tr -d '\r' < "$PS" | grep -q 'old copy, left as it is' && ok "both report a plain-folder Superpowers copy as stale" || no "a stale copy is not reported on one platform" ""
tr -d '\r' < "$PS" | grep -qi "skipSources = @('anthropic" && no "setup.ps1 skips anthropic/" "no marketplace provides those skills" || ok "anthropic/ is registered on Windows"
printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

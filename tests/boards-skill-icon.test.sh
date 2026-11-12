#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The boards skill documents board.json's "icon" key (AIOS App 0.15.1) (#296)
#
# WHAT IT HOLDS
#   * the board.json bullet names `icon`, says an unknown name keeps the default glyph
#     with no error, and that an older App ignores it
#   * the writer example writes an icon
#   * every icon the skill suggests is one the App draws. The list below is copied from
#     the App's docs/rfcs/sidebar-boards.md (from ICONS in renderer/app.js); update it
#     when the App adds icons, never by guessing.
#   * the troubleshooting "Error line" stays about title / valid_for: a bad icon shows none
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
F=skills/aios/boards/SKILL.md
APP_ICONS="aios assistant bolt book box brain building calendar chart chat check coffee comfort command copy design docText download explorer file folder folderOpen gear guide help html id img inbox keyboard layout megaphone mic moon note panel plug robot rocket search shield skill sliders sparkles spawn speaker stack star stop sun sync term title trash users wrench"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
grep -E '^\s*- `icon`' "$F" >/dev/null && ok "the board.json bullet documents icon" || no "no icon entry under board.json"
grep -i 'default board glyph' "$F" >/dev/null && ok "an unknown name keeps the default glyph" || no "the fallback is not described"
grep -E 'older than 0\.15\.1' "$F" >/dev/null && ok "an older App ignores it" || no "older-App behaviour not stated"
grep -F '"icon":' "$F" | grep -F 'write_text' >/dev/null && ok "the writer example writes an icon" || no "the writer example has no icon"
sug=$(grep -E 'Names that suit boards' "$F" | sed -E 's/.*Names that suit boards: ([^.]*)\..*/\1/' | grep -oE '`[a-zA-Z]+`' | tr -d '`')
[ -n "$sug" ] && ok "the skill suggests some names" || no "no suggested names found"
bad=""; for n in $sug; do case " $APP_ICONS " in *" $n "*) ;; *) bad="$bad $n";; esac; done
[ -z "$bad" ] && ok "every suggested name is one the App draws" || no "names the App does not draw:$bad"
grep -i 'Error line on the card' "$F" | grep -i 'icon' >/dev/null && no "the error-line troubleshooting mentions icon" || ok "the error line stays about title / valid_for"
printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

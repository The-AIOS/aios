#!/usr/bin/env bash
# Superpowers registration (#313). skills/setup.sh registers the bundled Superpowers when no
# Superpowers plugin is installed, skips it when one is (no doubling), never touches a
# plain-folder copy (it reports it as stale), is idempotent, and still registers every other
# source in every case. Runs the real script under a fake HOME.
# Usage: bash tests/superpowers-registration.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SETUP="$ROOT/skills/setup.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "superpowers-registration"
SP=$(ls -d "$ROOT"/skills/superpowers/*/ 2>/dev/null | head -1); SP=$(basename "$SP")
AI=$(ls -d "$ROOT"/skills/aios/*/ | head -1); AI=$(basename "$AI")
[ -n "$SP" ] && [ -n "$AI" ] || { no "fixture: no bundled skills found"; echo "$pass passed, $fail failed"; exit 1; }
run(){ HOME="$1" bash "$SETUP" </dev/null 2>&1; }

# 1. Fresh machine, no plugin: the bundled Superpowers is linked, and other sources too.
H1=$(mktemp -d "${TMPDIR:-/tmp}/sp1.XXXXXX"); out=$(run "$H1"); rc=$?
[ "$rc" = 0 ] && ok "setup exits 0 on a fresh machine" || no "setup failed (rc=$rc): $out"
[ -L "$H1/.claude/skills/$SP" ] && ok "no plugin: the bundled Superpowers is linked ($SP)" || no "no plugin: $SP was not linked"
[ -L "$H1/.claude/skills/$AI" ] && ok "other sources still register ($AI)" || no "$AI was not linked"
case "$(readlink "$H1/.claude/skills/$SP")" in */skills/superpowers/$SP) ok "the link points at the bundled copy" ;; *) no "the link points elsewhere" ;; esac

# 2. Idempotent: a second run links nothing new and changes nothing.
out2=$(run "$H1")
printf '%s' "$out2" | grep -q 'linked 0,' && ok "a second run links nothing" || no "second run linked again: $(printf '%s' "$out2" | grep Done)"

# 3. A plain-folder copy (an old hand-made copy): left as it is, reported as stale, setup still succeeds.
H2=$(mktemp -d "${TMPDIR:-/tmp}/sp2.XXXXXX"); mkdir -p "$H2/.claude/skills/$SP"; echo old > "$H2/.claude/skills/$SP/SKILL.md"
out=$(run "$H2"); rc=$?
[ "$rc" = 0 ] && ok "setup exits 0 with a stale copy present" || no "setup failed with a stale copy (rc=$rc)"
[ -d "$H2/.claude/skills/$SP" ] && [ ! -L "$H2/.claude/skills/$SP" ] && [ "$(cat "$H2/.claude/skills/$SP/SKILL.md")" = old ] \
  && ok "the stale copy is never touched" || no "the stale copy was changed"
printf '%s' "$out" | grep -q "old copy, left as it is: $SP" && printf '%s' "$out" | grep -q 'plain folders: old copies' \
  && ok "the stale copy is named, with what to do" || no "stale copy not reported: $out"
[ -L "$H2/.claude/skills/$AI" ] && ok "other sources still register beside a stale copy" || no "$AI not linked beside a stale copy"

# 4. Plugin installed: the bundled Superpowers is not linked (no doubling); other sources still are.
H3=$(mktemp -d "${TMPDIR:-/tmp}/sp3.XXXXXX"); mkdir -p "$H3/.claude/plugins/marketplaces/superpowers-marketplace"
out=$(run "$H3"); rc=$?
[ "$rc" = 0 ] && ok "setup exits 0 with the plugin installed" || no "setup failed with the plugin (rc=$rc)"
[ ! -e "$H3/.claude/skills/$SP" ] && ok "plugin installed: the bundled Superpowers is not linked" || no "plugin installed but $SP was linked (doubled)"
[ -L "$H3/.claude/skills/$AI" ] && ok "plugin installed: other sources still register" || no "$AI not linked with the plugin installed"
printf '%s' "$out" | grep -q 'comes from its installed plugin' && ok "it says Superpowers comes from the plugin" || no "no plugin note"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

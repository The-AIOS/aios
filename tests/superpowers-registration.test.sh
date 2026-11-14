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

plugin(){ mkdir -p "$1/.claude/plugins"; printf '{"version":2,"plugins":{"superpowers@%s":[{"scope":"%s"}]}}\n' "$2" "${3:-user}" >"$1/.claude/plugins/installed_plugins.json"; }

# 4. Plugin installed (from any marketplace): the bundled Superpowers is not linked; other sources still are.
H3=$(mktemp -d "${TMPDIR:-/tmp}/sp3.XXXXXX"); plugin "$H3" claude-plugins-official
out=$(run "$H3"); rc=$?
[ "$rc" = 0 ] && ok "setup exits 0 with the plugin installed" || no "setup failed with the plugin (rc=$rc)"
[ ! -e "$H3/.claude/skills/$SP" ] && ok "plugin installed: the bundled Superpowers is not linked" || no "plugin installed but $SP was linked (doubled)"
[ -L "$H3/.claude/skills/$AI" ] && ok "plugin installed: other sources still register" || no "$AI not linked with the plugin installed"
printf '%s' "$out" | grep -q 'comes from its installed plugin' && ok "it says Superpowers comes from the plugin" || no "no plugin note"

# 5. A marketplace that is merely added (plugin not installed) does not count: the bundled copy is linked.
H4=$(mktemp -d "${TMPDIR:-/tmp}/sp4.XXXXXX"); mkdir -p "$H4/.claude/plugins/marketplaces/superpowers-marketplace"
run "$H4" >/dev/null
[ -L "$H4/.claude/skills/$SP" ] && ok "a marketplace without the installed plugin does not suppress the bundled copy" || no "an added-but-uninstalled marketplace suppressed Superpowers"

# 6. The plugin arrives after setup linked the bundled copy: setup removes exactly its own links, never a plain folder.
H5=$(mktemp -d "${TMPDIR:-/tmp}/sp5.XXXXXX"); run "$H5" >/dev/null
OTHER=$(ls -d "$ROOT"/skills/superpowers/*/ | sed -n 2p); OTHER=$(basename "$OTHER")
unlink "$H5/.claude/skills/$OTHER"; mkdir "$H5/.claude/skills/$OTHER"; echo mine > "$H5/.claude/skills/$OTHER/SKILL.md"
plugin "$H5" superpowers-marketplace; out=$(run "$H5")
[ ! -e "$H5/.claude/skills/$SP" ] && ok "after the plugin arrives, setup removes the bundled link it made earlier (no doubling)" || no "the earlier link stayed beside the plugin"
[ "$(cat "$H5/.claude/skills/$OTHER/SKILL.md" 2>/dev/null)" = mine ] && ok "a plain folder is never removed, even with the plugin installed" || no "a plain folder was removed"
[ -L "$H5/.claude/skills/$AI" ] && ok "other sources' links are untouched" || no "another source's link was removed"
printf '%s' "$out" | grep -q 'removed [0-9]* earlier link' && ok "it says how many earlier links it removed" || no "no note about removed links"

# 7. Installed but not active here: a disabled plugin, or one installed for another project only, provides
#    nothing, so the bundled copy is linked (never left with no Superpowers at all).
H6=$(mktemp -d "${TMPDIR:-/tmp}/sp6.XXXXXX"); plugin "$H6" official; printf '{"enabledPlugins":{"superpowers@official":false}}\n' > "$H6/.claude/settings.json"
run "$H6" >/dev/null; [ -L "$H6/.claude/skills/$SP" ] && ok "a disabled plugin does not suppress the bundled copy" || no "a disabled plugin left no Superpowers"
H7=$(mktemp -d "${TMPDIR:-/tmp}/sp7.XXXXXX"); plugin "$H7" official project
run "$H7" >/dev/null; [ -L "$H7/.claude/skills/$SP" ] && ok "a project-only install does not suppress the bundled copy" || no "a project-only install left no Superpowers"
printf '%s' "$(run "$(mktemp -d "${TMPDIR:-/tmp}/sp8.XXXXXX")")" | grep -q 'run this script again: it removes these links' && ok "after linking, it says to re-run setup if the plugin is installed later" || no "no re-run note after linking"

# 8. A relocated config folder (CLAUDE_CONFIG_DIR) is where the plugin records are read.
H9=$(mktemp -d "${TMPDIR:-/tmp}/sp9.XXXXXX"); mkdir -p "$H9/cfg/plugins"
printf '{"version":2,"plugins":{"superpowers@official":[{"scope":"user"}]}}\n' > "$H9/cfg/plugins/installed_plugins.json"
HOME="$H9" CLAUDE_CONFIG_DIR="$H9/cfg" bash "$SETUP" </dev/null >/dev/null 2>&1
[ ! -e "$H9/.claude/skills/$SP" ] && ok "a plugin recorded under CLAUDE_CONFIG_DIR is seen" || no "CLAUDE_CONFIG_DIR ignored: the bundled copy was linked beside the plugin"

# 9. After the vault moved, our old link is broken; with the plugin installed it is recognised and removed.
H10=$(mktemp -d "${TMPDIR:-/tmp}/sp10.XXXXXX"); mkdir -p "$H10/.claude/skills"
ln -s "/old/vault/skills/superpowers/$SP" "$H10/.claude/skills/$SP"; plugin "$H10" official
run "$H10" >/dev/null
[ ! -L "$H10/.claude/skills/$SP" ] && ok "a broken link from before a vault move is recognised as ours and removed" || no "a stale link from a moved vault stayed"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

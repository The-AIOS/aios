#!/usr/bin/env bash
# tests/update-clone-lock-skills-filters-sweep.test.sh
#
# Four places where /aios:update acted on a shared or partial view:
#   1. The clone at a fixed /tmp path had no lock — a second update wiped the first one's tree.
#   2. Skill-folder dedup compared only SKILL.md and then deleted the whole folder.
#   3. The reconcile's filters were bare substrings: `oauth` hid `doc-coauthoring/` and the
#      OAuth template; their drift was never reported.
#   4. The residue sweep looked for space-joined names only; zsh leaves newline-joined ones.
#
# Blocks under test are EXTRACTED from update.md, so a regression in the spec fails here.
#
# Run:  bash tests/update-clone-lock-skills-filters-sweep.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/plugins/aios/commands/update.md"
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
sk(){ SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || no "$3" "got [$1], wanted [$2]"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ucl.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

printf '/aios:update — clone lock, whole-folder skill compare, anchored filters, two-shape sweep\n'

# ---------------------------------------------------------------------------
# 1. clone lock — the block from Step 1, with the /tmp path redirected into $TMP
# ---------------------------------------------------------------------------
LOCKBLOCK=$(awk '/^LOCK=\/tmp\/aios-update-check.lock$/{f=1} f{print} f&&/^fi$/{exit}' "$SPEC" | sed "s#/tmp/aios-update-check.lock#$TMP/lock#")
[ -n "$LOCKBLOCK" ] && ok "1-. lock block extracted from Step 1" || no "1-. could not extract the lock block"
run_lock(){ ( eval "$LOCKBLOCK" ) 2>"$TMP/err"; echo "rc=$?"; }
have "$(run_lock)" "rc=0" "1a. no lock → acquired (rc 0)"
[ -d "$TMP/lock" ] && ok "1b. …and the lock directory exists (its mtime is the start time)" || no "1b. lock directory missing"
have "$(run_lock)" "rc=1" "1c. a fresh lock held by another run → refused (rc 1)"
grep -q 'another /aios:update holds' "$TMP/err" && ok "1d. …with a message that names the other run" || no "1d. refusal message missing" "$(cat "$TMP/err")"
grep -q 'do NOT run Step 7' "$TMP/err" && ok "1e. …and tells this run not to clean up what it never owned" || no "1e. refusal message does not forbid the cleanup"
# the race the timestamp-file design had: peer just ran mkdir, has not written anything yet →
# with the directory's own mtime as the clock there is nothing missing to misread as stale
rm -rf "$TMP/lock"; mkdir "$TMP/lock"
have "$(run_lock)" "rc=1" "1f. a peer's lock with NO contents at all is still a fresh lock → refused"
mkdir -p "$TMP/lock/owner-a"; touch -t 200001010000 "$TMP/lock"
have "$(run_lock)" "rc=0" "1g. a lock older than 30 min is RECLAIMED (unattended /today runs must not wedge on a crash) → acquired"
grep -q 'reclaimed a stale' "$TMP/err" && ok "1h. …and the reclaim is reported, not silent" || no "1h. stale reclaim not reported" "$(cat "$TMP/err")"
[ -d "$TMP/lock" ] && [ ! -d "$TMP/lock/owner-a" ] && ok "1h'. …the lock now belongs to this run (the stale one's contents are gone)" || no "1h'. lock not re-acquired cleanly"
# two runs that both judge it stale: the atomic mv lets exactly one through
rm -rf "$TMP/lock"; mkdir "$TMP/lock"; touch -t 200001010000 "$TMP/lock"
( run_lock > "$TMP/r1" ) & ( run_lock > "$TMP/r2" ) & wait
wins=$(cat "$TMP/r1" "$TMP/r2" | grep -c 'rc=0')
have "$wins" "1" "1l. two runs racing for one stale lock → exactly one acquires it"
grep -qF 'Finally `rm -rf /tmp/aios-update-check /tmp/aios-update-check.lock`' "$SPEC" && ok "1i. spec: Step 7's own cleanup line releases the lock with the clone" || no "1i. spec: Step 7's cleanup line does not release the lock" "a model following Step 7 leaves the lock behind"
grep -q "except when Step 1's lock refused this run" "$SPEC" && ok "1j. spec: Step 7's cleanup is withheld from a refused run" || no "1j. spec: a refused run would still clean up"
rm -rf "$TMP/lock"

# ---------------------------------------------------------------------------
# 2. skill folder: the decision must see the whole folder
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bundled/x" "$TMP/stray/x/scripts"
printf 'skill\n' > "$TMP/bundled/x/SKILL.md"; printf 'skill\n' > "$TMP/stray/x/SKILL.md"; printf 'mine\n' > "$TMP/stray/x/scripts/run.sh"
old=$(cmp -s "$TMP/stray/x/SKILL.md" "$TMP/bundled/x/SKILL.md" && echo remove-silently || echo backup)
new=$(diff -rq "$TMP/stray/x" "$TMP/bundled/x" >/dev/null 2>&1 && echo remove-silently || echo backup)
have "$old" "remove-silently" "2a. OLD rule (SKILL.md only): identical SKILL.md → remove silently, scripts/ lost (the defect, reproduced)"
have "$new" "backup"          "2b. NEW rule (whole folder): the operator's scripts/ make it differ → backup first"
grep -q 'compare the whole folder, never only its `SKILL.md`' "$SPEC" && ok "2c. spec: step 3b compares the whole folder" || no "2c. spec: step 3b no longer compares the whole folder"
grep -q 'duplicates/skills-root-{name}/' "$SPEC" && grep -q 'duplicates/skills-custom-{name}/' "$SPEC" && ok "2d. spec: root and custom strays back up to DIFFERENT folders" || no "2d. spec: skill-folder backup paths missing or shared"

# ---------------------------------------------------------------------------
# 3. reconcile filters, extracted from Step 6.5 and fed synthetic lines
# ---------------------------------------------------------------------------
VAULT="$TMP/vault"; CLONE="$TMP/clone"
FILTERS=$(awk '/^  \| grep -vF "Only in \$VAULT"/{f=1} f{print} f&&/\|\| true/{exit}' "$SPEC" | sed -E 's/ *\\$//; s/ *\|\| true.*$//' | tr '\n' ' ')
[ -n "$FILTERS" ] && ok "3-. filter chain extracted from Step 6.5" || no "3-. could not extract the filter chain"
through(){ printf '%s\n' "$1" | eval "cat $FILTERS"; }
must_pass(){ [ -n "$(through "$1")" ] && ok "3p. survives the filters: $2" || no "3p. WRONGLY dropped: $2" "$1"; }
must_drop(){ [ -z "$(through "$1")" ] && ok "3d. dropped as intended: $2" || no "3d. WRONGLY kept: $2" "$1"; }
must_pass "Files $VAULT/skills/anthropic/doc-coauthoring/SKILL.md and $CLONE/skills/anthropic/doc-coauthoring/SKILL.md differ" "a bundled skill whose name contains 'oauth' (co-oauth-oring)"
must_pass "Only in $CLONE/mcps/google-workspace-mcp: oauth.json.template" "the OAuth TEMPLATE the framework ships"
must_pass "Files $VAULT/hooks/aios-commit and $CLONE/hooks/aios-commit differ" "an ordinary framework file"
must_drop "Files $VAULT/mcps/google-workspace-mcp/oauth.json and $CLONE/mcps/google-workspace-mcp/oauth.json differ" "a real oauth.json credential"
must_drop "Files $VAULT/.gitignore and $CLONE/.gitignore differ" ".gitignore (dual-owned, merged in Step 2.7)"
must_drop "Files $VAULT/.claude-plugin/marketplace.json and $CLONE/.claude-plugin/marketplace.json differ" "marketplace.json (dual-owned)"
must_drop "Only in $CLONE/mcps: foo.egg-info" "an egg-info build dir"
must_drop "Only in $VAULT/agents: custom" "a vault-side extra"
# GNU diff (Git Bash) quotes paths that contain a space — the framework's own vault paths all do
must_pass "Files '$VAULT/skills/anthropic/doc-coauthoring/SKILL.md' and '$CLONE/skills/anthropic/doc-coauthoring/SKILL.md' differ" "the same skill, GNU-quoted"
must_pass "Only in '$CLONE/mcps/google-workspace-mcp': oauth.json.template" "the OAuth template, GNU-quoted"
must_drop "Files '$VAULT/mcps/google-workspace-mcp/oauth.json' and '$CLONE/mcps/google-workspace-mcp/oauth.json' differ" "a real oauth.json, GNU-quoted"
must_drop "Files '$VAULT/.claude-plugin/marketplace.json' and '$CLONE/.claude-plugin/marketplace.json' differ" "marketplace.json, GNU-quoted"
# the OLD bare-substring chain, transcribed, drops the skill — so 3p is not vacuous
old_through(){ printf '%s\n' "$1" | grep -vE "\.(log|pyc)$|oauth|egg-info|\.session$"; }
[ -z "$(old_through "Files $VAULT/skills/anthropic/doc-coauthoring/SKILL.md and $CLONE/skills/anthropic/doc-coauthoring/SKILL.md differ")" ] \
  && ok "3o. OLD chain drops doc-coauthoring (the defect, reproduced)" || no "3o. old chain unexpectedly kept doc-coauthoring"

# ---------------------------------------------------------------------------
# 4. residue sweep, extracted from Step 3 and run over both residue shapes
# ---------------------------------------------------------------------------
# end marker by fixed string: BSD awk reads `\{\}` as an interval, so a regex end never matched and the
# extraction silently ran on to the end of the spec (the sweep still printed first, so it "passed")
SWEEP=$(awk '/^find "\$HOME\/aios" -maxdepth 1 -type d ! -name/{f=1} f{print} f&&index($0,"esac'"'"' _ {} \\;")==1+length($0)-length("esac'"'"' _ {} \\;"){exit}' "$SPEC")
[ "$(printf '%s\n' "$SWEEP" | grep -c .)" -lt 20 ] && ok "4-'. extraction stops at the end of the sweep block" || no "4-'. extraction ran past the sweep block" "$(printf '%s\n' "$SWEEP" | grep -c .) lines"
[ -n "$SWEEP" ] && ok "4-. sweep block extracted from Step 3" || no "4-. could not extract the sweep block"
H="$TMP/home"; mkdir -p "$H/aios/01 - calendar" "$H/aios/CHANGELOG.md SETUP.md" "$H/aios/CHANGELOG.md
CLAUDE.md
hooks" "$H/aios/hooks"; echo x > "$H/aios/hooks/h"; echo y > "$H/aios/01 - calendar/n.md"
mkres(){ mkdir -p "$H/aios/CHANGELOG.md SETUP.md" "$H/aios/CHANGELOG.md
CLAUDE.md
hooks"; }
out=$(HOME="$H" bash -c "$SWEEP" 2>/dev/null | sort)
printf '%s\n' "$out" | grep -q 'CHANGELOG.md SETUP.md$' && ok "4a. bash: the space-joined residue is found" || no "4a. bash: space-joined residue missed" "$out"
printf '%s\n' "$out" | grep -q 'CHANGELOG.md^JCLAUDE.md^Jhooks$' && ok "4b. bash: the newline-joined residue is found (printed with ^J)" || no "4b. bash: newline-joined residue missed" "$out"
have "$(printf '%s\n' "$out" | grep -c .)" "2" "4c. bash: nothing else is flagged (calendar and hooks are left alone)"
left=$(find "$H/aios" -maxdepth 1 -type d -name 'CHANGELOG.md*' | grep -c .)
have "$left" "0" "4d. the sweep REMOVED both residue directories itself (a ^J name cannot be typed back)"
[ -f "$H/aios/hooks/h" ] && [ -f "$H/aios/01 - calendar/n.md" ] && ok "4e. real folders and their files are untouched" || no "4e. the sweep touched a real folder"
mkres
if command -v zsh >/dev/null 2>&1; then
  outz=$(HOME="$H" zsh -c "$SWEEP" 2>/dev/null | sort)
  have "$(printf '%s\n' "$outz" | grep -c .)" "2" "4z. zsh (the session shell): both shapes found, nothing else"
else
  sk "4z. zsh unavailable"
fi
# the OLD sweep, transcribed, misses the newline shape — so 4b is not vacuous
mkres
old_sweep(){ find "$H/aios" -maxdepth 1 -type d ! -name '.*' -print | while IFS= read -r d; do
  case "$(basename "$d")" in *.[A-Za-z0-9]*\ *) [ "$(find "$d" -type f | wc -l)" -eq 0 ] && echo "$d" ;; esac
done; }
oldout=$(old_sweep | grep -c .)
have "$oldout" "1" "4o. OLD sweep finds only the space-joined one (the defect, reproduced)"

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1

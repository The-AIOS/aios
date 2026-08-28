#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A bundled agent's declared skills must exist in the repo (issue #49, item 4)
#
# The root failure behind #49 was not the exclusion in skills/setup.sh. It was
# that "an agent DECLARES a skill" and "that skill is actually available" were
# never checked against each other. So an agent could name a skill in its
# `## Skills` block, receive nothing, and still answer — just worse, with nothing
# anywhere reporting why. Eight bundled agents were in that state:
#
#   content-writer · sales-proposal-writer · protocol-steward  (doc-coauthoring)
#   email-drafter · report-drafter                             (internal-comms)
#   deck-builder                                               (theme-factory)
#   aios-builder                                    (mcp-builder, skill-creator)
#
# This asserts the repo-side half, which is the half canonical controls: every
# skill an agent names must EXIST as a bundled source. Whether it is registered
# into ~/.claude/skills is machine state, checked by skills/setup.sh's own
# presence check — a test cannot assert another operator's machine, and pretending
# to would be the same over-claiming this whole class of bug is made of.
#
# The failure this catches is silent by construction: nothing errors, an agent
# simply underperforms. That is why it is a test and not a convention.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# The set of skills the repo actually ships, across every bundled source.
avail=$(find skills -mindepth 2 -maxdepth 3 -name SKILL.md 2>/dev/null \
        | while IFS= read -r f; do basename "$(dirname "$f")"; done | sort -u)
n_avail=$(printf '%s\n' "$avail" | grep -c . )

echo "── 1. the available-skill set is non-empty ──"
# Without this the whole suite passes by comparing against nothing — the
# fail-open shape that has bitten several guards in this repo.
[ "${n_avail:-0}" -ge 20 ] \
  && ok "found $n_avail bundled skills to check against" \
  || no "only ${n_avail:-0} bundled skills found" "every assertion below would pass vacuously"

echo "── 2. every skill a bundled agent declares exists in the repo ──"
bad=0
for a in $(find agents/aios -name '*.md' 2>/dev/null | sort); do
  # Only the `## Skills` block, and only backticked names in its bullets.
  # NOTE: an earlier version piped through `tr -d '\x60-'`, which deletes hyphens
  # INSIDE the name too — `doc-coauthoring` became `doccoauthoring` and this suite
  # reported 57 failures that were all its own parser mangling the input. sed the
  # delimiters only; never character-class away a character the data contains.
  decl=$(awk '/^## Skills/{f=1;next} f&&/^## /{exit} f' "$a" \
         | sed -nE 's/^- `([a-z0-9][a-z0-9-]*)`.*/\1/p')
  [ -z "$decl" ] && continue
  for d in $decl; do
    printf '%s\n' "$avail" | grep -qx "$d" || {
      no "$(basename "$a" .md) declares '$d', which no bundled source provides" \
         "the agent receives nothing and still answers — no error is raised"
      bad=$((bad+1)); }
  done
done
[ "$bad" -eq 0 ] && ok "every declared skill resolves to a bundled source"

echo "── 3. the registrar excludes a source only on a premise it CHECKS ──"
# anthropic/ was excluded on a premise measured false on two vaults. The exclusion
# list may exist; what may not exist is an exclusion with nothing verifying it.
if grep -qE '^\s*(anthropic \| superpowers|anthropic)\)' skills/setup.sh; then
  no "skills/setup.sh still excludes anthropic/" "measured: 11 sources, 10-11 absent from ~/.claude/skills on two vaults"
else
  ok "anthropic/ is no longer excluded"
fi
if grep -qF 'absent="$absent $name"' skills/setup.sh && grep -qiE 'marketplace is not installed yet|premise' skills/setup.sh; then
  ok "the registrar verifies its own exclusion premise at runtime"
else
  no "no presence check behind the exclusion list" "an unverified premise is what produced this bug"
fi

echo "── 4. CONTROL — section 2 must be able to fail ──"
T=$(mktemp -d); mkdir -p "$T/agents/aios/x" "$T/skills/aios/real-skill"
touch "$T/skills/aios/real-skill/SKILL.md"
printf '## Skills\n\n- `no-such-skill` — invented for the control.\n' > "$T/agents/aios/x/ghost.md"
hits=$(cd "$T" && {
  av=$(find skills -mindepth 2 -maxdepth 3 -name SKILL.md | while IFS= read -r f; do basename "$(dirname "$f")"; done | sort -u)
  c=0
  for a in $(find agents -name '*.md'); do
    for d in $(awk '/^## Skills/{f=1;next} f&&/^## /{exit} f' "$a" | sed -nE 's/^- `([a-z0-9][a-z0-9-]*)`.*/\1/p'); do
      printf '%s\n' "$av" | grep -qx "$d" || c=$((c+1))
    done
  done
  echo "$c"; })
rm -rf "$T"
[ "${hits:-0}" -ge 1 ] \
  && ok "CONTROL FIRES: an agent declaring a nonexistent skill is detected" \
  || no "CONTROL DID NOT FIRE — section 2 proves nothing"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

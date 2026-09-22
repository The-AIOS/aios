#!/usr/bin/env bash
# tests/update-tier0-denylist.test.sh
#
# Guards the Tier-0 boundary in /aios:update AFTER the layer enumeration was made
# generic over directories (Step 2 + Step 6.5).
#
# WHY THIS EXISTS, AND WHY IT IS SHAPED THIS WAY
# ----------------------------------------------
# The layer list used to be hardcoded (`templates skills hooks mcps plugins agents
# .claude-plugin`). That was safe for Tier 0 by ACCIDENT: tests/ and .github/ were
# excluded by simple omission. It was unsafe for everything else — a newly-added
# bundled folder was invisible to Step 2 (nothing DIFFERS; the path is merely absent
# from the vault) and equally invisible to Step 6.5, because the backstop read from
# the same hardcoded list. One blind spot, shared by the check and its own backstop.
#
# Deriving the list from the clone fixes that — and immediately arms the footgun the
# Tier 0 section warns about in writing: a generic enumeration sweeps tests/ and
# .github/ into every operator vault. So the exclusion has to stop being an omission
# and become a named denylist, and that denylist needs a test that CANNOT pass
# vacuously.
#
# Hence the shape: this does not grep update.md for reassuring strings. It MIRRORS
# the real derivation logic, RUNS it against a fixture tree, and asserts the output.
# Then it re-runs the same logic with the denylist emptied and asserts the opposite —
# so a version of this file that could never fail would itself fail scenario 4.
#
# MIRRORS, not extracts — and that word is the whole reason for #141. The mirror
# below was hand-copied from the spec, so it copied the spec's `ls -A` too, and a
# mirror carrying the same fault as the original cannot see it: this suite was green
# for the entire life of the bug. Two sections now bind the mirror to reality
# instead of trusting it — § 7 reproduces the Windows condition and requires the
# `ls` form to FAIL under it, and § 8 forbids `ls` in the spec's command positions
# at all. A mirror is only evidence to the extent something forces it to match.
#
# Run:  bash tests/update-tier0-denylist.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
U="$REPO/plugins/aios/commands/update.md"
PASS=0; FAIL=0
ok(){ printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# A fixture standing in for the canonical clone: real Tier-1 layers, the two Tier-0
# folders, an operator vault/ tree, and a layer that does NOT appear in any hardcoded
# list anywhere — that last one is the regression the generalisation exists to fix.
CLONE="$TMP/clone"
mkdir -p "$CLONE"/{templates,skills,hooks,mcps,plugins,agents,.claude-plugin,tests,.github/workflows,vault/.obsidian,brandnewlayer}
: > "$CLONE/CLAUDE.md"

echo "== update-tier0-denylist =="

# ---------------------------------------------------------------------------
# 1. The denylist is present in the spec and names both Tier-0 folders.
# ---------------------------------------------------------------------------
DENY_LINE="$(grep -m1 '^TIER0_DENY=' "$U" 2>/dev/null || true)"
if [ -z "$DENY_LINE" ]; then
  no "TIER0_DENY is defined in update.md" "no TIER0_DENY= line found — the enumeration is generic with nothing excluding Tier 0"
else
  miss=""
  for d in tests .github; do
    case "$DENY_LINE" in *"$d"*) ;; *) miss="$miss $d" ;; esac
  done
  [ -z "$miss" ] && ok "TIER0_DENY names tests and .github" \
                 || no "TIER0_DENY names tests and .github" "missing:$miss"
fi

# ---------------------------------------------------------------------------
# 2. THE REAL CHECK — run the derivation and assert what it produces.
#    Extracted from the spec rather than reimplemented, so this cannot drift
#    into testing a copy of the logic that update.md no longer uses.
# ---------------------------------------------------------------------------
# `find`, exactly as update.md now derives it — NOT `find -printf '%f\n'`, which is
# GNU-only and answers `find: -printf: unknown primary or operator` on a stock macOS.
derive(){ # $1 = denylist to use
  local deny="$1" out="" d path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    d="${path##*/}"
    case " $deny " in *" $d "*) continue ;; esac
    out="$out $d"
  done <<EOF
$(find "$CLONE" -maxdepth 1 -mindepth 1 -type d)
EOF
  printf '%s' "$out"
}

# The form update.md USED to carry, kept solely so § 7 can require it to break.
derive_via_ls(){ # $1 = denylist
  local deny="$1" out="" d
  for d in $(cd "$CLONE" && ls -A); do
    [ -d "$CLONE/$d" ] || continue
    case " $deny " in *" $d "*) continue ;; esac
    out="$out $d"
  done
  printf '%s' "$out"
}

REAL_DENY="$(printf '%s' "$DENY_LINE" | sed -e 's/^TIER0_DENY=//' -e 's/^"//' -e 's/"$//')"
LAYERS="$(derive "$REAL_DENY")"

leaked=""
for d in tests .github; do
  case " $LAYERS " in *" $d "*) leaked="$leaked $d" ;; esac
done
[ -z "$leaked" ] && ok "derived layers exclude every Tier-0 folder" \
               || no "derived layers exclude every Tier-0 folder" \
                     "LEAKED:$leaked — this would ship CI scaffolding into every operator vault"

# vault/ is Tier 2; only vault/.obsidian is added back, and by hand.
case " $LAYERS " in
  *" vault "*) no "vault/ is not swept wholesale" "vault/ entered the layer list — that is operator content (Tier 2)" ;;
  *)           ok "vault/ is not swept wholesale" ;;
esac

# ---------------------------------------------------------------------------
# 3. The positive half — the reason to generalise at all.
#    A layer named in no hardcoded list must still be found.
# ---------------------------------------------------------------------------
case " $LAYERS " in
  *" brandnewlayer "*) ok "a layer absent from every hardcoded list is still enumerated" ;;
  *)                   no "a layer absent from every hardcoded list is still enumerated" \
                          "the enumeration is not actually generic — the original bug survives" ;;
esac

# ---------------------------------------------------------------------------
# 4. THE NEGATIVE CASE — prove this test can fail.
#    Same logic, empty denylist: Tier 0 MUST leak. If it does not, the assertion
#    in scenario 2 is vacuous and proves nothing.
# ---------------------------------------------------------------------------
UNGUARDED="$(derive "")"
n=0
for d in tests .github; do
  case " $UNGUARDED " in *" $d "*) n=$((n+1)) ;; esac
done
[ "$n" = 2 ] && ok "test is falsifiable (empty denylist leaks both Tier-0 folders)" \
             || no "test is falsifiable (empty denylist leaks both Tier-0 folders)" \
                   "expected 2 leaks with no denylist, got $n — scenario 2 cannot fail, so it is not a check"

# ---------------------------------------------------------------------------
# 5. Both call sites apply it. One guarded loop and one unguarded loop is the
#    same bug with a green build: Step 6.5 is Step 2's backstop.
# ---------------------------------------------------------------------------
# NB: `grep -c` exits 1 on zero matches while still printing "0", so the idiomatic
# `$(grep -c … || echo 0)` emits "0\n0" and the arithmetic test below dies on it.
# Read the count, then read the exit code — never let one stand in for the other.
sites="$(grep -c 'case " \$TIER0_DENY " in' "$U" 2>/dev/null)" || sites=0
[ "${sites:-0}" -ge 2 ] && ok "both Step 2 and Step 6.5 apply the denylist ($sites sites)" \
                        || no "both Step 2 and Step 6.5 apply the denylist" \
                              "found $sites guarded loop(s), expected >= 2"

# ---------------------------------------------------------------------------
# 6. The category stays documented — folklore is how the first blind spot happened.
# ---------------------------------------------------------------------------
grep -q '^### Tier 0' "$U" && ok "update.md still documents § Tier 0" \
                           || no "update.md still documents § Tier 0"

# ---------------------------------------------------------------------------
# 7. THE WINDOWS CONDITION, REPRODUCED (#141).
#    Git for Windows ships `ls` aliased to `ls -F --color=auto
#    --show-control-chars` in /etc/profile.d/aliases.sh. `-F` appends a type
#    suffix, so `$d` is `vault/` and every denylist entry misses. The reconcile
#    then described the operator's own declared + observed context as framework
#    drift to pull, and its apply instruction says to overwrite. Exit 0, nothing
#    on stderr, lines shaped exactly like real drift.
#
#    There is no Windows here, so the alias is INJECTED: an `ls` earlier on PATH
#    that classifies. An alias would not survive into a function called from this
#    script, and a shim does the same job at the same place in the lookup.
# ---------------------------------------------------------------------------
SHIM="$TMP/bin"; mkdir -p "$SHIM"
REAL_LS="$(command -v ls)"
cat > "$SHIM/ls" <<STUB
#!/usr/bin/env bash
# Stands in for Git for Windows' \`ls -F\`: append / to directories, @ to symlinks.
cd "\${!#}" 2>/dev/null || true
"$REAL_LS" "\$@" | while IFS= read -r n; do
  if [ -d "\$n" ]; then printf '%s/\n' "\$n"
  elif [ -L "\$n" ]; then printf '%s@\n' "\$n"
  else printf '%s\n' "\$n"; fi
done
STUB
chmod +x "$SHIM/ls"

# HARNESS ASSERTION. A shim that does not classify would make both checks below
# pass while reproducing nothing — the same vacuity this suite exists to avoid.
PROBE="$(cd "$CLONE" && PATH="$SHIM:$PATH" ls -A | grep -c '/$' || true)"
[ "${PROBE:-0}" -ge 3 ] \
  && ok "harness: the ls shim really classifies ($PROBE dirs carry a suffix)" \
  || no "harness: the ls shim does not classify" "§ 7 would reproduce nothing"

# a. the OLD form must LEAK under it. If it does not, the condition is not
#    reproduced and everything below this line is decoration.
LEAK_LS="$(PATH="$SHIM:$PATH" derive_via_ls "$REAL_DENY")"
# Match BOTH spellings. The leaked token is `vault/`, with the classify suffix
# still attached — looking only for a bare `vault` finds nothing and reads as
# "no leak", which is the bug wearing the disguise of a passing test. The suffix
# does not soften the harm: `LAYERS+=("$d/")` yields `vault//`, git normalises
# the double slash, and Step 6.5's `diff -rq "$VAULT/vault/"` walks the
# operator's own tree either way.
n=0
for d in tests .github vault; do
  case " $LEAK_LS " in *" $d "*|*" $d/ "*) n=$((n+1)) ;; esac
done
[ "$n" -eq 3 ] \
  && ok "control: under \`ls -F\`, the ls-derived form leaks all three Tier-0/2 folders" \
  || no "control: the ls-derived form leaked only $n of 3 under \`ls -F\`" \
        "the #141 condition is not being reproduced, so 7b proves nothing"

# b. and the form update.md now uses must be immune to the same condition.
SAFE_LS="$(PATH="$SHIM:$PATH" derive "$REAL_DENY")"
n=0
for d in tests .github vault; do
  case " $SAFE_LS " in *" $d "*|*" $d/ "*) n=$((n+1)) ;; esac
done
[ "$n" -eq 0 ] \
  && ok "the find-derived form excludes all three even under \`ls -F\`" \
  || no "the find-derived form leaked $n folder(s) under \`ls -F\`" "LAYERS:$SAFE_LS"
# and it must still find the new layer — immunity that drops everything is not immunity
case " $SAFE_LS " in
  *" brandnewlayer "*) ok "and still enumerates a layer no hardcoded list names" ;;
  *)                   no "the find-derived form found no new layer under \`ls -F\`" "$SAFE_LS" ;;
esac

# ---------------------------------------------------------------------------
# 8. THE SPEC MUST NOT DERIVE A NAME FROM `ls` AT ALL.
#    § 7 proves `find` is immune; this is what stops the habit coming back at a
#    fourth site. `ls` is a presentation tool — it honours the caller's aliases,
#    colours and classify flags — so it has no business producing values a script
#    then matches on. Comments and echoed prose are exempt: the rule is about
#    command position, and the spec has to be able to explain itself.
# ---------------------------------------------------------------------------
LSUSE="$(grep -nE '(^|[|;&(]|\$\()[[:space:]]*ls[[:space:]]' "$U" \
         | grep -vE '^[0-9]+:[[:space:]]*#' | grep . || true)"
[ -z "$LSUSE" ] \
  && ok "update.md invokes \`ls\` in no command position" \
  || no "update.md still derives from \`ls\`:" "$LSUSE
       use: find \"\$DIR\" -maxdepth 1 -mindepth 1 -type d   (never -printf, it is GNU-only)"

# CONTROL for that grep — a detector with no control reports clean just as
# convincingly when it is broken, and this one is a regex over a 700-line file.
CTL="$TMP/lsctl.md"
printf '%s\n' 'for d in $(cd "$CLONE" && ls -A); do' > "$CTL"
R="$(grep -nE '(^|[|;&(]|\$\()[[:space:]]*ls[[:space:]]' "$CTL" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
[ -n "$R" ] && ok "control: the ls detector catches the exact line that shipped" \
            || no "control: the ls detector MISSED the line that shipped" "it cannot see what it is for"
printf '%s\n' '# never derive a name from `ls` — see #141' > "$CTL"
R="$(grep -nE '(^|[|;&(]|\$\()[[:space:]]*ls[[:space:]]' "$CTL" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
[ -z "$R" ] && ok "control: a comment explaining the rule does not fire it" \
            || no "control: the ls detector fires on its own documentation" "$R"

# ---------------------------------------------------------------------------
# 9. EACH SITE ASSERTS THE EXCLUSION HAPPENED, not merely that it was coded.
#    #141's `case` was syntactically perfect and matched nothing, so no linter
#    could have caught it. Only the effect is checkable: canonical always ships
#    tests/, .github/ and vault/, so a run that excluded none of them is broken.
# ---------------------------------------------------------------------------
eff="$(grep -c 'EXCLUDED="\$EXCLUDED' "$U" 2>/dev/null)" || eff=0
[ "${eff:-0}" -ge 2 ] \
  && ok "both derivations record what they excluded ($eff sites)" \
  || no "only ${eff:-0} derivation(s) record their exclusions" \
        "a denylist that silently matches nothing is the #141 failure; assert the outcome"
guards="$(grep -c 'for guard in tests .github vault' "$U" 2>/dev/null)" || guards=0
[ "${guards:-0}" -ge 2 ] \
  && ok "both derivations fail loudly when nothing was excluded ($guards sites)" \
  || no "only ${guards:-0} site(s) assert the exclusion happened" \
        "Step 6.5 is Step 2's backstop; an unasserted backstop shares the primary's blind spot"
grep -q "never excluded '\$guard'" "$U" \
  && ok "and the failure names the folder that was not excluded" \
  || no "the failure message does not name the folder" "an operator cannot act on 'derivation broken'"

# ---------------------------------------------------------------------------
# 10. RUN THE SPEC'S OWN ASSERTION, don't just confirm it is written down.
#     § 9 proves the words are present, which is the weaker claim — a guard can
#     be present and inert (this command shipped an inert one before: a compare
#     whose equal branch was unsatisfiable by construction, so it could never
#     once fire). So extract Step 2's real block and execute it twice: healthy,
#     where it must stay silent, and under the `ls` shim, where it must abort.
#
#     The extraction is EXPLICIT about failing. If the boundaries move, this
#     reports that it could not run rather than passing on an empty script —
#     a check that silently measures nothing is the shape of the bug it guards.
# ---------------------------------------------------------------------------
BLK="$TMP/step2.sh"
awk '/^LAYERS=\(\)$/{f=1} f{print} f && /^fi$/{exit}' "$U" > "$BLK.body"
if [ "$(grep -c . "$BLK.body")" -lt 10 ] || ! grep -q 'FATAL' "$BLK.body"; then
  no "harness: could not extract Step 2's derivation from update.md" \
     "the block boundaries moved — re-aim the awk, do not delete this section"
else
  ok "harness: extracted Step 2's derivation ($(grep -c . "$BLK.body") lines, carries a FATAL)"
  { printf 'CLONE=%s\nTIER0_DENY=%s\n' "$(printf '%q' "$CLONE")" "$(printf '%q' "$REAL_DENY")"
    cat "$BLK.body"
    printf 'printf "LAYERS=%%s\\n" "${LAYERS[*]}"\n'; } > "$BLK"

  OUT_OK="$(bash "$BLK" 2>&1)"; RC_OK=$?
  { [ "$RC_OK" -eq 0 ] && ! printf '%s' "$OUT_OK" | grep -q FATAL; } \
    && ok "the spec's own block runs clean on a healthy clone" \
    || no "the spec's block aborted on a HEALTHY clone" "$OUT_OK"

  OUT_BAD="$(PATH="$SHIM:$PATH" bash "$BLK" 2>&1)"; RC_BAD=$?
  # Under the shim the derivation is `find`-based, so it must STILL be clean --
  # that is the fix working. The assertion's own teeth are proven by 10c below,
  # which breaks the derivation rather than the environment.
  { [ "$RC_BAD" -eq 0 ] && ! printf '%s' "$OUT_BAD" | grep -q FATAL; } \
    && ok "and stays clean with a classifying \`ls\` on PATH" \
    || no "the spec's block aborted merely because \`ls\` classifies" "$OUT_BAD"

  # 10c. THE ASSERTION MUST HAVE TEETH. Swap the extracted derivation back to the
  #      `ls` form and require the spec's own FATAL to fire. Without this, 10a/10b
  #      are satisfied by an assertion that can never trigger.
  sed -e 's|^\$(find "\$CLONE" -maxdepth 1 -mindepth 1 -type d)$|$(cd "$CLONE" \&\& ls -A)|' \
      "$BLK.body" > "$BLK.mut.body"
  if grep -q 'ls -A' "$BLK.mut.body"; then
    { printf 'CLONE=%s\nTIER0_DENY=%s\n' "$(printf '%q' "$CLONE")" "$(printf '%q' "$REAL_DENY")"
      cat "$BLK.mut.body"; } > "$BLK.mut"
    OUT_MUT="$(PATH="$SHIM:$PATH" bash "$BLK.mut" 2>&1)"; RC_MUT=$?
    if [ "$RC_MUT" -ne 0 ] && printf '%s' "$OUT_MUT" | grep -q "never excluded 'tests'"; then
      ok "control: ls-derived + classifying \`ls\` → the spec's FATAL fires and names 'tests'"
    else
      no "control: the spec's effect assertion did NOT fire on a broken derivation" \
         "rc=$RC_MUT — the assertion is inert, which is worse than absent: $OUT_MUT"
    fi
  else
    no "control: could not mutate the extracted derivation" "the heredoc line moved; re-aim the sed"
  fi
fi

# ---------------------------------------------------------------------------
# 11. RUN STEP 6.5 TOO. § 10 executes Step 2's block; this suite only GREPPED for
#     Step 6.5's assertion (§ 9) — and that assertion was inert. It sat inside a
#     `{ … } | grep …` pipeline, so its `exit 1` ended only a subshell, it ran after
#     the diff loop had already printed, and the pipeline's status was the last
#     grep's. Simulating the #141 condition there gave exit 0, 63 drift lines and 25
#     of the operator's own context paths, with the FATAL on stderr only. The
#     presence check passed throughout. So: extract the block, run it three ways.
# ---------------------------------------------------------------------------
S65="$TMP/step65"; mkdir -p "$S65"
awk '/^### 6\.5\./{f=1} f&&/^```bash$/{g=1; next} g&&/^```$/{exit} g{print}' "$U" > "$S65/body.sh"
FXC="$S65/clone"; FXV="$S65/vault"
mkdir -p "$FXC"/{plugins/aios,agents,hooks,tests,.github,vault/.obsidian}
echo x > "$FXC/plugins/aios/a.md"; echo y > "$FXC/hooks/h.sh"; echo z > "$FXC/agents/g.md"
echo '{}' > "$FXC/vault/.obsidian/app.json"
for f in README.md LICENSE NOTICE; do echo "$f" > "$FXC/$f"; done
cp -R "$FXC" "$FXV"
# The fixture vault MUST hold operator content that differs from canonical's seed, the way
# every real vault does — or the leaked directories diff as identical, print nothing, and a
# broken assertion looks like a working one. The first version of this section copied the
# clone verbatim and passed against the old, inert code for exactly that reason.
mkdir -p "$FXC/vault/00 - notes/context/declared" "$FXV/vault/00 - notes/context/declared"
echo "seed" > "$FXC/vault/00 - notes/context/declared/about_me.md"
echo "the operator's own words, accumulated over months" > "$FXV/vault/00 - notes/context/declared/about_me.md"
# The gate keys on text EVERY version of this block carries, never on the new code's own
# shape — otherwise the suite fails on older code for a technicality and never reaches the
# assertion it exists for, which proves nothing about the bug.
if [ "$(grep -c . "$S65/body.sh")" -lt 40 ] || ! grep -qF "never excluded '\$guard'" "$S65/body.sh"; then
  no "harness: could not extract Step 6.5's block" "boundaries moved — re-aim the awk, never delete this section"
else
  ok "harness: extracted Step 6.5's block ($(grep -c . "$S65/body.sh") lines)"
  # point the block at the fixture instead of $HOME/aios and /tmp
  sed "s|^VAULT=\"\$HOME/aios\"; CLONE=\"/tmp/aios-update-check\"$|VAULT=\"$FXV\"; CLONE=\"$FXC\"|" "$S65/body.sh" > "$S65/run.sh"
  grep -qF "VAULT=\"$FXV\"" "$S65/run.sh" \
    && ok "harness: the block now targets the fixture, not a real vault" \
    || no "harness: could not retarget the block" "the VAULT=/CLONE= line changed shape — refusing to run it against a real vault"

  if grep -qF "VAULT=\"$FXV\"" "$S65/run.sh"; then
    bash "$S65/run.sh" > "$S65/o" 2>"$S65/e"; rc=$?
    { [ "$rc" -eq 0 ] && [ "$(grep -c . "$S65/o")" -eq 0 ]; } \
      && ok "11a. healthy vault → exit 0, empty drift list" \
      || no "11a. healthy vault did not reconcile clean" "exit=$rc stdout=$(head -2 "$S65/o")"

    echo changed > "$FXV/hooks/h.sh"
    bash "$S65/run.sh" > "$S65/o" 2>"$S65/e"; rc=$?
    { [ "$rc" -eq 0 ] && grep -q 'h.sh' "$S65/o"; } \
      && ok "11b. real drift → exit 0, and the file is named" \
      || no "11b. real drift was not reported" "exit=$rc stdout=$(head -2 "$S65/o")"
    echo y > "$FXV/hooks/h.sh"

    # the #141 condition: every derived name arrives with a classify suffix
    # Indentation-tolerant: the line sat four spaces deep inside the old piped group and
    # two at top level now; a pattern tied to either would silently skip the other.
    sed 's|^\([[:space:]]*\)p="${path##\*/}"$|\1p="${path##*/}/"|' "$S65/run.sh" > "$S65/broken.sh"
    if ! grep -qF 'p="${path##*/}/"' "$S65/broken.sh"; then
      no "11c. harness: could not mutate the derivation" "the derivation line moved — re-aim the sed"
    else
      bash "$S65/broken.sh" > "$S65/o" 2>"$S65/e"; rc=$?
      if grep -q 'context/declared' "$S65/o"; then
        no "11c. a broken derivation PRINTED the operator's own context as drift" \
           "exit=$rc — $(grep -c . "$S65/o") line(s) on stdout; the apply instruction says to overwrite these"
      elif [ "$rc" -ne 0 ] && [ "$(grep -c . "$S65/o")" -eq 0 ] && grep -q "never excluded 'tests'" "$S65/e"; then
        ok "11c. broken derivation → REFUSED: non-zero exit, NOTHING on stdout, FATAL names 'tests'"
      else
        no "11c. the Step 6.5 assertion does not stop a broken derivation" \
           "exit=$rc stdout_lines=$(grep -c . "$S65/o") — it can refuse without stopping anything"
      fi
    fi
  fi
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1

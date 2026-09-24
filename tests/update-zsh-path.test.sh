#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:update's shell blocks run under ZSH — and zsh's special names are not
# ordinary variables
#
# WHY
# The session's shell on macOS is zsh, where `path` is an ARRAY TIED to $PATH.
# Steps 2 and 6.5 derived their layer lists with `while IFS= read -r path`, so
# every iteration replaced the command search path with a filename. The loop
# body is all builtins and kept working; then `git diff` (Step 2) and `diff -rq`
# (Step 6.5) were simply not found. Their empty output read as "nothing changed"
# and "0 drift", Step 6.5 discards diff's stderr, and the run reported success
# having compared nothing — found by an operator session on 2026-09-22.
#
# Every existing suite ran these blocks with `bash`, which has no such tie, so
# all of them passed. This suite runs the same extracted blocks under zsh:
#   1. lint: no zsh-special name used as a shell variable in any command's
#      bash block (path fpath cdpath manpath module_path status argv)
#   2. Step 2 under zsh against a fixture git history → the changed file is named
#   3. Step 6.5 under zsh → a healthy vault is clean, real drift is named
#   4. Step 6.5 with `diff` missing from PATH → REFUSES (non-zero, nothing on
#      stdout), never an empty "clean" list
# Checks 2–3 fail against the pre-fix blocks under zsh; that is the point.
# zsh is REQUIRED under CI (macOS ships it; the ubuntu job installs it).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
U=plugins/aios/commands/update.md
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "-- 1. lint: zsh-special names are never shell variables --"
NAMES='path|fpath|cdpath|manpath|module_path|status|argv'
HITS="$(for f in plugins/aios/commands/*.md; do
  awk -v F="$f" '/^[[:space:]]*```(bash|sh|zsh)[[:space:]]*$/{b=1; next} b&&/^[[:space:]]*```[[:space:]]*$/{b=0; next} b{print F":"NR": "$0}' "$f"
done | grep -vE ':[0-9]+: *#' \
     | grep -E "read( -[a-zA-Z]+)* ($NAMES)([^A-Za-z0-9_]|\$)|for ($NAMES) in |(^|[;&|] *|: *)(local |export )?($NAMES)=" )"
# control: the lint must fire on the very line that caused this
CTRL="$(printf 'while IFS= read -r path; do\n' | grep -E "read( -[a-zA-Z]+)* ($NAMES)([^A-Za-z0-9_]|\$)")"
[ -n "$CTRL" ] && ok "control: the lint pattern catches \`read -r path\`" || no "control: the lint pattern is blind" "fix the regex before trusting a clean result"
[ -z "$HITS" ] && ok "no command's shell block assigns a zsh-special name" \
  || no "a command's shell block uses a zsh-special name as a variable" "$(printf '%s' "$HITS" | head -3)"

ZSH="$(command -v zsh || true)"
if [ -z "$ZSH" ]; then
  if [ -n "${CI:-}" ]; then no "zsh is available under CI" "install zsh on this runner — the macOS session shell is zsh"
  else echo "  - no zsh here: execution checks skipped (required under CI)"; fi
  printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; exit
fi

block(){ awk -v H="$1" 'index($0,H)==1{f=1} f&&/^```bash$/{g=1; next} g&&/^```$/{exit} g{print}' "$U"; }

echo "-- 2. Step 2 under zsh names what changed --"
C2="$TMP/c2"; mkdir -p "$C2"/{plugins/aios,agents,hooks,tests,.github,vault/.obsidian}
echo a > "$C2/plugins/aios/a.md"; echo h > "$C2/hooks/h.sh"; echo g > "$C2/agents/g.md"; echo t > "$C2/tests/t.sh"; echo w > "$C2/.github/w.yml"
( cd "$C2" && git init -q && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -qm A ) >/dev/null
BASE="$(git -C "$C2" rev-parse HEAD)"
echo changed > "$C2/hooks/h.sh"
( cd "$C2" && git -c user.email=t@t -c user.name=t commit -qam B ) >/dev/null
block "### 2. Find what changed" > "$TMP/s2.body"
if ! grep -q 'CLONE="/tmp/aios-update-check"' "$TMP/s2.body" || ! grep -q '{stored_hash}' "$TMP/s2.body"; then
  no "harness: could not extract Step 2's block" "the CLONE= line or {stored_hash} placeholder moved — re-aim, never delete"
else
  sed -e "s|^CLONE=\"/tmp/aios-update-check\"$|CLONE=\"$C2\"|" -e "s|{stored_hash}|$BASE|g" "$TMP/s2.body" > "$TMP/s2.sh"
  out="$("$ZSH" "$TMP/s2.sh" 2>"$TMP/s2.err")"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'hooks/h.sh'; then ok "2. zsh run names hooks/h.sh (exit 0)"
  else no "2. Step 2 under zsh did not name the changed file" "exit=$rc stdout='$(printf '%s' "$out" | head -2)' stderr='$(head -2 "$TMP/s2.err")'"; fi
  printf '%s\n' "$out" | grep -q '^tests/' && no "2b. Step 2 listed a Tier-0 path under zsh" "tests/ must never reach a vault" || ok "2b. no Tier-0 path listed"
fi

echo "-- 3. Step 6.5 under zsh --"
FXC="$TMP/clone"; FXV="$TMP/vault"
mkdir -p "$FXC"/{plugins/aios,agents,hooks,tests,.github,vault/.obsidian}
echo x > "$FXC/plugins/aios/a.md"; echo y > "$FXC/hooks/h.sh"; echo z > "$FXC/agents/g.md"
echo '{}' > "$FXC/vault/.obsidian/app.json"
for f in README.md LICENSE NOTICE; do echo "$f" > "$FXC/$f"; done
cp -R "$FXC" "$FXV"
block "### 6.5." > "$TMP/s65.body"
sed "s|^VAULT=\"\$HOME/aios\"; CLONE=\"/tmp/aios-update-check\"$|VAULT=\"$FXV\"; CLONE=\"$FXC\"|" "$TMP/s65.body" > "$TMP/s65.sh"
if ! grep -qF "VAULT=\"$FXV\"" "$TMP/s65.sh"; then
  no "harness: could not retarget Step 6.5" "the VAULT=/CLONE= line changed shape — refusing to run it against a real vault"
else
  "$ZSH" "$TMP/s65.sh" > "$TMP/o" 2>"$TMP/e"; rc=$?
  { [ "$rc" -eq 0 ] && [ "$(grep -c . "$TMP/o")" -eq 0 ]; } && ok "3a. healthy vault → exit 0, empty drift list" \
    || no "3a. healthy vault did not reconcile clean under zsh" "exit=$rc stdout=$(head -2 "$TMP/o") stderr=$(head -2 "$TMP/e")"
  echo changed > "$FXV/hooks/h.sh"
  "$ZSH" "$TMP/s65.sh" > "$TMP/o" 2>"$TMP/e"; rc=$?
  { [ "$rc" -eq 0 ] && grep -q 'h.sh' "$TMP/o"; } && ok "3b. real drift under zsh → exit 0 and the file is named" \
    || no "3b. real drift was NOT reported under zsh" "exit=$rc stdout_lines=$(grep -c . "$TMP/o") stderr=$(head -2 "$TMP/e") — this is the silent '0 drift'"

  echo "-- 4. a missing tool refuses, never reads as clean --"
  SHIM="$TMP/shim"; mkdir -p "$SHIM"
  for d in /usr/bin /bin; do for x in "$d"/*; do n="${x##*/}"; [ "$n" = diff ] && continue; [ -e "$SHIM/$n" ] || ln -s "$x" "$SHIM/$n" 2>/dev/null; done; done
  if [ -e "$SHIM/diff" ] || [ ! -e "$SHIM/find" ]; then no "harness: could not build a PATH without diff" "shim is wrong"
  else
    PATH="$SHIM" "$ZSH" "$TMP/s65.sh" > "$TMP/o" 2>"$TMP/e"; rc=$?
    { [ "$rc" -ne 0 ] && [ "$(grep -c . "$TMP/o")" -eq 0 ] && grep -q "'diff' is not on PATH" "$TMP/e"; } \
      && ok "4. diff missing → REFUSED: non-zero exit, nothing on stdout, FATAL names diff" \
      || no "4. a missing diff did not refuse" "exit=$rc stdout_lines=$(grep -c . "$TMP/o") stderr=$(head -1 "$TMP/e")"
  fi
  echo y > "$FXV/hooks/h.sh"
fi

echo "-- 5. Step 3.4: canonical's deletions — untouched files go, edited files stay and are asked about once --"
# The old rule asked about every deleted path with default KEEP, which left a stale
# file beside its replacement whenever upstream reorganised a folder (measured: five
# claude-api guides kept beside their new per-SDK folders). Run the real block.
D="$TMP/del"; mkdir -p "$D"
awk 'index($0,"4. **Files deleted upstream")==1{f=1} f&&/^[[:space:]]*```bash[[:space:]]*$/{g=1; next} g&&/^[[:space:]]*```[[:space:]]*$/{exit} g{sub(/^   /,""); print}' "$U" > "$D/body.sh"
if [ "$(grep -c . "$D/body.sh")" -lt 8 ] || ! grep -q 'echo "removed' "$D/body.sh"; then
  no "harness: could not extract Step 3.4's block" "the heading or fence moved — re-aim the awk, never delete this section"
else
  for sh in bash "$ZSH"; do
    F="$D/$(basename "$sh")"; rm -rf "$F"; mkdir -p "$F/clone/skills/x" "$F/home/aios/skills/x"
    ( cd "$F/clone" && git init -q && printf 'old guide\n' > skills/x/untouched.md && printf 'orig\n' > skills/x/edited.md && printf 'keep\n' > skills/x/stays.md \
      && git -c user.email=t@t -c user.name=t add -A && git -c user.email=t@t -c user.name=t commit -qm A ) >/dev/null
    BASE="$(git -C "$F/clone" rev-parse HEAD)"
    cp "$F/clone/skills/x/"*.md "$F/home/aios/skills/x/"; printf 'orig\nmy own note\n' > "$F/home/aios/skills/x/edited.md"
    ( cd "$F/clone" && git rm -q skills/x/untouched.md skills/x/edited.md && git -c user.email=t@t -c user.name=t commit -qm B ) >/dev/null
    { printf 'FILES=(skills/x/untouched.md skills/x/edited.md skills/x/stays.md)\n'
      sed -e "s|^CLONE=\"/tmp/aios-update-check\"; V=\"\$HOME/aios\"; S=\"{stored_hash}\"$|CLONE=\"$F/clone\"; V=\"$F/home/aios\"; S=\"$BASE\"|" "$D/body.sh"; } > "$F/run.sh"
    if ! grep -qF "CLONE=\"$F/clone\"" "$F/run.sh"; then no "harness: could not retarget Step 3.4" "the CLONE=/V=/S= line changed shape"; continue; fi
    out="$(HOME="$F/home" "$sh" "$F/run.sh" 2>&1)"
    n="$(basename "$sh")"
    { [ ! -e "$F/home/aios/skills/x/untouched.md" ] && printf '%s' "$out" | grep -q 'removed	skills/x/untouched.md'; } \
      && ok "$n · a deleted file you never edited is removed and reported" || no "$n · untouched deletion not removed" "$out"
    { [ -e "$F/home/aios/skills/x/edited.md" ] && printf '%s' "$out" | grep -q 'yours	skills/x/edited.md'; } \
      && ok "$n · a deleted file you edited is KEPT and listed for one question" || no "$n · edited deletion was not kept" "$out"
    [ -e "$F/home/aios/skills/x/stays.md" ] && ok "$n · a file canonical still has is untouched" || no "$n · a live file was removed"
  done
fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

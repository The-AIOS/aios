#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The statusline account chip renders the operator's alias, and falls back safely
#
# WHY THIS EXISTS
# The `👤` chip and the `🔄 from→to` swap banner used to show the email's
# local-part. Two accounts can legitimately SHARE a local-part — the same person
# on two providers, or one Google address behind two separate Anthropic accounts
# — and then both render identically, leaving the usage percentages as the only
# way to tell which one you are on. Contributed in #83.
#
# THE PROPERTY THAT MATTERS MOST IS THE FALLBACK. This code runs on every prompt
# render, so a raise here is not a wrong label, it is a broken statusline. The
# tests below therefore spend more effort on absent/malformed USER.md than on the
# happy path, and the no-alias case is asserted explicitly because that is what
# keeps every existing vault rendering exactly as it did before.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
MOD=hooks/claude-identity/context-monitor.py

label(){ # label <USER_MD_PATH|-> <email>
  local up="$1" em="$2"
  if [ "$up" = "-" ]; then env -u USER_MD_PATH python3 - "$MOD" "$em" <<'PY'
import importlib.util, sys
spec=importlib.util.spec_from_file_location("cm", sys.argv[1]); m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m); print(m._account_label(sys.argv[2] or None))
PY
  else USER_MD_PATH="$up" python3 - "$MOD" "$em" <<'PY'
import importlib.util, sys
spec=importlib.util.spec_from_file_location("cm", sys.argv[1]); m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m); print(m._account_label(sys.argv[2] or None))
PY
  fi; }

cat > "$T/USER.md" <<'MD'
# USER

## Anthropic accounts (quota management)

> parser notes live here

1. `same@gmail.com` — primary, MacBook
2. `same@gmail.com.alt` — overflow · alias **overflow**
3. `other@example.com` — third · alias **third slot**

## Next section
1. `notanaccount@example.com` — must NOT be picked up
MD

echo "── the alias renders, and only for lines that declare one ──"
[ "$(label "$T/USER.md" 'same@gmail.com.alt')" = "overflow" ] && ok "declared alias wins" || no "alias not used" "got [$(label "$T/USER.md" 'same@gmail.com.alt')]"
[ "$(label "$T/USER.md" 'other@example.com')" = "third slot" ] && ok "multi-word alias survives" || no "multi-word alias mangled"
# THE BACK-COMPAT CONTROL: without it this change could silently relabel every
# existing vault, which is the one outcome nobody would notice until it confused them.
[ "$(label "$T/USER.md" 'same@gmail.com')" = "same" ] && ok "control: no alias declared → local-part, unchanged behaviour" \
  || no "CONTROL FAILED — an undeclared account no longer renders its local-part"
[ "$(label "$T/USER.md" 'stranger@nowhere.com')" = "stranger" ] && ok "account absent from USER.md → local-part" || no "unknown account mislabelled"

echo "── the section boundary is respected ──"
[ "$(label "$T/USER.md" 'notanaccount@example.com')" = "notanaccount" ] \
  && ok "a numbered line in a LATER section is not read as an account" \
  || no "parser ran past its section" "an unrelated numbered list would poison the chip"

echo "── it never raises: this renders on every prompt ──"
[ "$(label "$T/nonexistent.md" 'a@b.com')" = "a" ] && ok "missing USER.md → local-part, no raise" || no "missing USER.md broke the label"
printf 'garbage without a section\n\x00\xff binary-ish\n' > "$T/junk.md"
[ "$(label "$T/junk.md" 'a@b.com')" = "a" ] && ok "malformed USER.md → local-part, no raise" || no "malformed USER.md broke the label"
[ "$(label "$T/USER.md" '')" = "?" ] && ok "empty email → '?' rather than a crash" || no "empty email not handled"

echo "── it self-locates rather than hardcoding the install path ──"
grep -q 'parents\[2\]' "$MOD" && ok "derives the repo root from __file__" \
  || no "no self-locating default" "hardcoding ~/aios depends on the operator's symlink; CI forbids it in .py"
sed 's/#.*//' "$MOD" | grep -q 'expanduser("~/aios' \
  && no "still hardcodes ~/aios in executable text" "Migration drift will fail" \
  || ok "no hardcoded ~/aios outside comments"

echo "── the convention is documented where operators receive it ──"
# USER.md is Tier-2 and NEVER syncs, so documenting only there would reach fresh
# clones and no existing operator. The component README is Tier-1 and does sync.
grep -q 'alias \*\*' hooks/claude-identity/README.md \
  && ok "documented in hooks/claude-identity/README.md (Tier-1, syncs)" \
  || no "convention undocumented" "a convention living only in its parser is folklore"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]

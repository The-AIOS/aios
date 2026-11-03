#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /aios:update offers to replace USER.md's accounts section only when it is safe
#
# WHY THIS EXISTS
# The account list moved to ~/.aios/accounts.json. The App from 0.14.0 and Glass from
# 0.5.14 read it from there, but an older surface still builds its account menu from
# USER.md's `## Anthropic accounts` section and would show an empty menu without it.
# So the offer must never fire while any installed surface is older, and replacing the
# section must never drop an account the new list does not have. (#262)
#
# A closed surface leaves no ~/.aios/surfaces file, so the install folders are read
# too: case 3 is an old Glass that is installed but not running.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found" >&2; exit 0; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
TOOL=hooks/claude-identity/user-md-accounts-pointer.py

fresh(){ # a machine with everything new enough
  rm -rf "$T/m"; mkdir -p "$T/m/surfaces" "$T/m/apps" "$T/m/home/.editor/extensions"
  printf '{"surface":"app","pid":1,"version":"0.14.0"}' > "$T/m/surfaces/app.json"
  mkdir -p "$T/m/apps/AIOS.app/Contents"
  "$PYBIN" -c 'import plistlib,sys; plistlib.dump({"CFBundleShortVersionString": sys.argv[2]}, open(sys.argv[1],"wb"))' \
    "$T/m/apps/AIOS.app/Contents/Info.plist" 0.14.1
  mkdir -p "$T/m/home/.editor/extensions/the-aios.aios-glass-0.5.13-universal" \
           "$T/m/home/.editor/extensions/the-aios.aios-glass-0.5.14-universal"
  cat > "$T/m/accounts.json" <<'J'
{"version":1,"accounts":[{"email":"a@example.com","rotation":true},{"email":"b@example.com","rotation":true}]}
J
  cat > "$T/m/USER.md" <<'M'
# USER

## Anthropic accounts

> My own note about these accounts.

1. `a@example.com` alias **work** — the main one, never automate it
2. `b@example.com`

**Rules:** keep this rule.

## Command personalizations

### /today
keep me
M
}
run(){ env -u USER_MD_PATH AIOS_SURFACES_DIR="$T/m/surfaces" AIOS_APP_DIRS="$T/m/apps" AIOS_APP_DATA_DIRS="${APPDATA_DIRS:-}" \
  AIOS_EXTENSIONS_HOME="$T/m/home" AIOS_ACCOUNTS_FILE="$T/m/accounts.json" \
  $PYBIN "$TOOL" "$@" --user-md "$T/m/USER.md"; }
offer(){ run check | $PYBIN -c 'import json,sys; print(json.load(sys.stdin)["offer"])'; }

fresh
[ "$(offer)" = True ] && ok "1. every surface new enough, every account listed → offer" || no "1. offer" "$(run check)"

fresh; printf '{"surface":"glass","pid":1,"version":"0.5.12"}' > "$T/m/surfaces/glass.json"
[ "$(offer)" = False ] && ok "2. a running Glass older than 0.5.14 → no offer" || no "2." "$(run check)"

fresh; rm -rf "$T/m/home/.editor/extensions/the-aios.aios-glass-0.5.14-universal"
[ "$(offer)" = False ] && ok "3. an old Glass that is installed but closed → no offer" || no "3." "$(run check)"

fresh; mkdir -p "$T/m/home/.other/extensions/the-aios.aios-glass-0.5.14-universal"
[ "$(offer)" = True ] && ok "4. the newest Glass in each editor counts, not every old folder" || no "4." "$(run check)"

fresh; "$PYBIN" -c 'import plistlib,sys; plistlib.dump({"CFBundleShortVersionString":"0.13.2"}, open(sys.argv[1],"wb"))' "$T/m/apps/AIOS.app/Contents/Info.plist"
[ "$(offer)" = False ] && ok "5. an installed App older than 0.14.0 → no offer" || no "5." "$(run check)"

fresh; printf '{"surface":"app","pid":1,"version":"?"}' > "$T/m/surfaces/app.json"
[ "$(offer)" = False ] && ok "6. a version that cannot be read → no offer" || no "6." "$(run check)"

fresh; printf '{"version":1,"accounts":[{"email":"a@example.com","rotation":true}]}' > "$T/m/accounts.json"
out=$(run check)
case "$out" in *'"offer": false'*b@example.com*) ok "7. an account missing from accounts.json blocks the offer and is named";;
  *) no "7." "$out";; esac

fresh; rm "$T/m/accounts.json"
[ "$(offer)" = False ] && ok "8. no accounts.json yet → no offer" || no "8." "$(run check)"

fresh; before=$(cat "$T/m/USER.md"); printf '{"surface":"glass","pid":1,"version":"0.5.12"}' > "$T/m/surfaces/glass.json"
run replace --backup-dir "$T/m/bk" >/dev/null; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$T/m/USER.md")" = "$before" ] && [ ! -e "$T/m/bk" ] \
  && ok "9. replace refuses when the check fails, and writes nothing" || no "9." "rc=$rc"

fresh; run replace --backup-dir "$T/m/bk" >/dev/null
grep -q 'accounts.json' "$T/m/USER.md" && ! grep -q 'b@example.com' "$T/m/USER.md" \
  && ok "10. replace puts the pointer in place of the list" || no "10." "$(cat "$T/m/USER.md")"
grep -q 'b@example.com' "$T/m/bk/USER.md-anthropic-accounts.md" \
  && ok "11. the old section is backed up first" || no "11."
grep -q '^### /today' "$T/m/USER.md" && grep -q '^keep me' "$T/m/USER.md" && head -1 "$T/m/USER.md" | grep '^# USER' >/dev/null \
  && ok "12. nothing outside the section changes" || no "12." "$(cat "$T/m/USER.md")"
[ "$(offer)" = False ] && ok "13. once replaced, the offer does not come back" || no "13." "$(run check)"
grep -q '^> My own note' "$T/m/USER.md" && grep -q '^\*\*Rules:\*\* keep this rule' "$T/m/USER.md" \
  && ok "14. the operator's own notes in the section stay; only the numbered list goes" || no "14." "$(cat "$T/m/USER.md")"
fresh; out=$(run check)
case "$out" in *'"removes"'*'never automate it'*) ok "15. check names the exact lines replace would remove";;
  *) no "15." "$out";; esac

fresh; rm -rf "$T/m/apps/AIOS.app" "$T/m/surfaces/app.json"; mkdir -p "$T/m/appdata/AIOS"
APPDATA_DIRS="$T/m/appdata/AIOS"; out=$(run check); APPDATA_DIRS=""
case "$out" in *'"offer": false'*'open the App once'*) ok "16. an App used here whose version nothing shows (closed, on Windows or Linux) → no offer";;
  *) no "16." "$out";; esac

fresh; printf '{"surface":"app","pid":1,"version":"0.14.0"}' > "$T/m/surfaces/app.json"; rm -rf "$T/m/apps/AIOS.app"; mkdir -p "$T/m/appdata/AIOS"
APPDATA_DIRS="$T/m/appdata/AIOS"; r=$(offer); APPDATA_DIRS=""
[ "$r" = True ] && ok "17. the same App with its version on record → offer" || no "17." "$r"

fresh; "$PYBIN" - "$T/m/USER.md" <<'PY2'
import sys; p=sys.argv[1]; s=open(p).read().replace("**Rules:** keep this rule.", "1. `claude-switch --add` is how I add one.")
open(p,"w").write(s)
PY2
r=$(offer); [ "$r" = True ] && grep -q 'claude-switch --add. is how' "$T/m/USER.md" && ok "18. a numbered note that is not an address is not read as an account" || no "18." "$(run check)"
run replace --backup-dir "$T/m/bk" >/dev/null
grep -q 'claude-switch --add. is how' "$T/m/USER.md" && ok "19. and replace leaves that note in place" || no "19."

fresh; "$PYBIN" -c 'import sys;p=sys.argv[1];d=open(p,newline="").read().replace("\n","\r\n");open(p,"w",newline="").write(d)' "$T/m/USER.md"
run replace --backup-dir "$T/m/bk" >/dev/null
lf=$("$PYBIN" -c 'import sys;d=open(sys.argv[1],"rb").read();print(d.count(b"\n")-d.count(b"\r\n"))' "$T/m/USER.md")
[ "$lf" = 0 ] && ok "20. a CRLF USER.md keeps CRLF line endings, the pointer included" || no "20." "$lf bare LF line(s)"

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

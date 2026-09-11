#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# connect.sh — the Google connector's one-command setup (AI-126)
#
# The thing worth asserting is the DERIVATION, not the happy path. Before this
# script, the set of Google APIs an operator had to enable was written down in
# three places — connector.json's `--permissions`, the setup doc's numbered
# list, and the oauth template's `scopes` array — and all three had drifted
# apart: the doc told you to enable a Chat API nothing requested, and the
# template's scopes omitted Gmail, contacts and forms entirely.
#
# Nobody noticed because the failure is late and misleading. A scope whose API
# is off consents fine, exposes the tool, and returns `403 SERVICE_DISABLED` at
# the first call, which reads like an auth problem. So this suite asserts the
# property that makes that impossible: exactly ONE list exists, every permission
# group resolves through it, and an unmapped group STOPS the script instead of
# quietly producing a half-enabled project.
#
# The gcloud stub is what makes the rest testable — every mutating path is
# exercised without a Google account, and the stub records its calls so
# `--dry-run` can be proven to mutate nothing rather than assumed to.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

SCRIPT="mcps/google-workspace-mcp/connect.sh"
MANIFEST="mcps/google-workspace-mcp/connector.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[ -f "$SCRIPT" ] || { printf '  FAIL  %s does not exist\n' "$SCRIPT"; exit 1; }

# ── a gcloud that records instead of calling Google ──────────────────────────
mk_gcloud(){ # $1 = bin dir · $2 = "authed"|"anon" · $3 = existing project ids (may be empty)
  mkdir -p "$1"
  cat > "$1/gcloud" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$GCLOUD_LOG"
case "\$1 \$2" in
  "auth list")      [ "$2" = authed ] && printf 'operator@%s\n' "\$STUB_DOMAIN" ;;
  "projects list")  printf '%s\n' "$3" ;;
  "projects create") exit 0 ;;
  "services enable") exit 0 ;;
  "services list")  printf '%s\n' "\$STUB_ENABLED" ;;
esac
exit 0
STUB
  chmod +x "$1/gcloud"
}

run(){ # run connect.sh with a controlled PATH; echoes output, sets RC
  local bin="$1"; shift
  OUTPUT="$(PATH="$bin:$PATH" bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}

echo "── 1. the API set derives from connector.json, and covers every group ──"
PERM_GROUPS="$(python3 -c '
import json,sys
a=json.load(open(sys.argv[1]))["register"]["args"]
print("\n".join(x.split(":")[0] for x in a[a.index("--permissions")+1:] if not x.startswith("-")))' "$MANIFEST")"
NGROUPS="$(printf '%s\n' "$PERM_GROUPS" | grep -c .)"
APIS="$(bash "$SCRIPT" --print-apis 2>&1)"; RC=$?
NAPIS="$(printf '%s\n' "$APIS" | grep -c .)"
if [ "$RC" -ne 0 ]; then
  no "--print-apis failed" "$APIS"
elif [ "$NGROUPS" -lt 5 ]; then
  no "only $NGROUPS permission groups parsed — the manifest probe is broken, not the manifest"
elif [ "$NAPIS" -eq "$NGROUPS" ]; then
  ok "$NGROUPS permission groups → $NAPIS APIs, one each"
else
  no "$NGROUPS groups produced $NAPIS APIs" "$APIS"
fi

# every API is a plausible service name, and the list has no duplicates
BAD="$(printf '%s\n' "$APIS" | grep -vE '^[a-z0-9-]+\.googleapis\.com$' | grep . || true)"
[ -z "$BAD" ] && ok "every derived entry is an API service name" || no "not API service names: $BAD"
DUPES="$(printf '%s\n' "$APIS" | sort | uniq -d | grep . || true)"
[ -z "$DUPES" ] && ok "no duplicate APIs" || no "duplicated: $DUPES"

echo "── 2. CONTROL — an unmapped permission group must STOP the script ──"
# This is the assertion the whole design rests on. If a new service can be added
# to the manifest and silently produce a project missing its API, the derivation
# buys nothing. Inject a bogus group and require a hard failure that NAMES it.
FIXDIR="$TMP/fixture"; mkdir -p "$FIXDIR"
cp "$SCRIPT" "$FIXDIR/connect.sh"
python3 - "$MANIFEST" "$FIXDIR/connector.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
args = d["register"]["args"]
args.insert(args.index("--permissions") + 1, "quantumdrive:full")
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
if grep -q 'quantumdrive' "$FIXDIR/connector.json"; then
  ok "injection assertion: the fixture really contains the unmapped group"
  OUT="$(bash "$FIXDIR/connect.sh" --print-apis 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ]; then
    no "an unmapped group produced a SUCCESSFUL API list" "$OUT"
  elif printf '%s' "$OUT" | grep -q 'quantumdrive'; then
    ok "unmapped group fails loudly and names the group"
  else
    no "it failed, but without naming the offending group" "$OUT"
  fi
else
  no "fixture injection did not take — this check proves nothing"
fi

echo "── 3. one list, and it lives in the script's mapping only ──"
# Extract api_for()'s line range and require every API-service literal in the
# file to sit inside it. A second hardcoded list anywhere else is the drift this
# change removes, so it fails the build rather than waiting to be noticed.
START="$(grep -n '^api_for()' "$SCRIPT" | head -1 | cut -d: -f1)"
END="$(awk -v s="$START" 'NR>s && /^}/ {print NR; exit}' "$SCRIPT")"
if [ -n "$START" ] && [ -n "$END" ]; then
  OUTSIDE="$(grep -nE '[a-z0-9-]+\.googleapis\.com' "$SCRIPT" \
    | awk -F: -v s="$START" -v e="$END" '$1 < s || $1 > e' | grep . || true)"
  [ -z "$OUTSIDE" ] \
    && ok "every API literal is inside api_for() (lines $START-$END)" \
    || no "API name written outside the mapping:" "$OUTSIDE"
else
  no "could not locate api_for() — the structural check cannot run"
fi

# and the docs must not restate it either — they defer to --print-apis
DOCDRIFT=""
for d in mcps/google-workspace-mcp/personal-account-setup.md mcps/google-workspace-mcp/README.md; do
  [ -f "$d" ] || continue
  grep -qE '^[^h]*[a-z0-9-]+\.googleapis\.com' "$d" && DOCDRIFT="$DOCDRIFT $d"
done
[ -z "$DOCDRIFT" ] \
  && ok "setup docs restate no API list" \
  || no "a doc hardcodes API names again:$DOCDRIFT" "point at --print-apis instead"
grep -q -- '--print-apis' mcps/google-workspace-mcp/personal-account-setup.md \
  && ok "the setup doc points at --print-apis" \
  || no "personal-account-setup.md does not reference --print-apis"

# The copy in SETUP.md was PROSE, not a literal -- "the core seven (Drive, Docs,
# Sheets, Slides, Calendar, Tasks, Gmail) plus People API for contacts ... and Chat
# API if you add chat" -- so a check for `*.googleapis.com` would have missed it
# entirely, which is how it drifted to naming an API nothing requests. Catch the
# shape instead: a line that says "API" and names three or more of the services is
# an enumeration of the list, wherever it lives.
#
# A line that names the services WITHOUT saying "API" is a value statement ("enables
# Calendar, Tasks, Drive ...") and is fine -- it tells an operator what they get, it
# does not send them to go and enable things.
ENUM="$(python3 tests/fixtures/google-connect-enum-scan.py)"
[ -z "$ENUM" ] \
  && ok "no doc enumerates the APIs to enable in prose either" \
  || no "a doc re-enumerates the API list:" "$ENUM"


# CONTROLS for that scanner. A drift detector with no controls is the thing it is
# meant to prevent: it would report "clean" just as convincingly if it were broken,
# and it very nearly was -- the first version fired on an unrelated SETUP.md note
# about USER.md Sources, and an earlier one MISSED the copy whose service names sat
# in a blockquote on the following line. So each historical copy is replayed as a
# fixture and must still be caught, and the coincidence must stay silent.
CTL="$TMP/enumctl"; mkdir -p "$CTL"
cp tests/fixtures/google-connect-enum-scan.py "$CTL/scan.py"
ctl(){ # $1 label · $2 expect(catch|silent) · stdin = the fixture
  rm -f "$CTL/SETUP.md"; cat > "$CTL/SETUP.md"
  R="$(cd "$CTL" && python3 scan.py)"
  if [ "$2" = catch ]; then
    [ -n "$R" ] && ok "scanner control: $1 → caught" || no "scanner control: $1 → MISSED" "the detector cannot see a copy it is supposed to catch"
  else
    [ -z "$R" ] && ok "scanner control: $1 → silent" || no "scanner control: $1 → false positive" "$R"
  fi
}
ctl "prose copy (the SETUP.md one)" catch <<'FIX'
so your Cloud project needs the matching nine APIs enabled — the core seven (Drive, Docs, Sheets, Slides, Calendar, Tasks, Gmail) plus People API for `contacts` and Forms API for `forms`.
FIX
ctl "list on the line AFTER the instruction" catch <<'FIX'
**2. Enable APIs** — APIs & Services → **Library** → enable each (search → Enable).
> **Drive · Docs · Sheets · Slides · Calendar · Tasks · Gmail** — the core seven
FIX
ctl "service→API mapping (the TROUBLESHOOTING one)" catch <<'FIX'
2. **Enable the matching Google API** for each service you added — People for `contacts`,
   Forms for `forms`, Google Chat for `chat`, Apps Script for `appscript`, Custom Search for
   `search`.
FIX
ctl "unrelated prose using both words far apart" silent <<'FIX'
**What Claude asks you** (only if needed):
- Your Google email (for Calendar/Tasks/Drive)
- **Which Google Tasks list to read.** Without it the Tasks source is enabled but never queried — `/aios:today` will have no tasks. Get the ID from the Tasks API (`tasklists.list`).
FIX

echo "── 3a. no doc hands the operator a hand-typed --permissions list ──"
# The SEVENTH copy of this fact was not an API list at all -- it was a
# `--permissions` list inside a `uvx` command that mcps-setup.md told the
# operator to run, and it had drifted to SIX services while the connector
# requested nine. Following it produced a server that started fine and 403'd on
# Gmail at the first call. Same class as the API list, different surface, so it
# needs its own assertion: a LIST is three or more service:level tokens on ONE
# line -- that is the shape someone copies. Individual services named in
# explanatory prose (`chat:full` is off by default, `search:full` needs a key)
# are not a list and must not fire.
SVC='(drive|sheets|slides|docs|calendar|tasks|gmail|contacts|forms|chat|search|appscript):(full|readonly|organize|drafts|send)'
perm_lists(){ # $1 = file → prints "path:line" for any line carrying >=3 tokens
  grep -nE -- "$SVC" "$1" 2>/dev/null | while IFS= read -r hit; do
    ln="${hit%%:*}"; body="${hit#*:}"
    n="$(printf '%s' "$body" | grep -oE -- "$SVC" | sort -u | grep -c .)"
    [ "$n" -ge 3 ] && printf '%s:%s(%s tokens) ' "$1" "$ln" "$n"
  done
}
HARD=""
for f in SETUP.md README.md CHEATSHEET.md TOOLS.md plugins/aios/commands/mcps-setup.md \
         mcps/google-workspace-mcp/README.md mcps/google-workspace-mcp/personal-account-setup.md \
         mcps/google-workspace-mcp/TROUBLESHOOTING.md; do
  [ -f "$f" ] || continue
  HARD="$HARD$(perm_lists "$f")"
done
[ -z "$HARD" ] \
  && ok "no hand-typed --permissions list outside connector.json" \
  || no "a doc hard-codes the permission list:" "$HARD
        connector.json is its only home; connect.sh --finish prints the registration from it"

# CONTROLS — the exact drifted line that shipped, and the prose that must not fire.
CTL2="$TMP/permctl"; mkdir -p "$CTL2"
printf '%s\n' 'ask user to run `uvx workspace-mcp --single-user --permissions drive:full sheets:full slides:full docs:full calendar:full tasks:full`' > "$CTL2/SETUP.md"
R="$(cd "$CTL2" && grep -nE -- "$SVC" SETUP.md | while IFS= read -r h; do b="${h#*:}"; n="$(printf '%s' "$b" | grep -oE -- "$SVC" | sort -u | grep -c .)"; [ "$n" -ge 3 ] && echo hit; done)"
[ -n "$R" ] && ok "control: the drifted uvx list → caught" || no "control: the real drifted list → MISSED"
printf '%s\n' '**Google Chat is off by default.** Add `chat:full` (or `chat:readonly`) for spaces.' > "$CTL2/SETUP.md"
R="$(cd "$CTL2" && grep -nE -- "$SVC" SETUP.md | while IFS= read -r h; do b="${h#*:}"; n="$(printf '%s' "$b" | grep -oE -- "$SVC" | sort -u | grep -c .)"; [ "$n" -ge 3 ] && echo hit; done)"
[ -z "$R" ] && ok "control: prose naming one service → silent" || no "control: prose fired a false positive"

echo "── 3c. a session can drive it without parsing prose ──"
BIN="$TMP/drv"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/drv.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=example.com STUB_ENABLED=""
export GOOGLE_WORKSPACE_CRED_DIR="$TMP/drvcreds"
run "$BIN" --dry-run
ID="$(printf '%s' "$OUTPUT" | sed -n 's/^AIOS_PROJECT_ID=//p')"
{ [ -n "$ID" ] && [ "$(printf '%s' "$ID" | grep -c .)" = 1 ]; } \
  && ok "one stable AIOS_PROJECT_ID= line ($ID)" \
  || no "no single machine-readable project id line" "a driver would have to parse prose"
# --dry-run must not leave state behind
[ -f "$TMP/drvcreds/.aios-project" ] && no "--dry-run recorded project state" || ok "--dry-run records no state"
# a real run records it, and --finish then needs NO arguments
export GCLOUD_LOG="$TMP/drv2.log"; : > "$GCLOUD_LOG"
run "$BIN"
[ "$(cat "$TMP/drvcreds/.aios-project" 2>/dev/null)" = "$(printf '%s' "$OUTPUT" | sed -n 's/^AIOS_PROJECT_ID=//p')" ] \
  && ok "a real run records the project id for --finish" \
  || no "project id not recorded, or disagrees with the emitted line"

echo "── 3b. the mapping covers every service the upstream supports ──"
# connector.json only requests nine today, so the other suites cannot notice a
# missing row until someone edits the manifest and the script stops. The README
# documents the full set the upstream server accepts; every one of them should
# already resolve, so adding a service stays a one-line manifest edit.
UPSTREAM_SVCS="$(sed -n 's/^Services: //p' mcps/google-workspace-mcp/README.md | tr -d '`' | tr '·' '\n' | tr -d ' ' | grep . || true)"
if [ -z "$UPSTREAM_SVCS" ]; then
  no "could not read the service list from README.md — this check proves nothing"
else
  NSVC="$(printf '%s\n' "$UPSTREAM_SVCS" | grep -c .)"
  UNMAPPED=""
  for svc in $UPSTREAM_SVCS; do
    grep -qE "^[[:space:]]*$svc\)" "$SCRIPT" || UNMAPPED="$UNMAPPED $svc"
  done
  [ -z "$UNMAPPED" ] \
    && ok "all $NSVC upstream services have a row in api_for()" \
    || no "no api_for() row for:$UNMAPPED" "adding one of these to connector.json would stop connect.sh"
fi

echo "── 4. preflight refuses cleanly ──"
# A PATH holding every tool the script needs EXCEPT gcloud. An empty PATH would
# also remove bash and python3, so the run would die for the wrong reason and the
# check would pass without ever exercising the branch it names.
NOGC="$TMP/nogcloud"; mkdir -p "$NOGC"
# `type -P` resolves ONLY a real executable on disk. `command -v` would answer
# with a bare name for a shell function -- and an interactive shell may well wrap
# `grep` in one -- producing a farm of DANGLING symlinks. The script then fails
# with "grep: command not found" and the check appears to pass for the right
# reason while actually never reaching the branch it names.
for t in bash env python3 dirname basename grep sed awk tr cat date mkdir head cut sort uniq wc ls cp chmod printf; do
  p="$(type -P "$t" 2>/dev/null)" || p=""
  [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$NOGC/$t"
done
for t in grep sed python3; do
  [ -x "$NOGC/$t" ] || no "harness: $NOGC/$t is not a working executable" \
    "a dangling link makes the no-gcloud check fail for the wrong reason"
done
[ -x "$NOGC/python3" ] && ok "harness: python3 reachable without gcloud" \
  || no "harness: could not stage python3 — the no-gcloud check cannot run"
BASH_BIN="$(command -v bash)"
OUTPUT="$(PATH="$NOGC" "$BASH_BIN" "$SCRIPT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ]; then
  no "ran to completion with no gcloud on PATH"
elif printf '%s' "$OUTPUT" | grep -q 'gcloud is not installed'; then
  ok "no gcloud → clean refusal naming gcloud"
else
  no "refused, but not because of gcloud" "$OUTPUT"
fi
printf '%s' "$OUTPUT" | grep -q 'cloud.google.com/sdk' \
  && ok "and points at the installer" || no "refusal offers no way forward"

BIN="$TMP/anon"; mk_gcloud "$BIN" anon ""
export GCLOUD_LOG="$TMP/anon.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
run "$BIN"
if [ "$RC" -eq 0 ]; then
  no "proceeded while gcloud was unauthenticated"
elif printf '%s' "$OUTPUT" | grep -q 'gcloud auth login'; then
  ok "unauthenticated gcloud → refusal naming \`gcloud auth login\`"
else
  no "refused but never named the fix" "$OUTPUT"
fi
grep -q 'projects create' "$GCLOUD_LOG" && no "created a project despite refusing" || ok "no project created on refusal"

echo "── 4b. --dry-run refuses too, and says nothing was created ──"
# A dry run must NOT skip the preflight. Skipping it would print a confident
# plan that cannot execute -- the operator's whole reason for running --dry-run
# is to find out whether this will work on their machine. And a red refusal
# mid-setup makes anyone wonder if they are now half-configured, so both
# refusals say plainly that nothing was created.
OUTPUT="$(PATH="$NOGC" "$BASH_BIN" "$SCRIPT" --dry-run 2>&1)"; RC=$?
{ [ "$RC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -q 'gcloud is not installed'; } \
  && ok "--dry-run with no gcloud → refuses, naming gcloud" \
  || no "--dry-run skipped the missing-gcloud preflight" "it would print a plan that cannot run" 
printf '%s' "$OUTPUT" | grep -qi 'nothing has been created' \
  && ok "and says nothing was created" || no "refusal leaves the operator wondering if they are half-configured"
# the hint must be actionable for THIS platform, not a bare doc URL when a one-liner exists
if [ "$(uname -s)" = Darwin ] && command -v brew >/dev/null 2>&1; then
  printf '%s' "$OUTPUT" | grep -q 'brew install --cask google-cloud-sdk' \
    && ok "macOS + brew → the hint is the one-liner" \
    || no "on a Mac with brew the hint is still a doc URL" "$OUTPUT"
else
  printf '%s' "$OUTPUT" | grep -q 'cloud.google.com/sdk' \
    && ok "hint points at the installer for this platform" || no "no install hint at all"
fi

BIN="$TMP/anon2"; mk_gcloud "$BIN" anon ""
export GCLOUD_LOG="$TMP/anon2.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
run "$BIN" --dry-run
{ [ "$RC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -q 'gcloud auth login'; } \
  && ok "--dry-run while logged out → refuses, naming \`gcloud auth login\`" \
  || no "--dry-run skipped the authentication preflight" "$OUTPUT"
printf '%s' "$OUTPUT" | grep -qi 'nothing has been created' \
  && ok "and says nothing was created" || no "logged-out refusal does not reassure"
grep -qE 'projects create|services enable' "$GCLOUD_LOG" \
  && no "mutated despite refusing" || ok "no mutating call on either refusal"

echo "── 5. --dry-run mutates nothing ──"
BIN="$TMP/dry"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/dry.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
run "$BIN" --dry-run
if grep -qE 'projects create|services enable' "$GCLOUD_LOG"; then
  no "--dry-run called a mutating gcloud command" "$(cat "$GCLOUD_LOG")"
else
  ok "--dry-run issued no mutating gcloud call"
fi
printf '%s' "$OUTPUT" | grep -q 'would enable' && ok "--dry-run still reports what it would do" \
  || no "--dry-run printed no plan" "$OUTPUT"

echo "── 6. the full run enables every derived API in ONE call ──"
BIN="$TMP/run"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/run.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
run "$BIN"
ENABLE_CALLS="$(grep -c '^services enable' "$GCLOUD_LOG" || true)"
[ "$ENABLE_CALLS" = 1 ] \
  && ok "one \`services enable\` call, not $NAPIS of them" \
  || no "expected 1 enable call, saw $ENABLE_CALLS"
MISSED=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  grep -q -- "$a" "$GCLOUD_LOG" || MISSED="$MISSED $a"
done <<EOF
$APIS
EOF
[ -z "$MISSED" ] && ok "all $NAPIS APIs passed to gcloud" || no "never enabled:$MISSED"

echo "── 7. the account type decides which clicks are shown ──"
printf '%s' "$OUTPUT" | grep -q 'Test user' \
  && ok "consumer account → test-user step shown" || no "consumer account: no test-user step"
printf '%s' "$OUTPUT" | grep -q '7 days' \
  && ok "consumer account → the 7-day Testing clock is named" || no "consumer: 7-day clock not named"
BIN="$TMP/ws"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/ws.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=example.com STUB_ENABLED=""
run "$BIN"
if printf '%s' "$OUTPUT" | grep -q 'Internal'; then
  ok "workspace account → Internal audience"
else
  no "workspace account was not routed to Internal" "$OUTPUT"
fi
printf '%s' "$OUTPUT" | grep -q '7 days' \
  && no "workspace account shown the 7-day clock, which cannot apply to it" \
  || ok "workspace account not warned about a trap it cannot hit"

echo "── 8. an existing project is offered, never silently duplicated ──"
BIN="$TMP/exist"; mk_gcloud "$BIN" authed "aios-workspace-260101-1234"
export GCLOUD_LOG="$TMP/exist.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
run "$BIN"
if grep -q 'projects create' "$GCLOUD_LOG"; then
  no "created a second project while one already existed"
elif printf '%s' "$OUTPUT" | grep -q 'aios-workspace-260101-1234'; then
  ok "existing project surfaced instead of creating another"
else
  no "neither reused nor reported the existing project" "$OUTPUT"
fi
export GCLOUD_LOG="$TMP/exist2.log"; : > "$GCLOUD_LOG"
run "$BIN" --new
grep -q 'projects create' "$GCLOUD_LOG" && ok "--new overrides and creates one" || no "--new did not create"

echo "── 9. --finish rejects the two client mistakes that fail LATE ──"
BIN="$TMP/fin"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/fin.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com STUB_ENABLED=""
export GOOGLE_WORKSPACE_CRED_DIR="$TMP/creds"
cat > "$TMP/web.json" <<'J'
{"web":{"client_id":"x.apps.googleusercontent.com","client_secret":"s","project_id":"p1"}}
J
cat > "$TMP/wrongproj.json" <<'J'
{"installed":{"client_id":"x.apps.googleusercontent.com","client_secret":"s","project_id":"other-project"}}
J
cat > "$TMP/good.json" <<'J'
{"installed":{"client_id":"x.apps.googleusercontent.com","client_secret":"s","project_id":"p1"}}
J
run "$BIN" --finish --project-id p1 --client "$TMP/web.json"
{ [ "$RC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -qi 'desktop'; } \
  && ok "a Web client is rejected, naming Desktop as the fix" \
  || no "Web client accepted (this surfaces later as redirect_uri_mismatch)" "$OUTPUT"
run "$BIN" --finish --project-id p1 --client "$TMP/wrongproj.json"
{ [ "$RC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -q 'other-project'; } \
  && ok "a client from another project is rejected, naming both projects" \
  || no "wrong-project client accepted (this surfaces later as 403 org_internal)" "$OUTPUT"
run "$BIN" --finish --project-id p1 --client "$TMP/good.json"
if [ "$RC" -ne 0 ]; then
  no "a valid Desktop client for the right project was rejected" "$OUTPUT"
elif [ -f "$TMP/creds/client_secret.json" ]; then
  PERM="$(ls -l "$TMP/creds/client_secret.json" | cut -c1-10)"
  case "$PERM" in -rw-------) ok "valid client installed 0600 outside the vault" ;;
                  *) no "installed with permissions $PERM, expected -rw-------" ;; esac
else
  no "accepted but wrote no credential file"
fi
printf '%s' "$OUTPUT" | grep -q 'claude mcp add' \
  && ok "--finish prints the registration command" || no "--finish printed no registration command"
# the registration it prints must come from the manifest, not a second copy
printf '%s' "$OUTPUT" | grep -q -- '--permissions' \
  && ok "the printed registration carries the manifest's permissions" \
  || no "printed registration has no --permissions — it is not manifest-derived"

echo "── 10. --verify reports missing APIs, and says what cannot be checked ──"
BIN="$TMP/ver"; mk_gcloud "$BIN" authed ""
export GCLOUD_LOG="$TMP/ver.log"; : > "$GCLOUD_LOG"; export STUB_DOMAIN=gmail.com
export STUB_ENABLED="$(printf '%s\n' "$APIS" | head -3)"
run "$BIN" --verify --project-id p1
{ [ "$RC" -ne 0 ] && printf '%s' "$OUTPUT" | grep -q 'gmail.googleapis.com'; } \
  && ok "a partially-enabled project fails and names what is missing" \
  || no "missing APIs not reported" "$OUTPUT"
printf '%s' "$OUTPUT" | grep -q 'gcloud services enable' \
  && ok "and prints the command that fixes it" || no "no remediation command"
export STUB_ENABLED="$APIS"
run "$BIN" --verify --project-id p1
{ [ "$RC" -eq 0 ] && printf '%s' "$OUTPUT" | grep -q "all $NAPIS APIs enabled"; } \
  && ok "a fully-enabled project verifies clean" || no "clean project did not verify" "$OUTPUT"
printf '%s' "$OUTPUT" | grep -qi 'cannot be read back' \
  && ok "verify states what it CANNOT check rather than implying full coverage" \
  || no "verify implies it checked the consent screen, which no API exposes"

echo "── 11. portable to the bash 3.2 that ships on macOS ──"
B32=""
grep -qE '^\s*declare -A|^\s*local -A' "$SCRIPT" && B32="$B32 associative-array"
grep -qE '\bmapfile\b|\breadarray\b'            "$SCRIPT" && B32="$B32 mapfile"
grep -qE '\$\{[A-Za-z_]+\^\^|\$\{[A-Za-z_]+,,'  "$SCRIPT" && B32="$B32 case-expansion"
[ -z "$B32" ] && ok "no bash 4+ constructs" || no "bash 4-only construct(s):$B32"

# Assigning a bash special variable is SILENT: the write is discarded and the read
# returns bash's value. This suite lost an hour to `GROUPS=` returning the caller's
# gid (20) as if it were manifest data -- and only under bash, because zsh has no
# such variable, so the same line worked when pasted into a terminal.
# Enumerated, not globbed: `BASH_[A-Z]+` also matches a perfectly ordinary
# BASH_BIN and reports it as a bug. A guard that fires on correct code gets
# switched off, which is worse than not having it.
SPECIAL='GROUPS|SECONDS|RANDOM|LINENO|PIPESTATUS|FUNCNAME|DIRSTACK|SHELLOPTS|UID|EUID|PPID|HISTCMD'
SPECIAL="$SPECIAL|BASHPID|BASHOPTS|BASH_REMATCH|BASH_SOURCE|BASH_LINENO|BASH_VERSION|BASH_VERSINFO|BASH_SUBSHELL|BASH_COMMAND|BASH_ARGC|BASH_ARGV"
for f in "$SCRIPT" "$0"; do
  HIT="$(grep -nE "^[[:space:]]*(local[[:space:]]+|export[[:space:]]+)?($SPECIAL)=" "$f" | grep . || true)"
  [ -z "$HIT" ] \
    && ok "$(basename "$f") assigns no bash special variable" \
    || no "$(basename "$f") assigns a bash special variable:" "$HIT"
done
bash -n "$SCRIPT" && ok "parses cleanly" || no "syntax error"

echo "── 12. the oauth template carries no scope list to drift ──"
TPL="mcps/google-workspace-mcp/oauth.json.template"
if [ -f "$TPL" ]; then
  python3 - "$TPL" <<'PY' && ok "template has no frozen \`scopes\` array" || no "the template still ships a scope list — it is a fourth copy, and nothing reads it"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if "scopes" in d else 0)
PY
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TPL" \
    && ok "template is valid JSON" || no "template is not valid JSON"
  for k in client_id client_secret; do
    python3 -c '
import json,sys
sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1])) else 1)' "$TPL" "$k" \
      && ok "template keeps \`$k\` (SETUP.md reads it)" || no "template lost \`$k\` — SETUP.md reads it"
  done
fi

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

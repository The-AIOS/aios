#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# connect.sh — Google Workspace connector setup, in one command.
#
# Google exposes an API for exactly half of this. Project creation and API
# enablement are automatable; the consent screen and the OAuth client are
# console-only — no API exists for either, in any gcloud release. So this script
# does not pretend to automate the whole thing. It does the two automatable
# parts (which are also the two tedious ones), and hands you the rest as a short
# numbered list of links that land on the exact page for YOUR project.
#
# The structural part of the fix is the API list. It is DERIVED from
# connector.json's `--permissions` — the same manifest that registers the
# server — rather than typed here. A scope whose API is not enabled is the
# single most confusing failure in this setup: consent succeeds, the tool
# appears, and the first call returns `403 SERVICE_DISABLED`, which reads like
# an auth problem and is not. Deriving both lists from one source makes that
# mismatch impossible to express rather than something a doc has to warn about.
#
# Three lists of this same fact existed before this script and all three
# disagreed. That is what a hand-maintained list does, given enough time.
#
# Usage:
#   bash connect.sh                      create a project, enable every API
#   bash connect.sh --project-id ID      use a project you already have
#   bash connect.sh --new                create another, even if one exists
#   bash connect.sh --verify  --project-id ID    re-check the APIs are on
#   bash connect.sh --finish  --project-id ID --client PATH.json
#                                        install the downloaded client + print
#                                        the registration command
#   bash connect.sh --print-apis         print the derived API list and exit
#   bash connect.sh --dry-run            say what would happen, change nothing
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/connector.json"
CRED_DIR="${GOOGLE_WORKSPACE_CRED_DIR:-$HOME/.google_workspace_mcp}"

MODE=connect
PROJECT_ID=""
CLIENT_JSON=""
FORCE_NEW=0
DRY_RUN=0

b(){ printf '\033[1m%s\033[0m\n' "$1"; }
say(){ printf '%s\n' "$1"; }
die(){ printf '\n✗ %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project-id) PROJECT_ID="${2:-}"; shift 2 ;;
    --client)     CLIENT_JSON="${2:-}"; shift 2 ;;
    --new)        FORCE_NEW=1; shift ;;
    --verify)     MODE=verify; shift ;;
    --finish)     MODE=finish; shift ;;
    --print-apis) MODE=print-apis; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    sed -n '4,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown argument: $1" "run with --help" ;;
  esac
done

# ── the mapping: one permission group → the Google API that serves it ────────
# This is the ONLY place an API name is written. Everything else derives.
# A group with no row here is a hard failure, never a silent skip — see
# derive_apis(). Adding a service to connector.json's --permissions without
# adding its row here stops the script rather than shipping a half-enabled
# project, which is the whole point.
api_for(){
  case "$1" in
    drive)     printf 'drive.googleapis.com\n' ;;
    docs)      printf 'docs.googleapis.com\n' ;;
    sheets)    printf 'sheets.googleapis.com\n' ;;
    slides)    printf 'slides.googleapis.com\n' ;;
    calendar)  printf 'calendar-json.googleapis.com\n' ;;
    tasks)     printf 'tasks.googleapis.com\n' ;;
    gmail)     printf 'gmail.googleapis.com\n' ;;
    contacts)  printf 'people.googleapis.com\n' ;;
    forms)     printf 'forms.googleapis.com\n' ;;
    chat)      printf 'chat.googleapis.com\n' ;;
    search)    printf 'customsearch.googleapis.com\n' ;;
    appscript) printf 'script.googleapis.com\n' ;;
    *)         return 1 ;;
  esac
}

# `openid`, `userinfo.email` and `userinfo.profile` are deliberately absent:
# they are granted by the consent screen itself and have no API to enable.

# The most actionable install instruction for THIS machine. A doc URL is the
# fallback, not the answer: on macOS with Homebrew already present there is a
# one-liner, and handing someone a documentation page instead is the same
# friction this script exists to remove. It SUGGESTS and never installs —
# putting an SDK on an operator's machine is their call, not a script's.
gcloud_install_hint(){
  case "$OSTYPE" in
    darwin*)
      if command -v brew >/dev/null 2>&1; then
        printf 'brew install --cask google-cloud-sdk'
      else
        printf 'https://cloud.google.com/sdk/docs/install — or install Homebrew first, then: brew install --cask google-cloud-sdk'
      fi ;;
    msys*|cygwin*|win*)
      printf 'https://cloud.google.com/sdk/docs/install (Windows installer)' ;;
    *)
      printf 'https://cloud.google.com/sdk/docs/install' ;;
  esac
}

need_python(){
  command -v python3 >/dev/null 2>&1 \
    || die "python3 not found." "It reads connector.json. On macOS: xcode-select --install"
}

# Permission GROUPS, in manifest order: `drive:full` → `drive`.
permission_groups(){
  python3 - "$MANIFEST" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit("connector.json unreadable: %s" % e)
args = d.get("register", {}).get("args", [])
if "--permissions" not in args:
    sys.exit("connector.json register.args has no --permissions list")
out = []
for a in args[args.index("--permissions") + 1:]:
    if a.startswith("-"):
        break
    out.append(a.split(":")[0])
if not out:
    sys.exit("--permissions is present but empty")
print("\n".join(out))
PY
}

has_line(){ printf '%s\n' "$2" | grep -qx -- "$1"; }

# Newline-separated API list on stdout. Non-zero if any group is unmapped.
derive_apis(){
  local groups g a apis="" unmapped=""
  groups="$(permission_groups)" || return 1
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if a="$(api_for "$g")"; then
      has_line "$a" "$apis" || apis="${apis:+$apis
}$a"
    else
      unmapped="$unmapped $g"
    fi
  done <<EOF
$groups
EOF
  if [ -n "$unmapped" ]; then
    printf 'no Google API is mapped for permission group(s):%s\n' "$unmapped" >&2
    printf 'add a row to api_for() in %s — the manifest and this mapping must agree.\n' "$0" >&2
    return 1
  fi
  printf '%s\n' "$apis"
}

# ── print-apis: the derivation, inspectable on its own ───────────────────────
if [ "$MODE" = print-apis ]; then
  need_python
  APIS="$(derive_apis)" || die "could not derive the API list from connector.json"
  printf '%s\n' "$APIS"
  exit 0
fi

need_python
APIS="$(derive_apis)" || die "could not derive the API list from connector.json"
API_COUNT="$(printf '%s\n' "$APIS" | grep -c .)"

# ── preflight ────────────────────────────────────────────────────────────────
command -v gcloud >/dev/null 2>&1 || die \
  "gcloud is not installed — this script needs it to create the project and enable APIs." \
  "Nothing has been created, so you are not half-configured.

  Install it:  $(gcloud_install_hint)
  Then re-run this script.

  Or skip gcloud entirely: personal-account-setup.md walks the whole thing through
  the console by hand. Same result, more clicks."

ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
[ -n "$ACCOUNT" ] || die \
  "gcloud is installed but nobody is logged in." \
  "Nothing has been created, so you are not half-configured.

  Run:  gcloud auth login

  Sign in as the ACCOUNT YOU WANT THE MCP TO ACT AS — the project is created under
  whoever is logged in, and a client from one account cannot serve another. Then
  re-run this script."

DOMAIN="${ACCOUNT##*@}"
case "$DOMAIN" in
  gmail.com|googlemail.com) ACCOUNT_KIND=consumer ;;
  *)                        ACCOUNT_KIND=workspace ;;
esac

# ── finish: install the downloaded client, then print the registration ───────
if [ "$MODE" = finish ]; then
  # Both arguments DEFAULT, because every argument is something that can be got
  # wrong -- and these two are the worst kind: a project id that must be copied
  # exactly, and a glob path into ~/Downloads. The connect run already knew the
  # project id, so asking for it back makes the tool's own bookkeeping the
  # operator's problem.
  if [ -z "$PROJECT_ID" ] && [ -f "$CRED_DIR/.aios-project" ]; then
    PROJECT_ID="$(cat "$CRED_DIR/.aios-project" 2>/dev/null)"
    [ -n "$PROJECT_ID" ] && say "project: $PROJECT_ID (recorded by your last connect run)"
  fi
  [ -n "$PROJECT_ID" ] || die \
    "no project id — pass --project-id, or run \`connect.sh\` first so it records one." \
    "The connect run writes it to $CRED_DIR/.aios-project."

  if [ -z "$CLIENT_JSON" ]; then
    # Newest client_secret_*.json in ~/Downloads. Safe to guess precisely BECAUSE
    # the checks below reject a client of the wrong type or from another project,
    # so a wrong guess fails loudly instead of installing quietly.
    CLIENT_JSON="$(ls -t "$HOME"/Downloads/client_secret_*.json 2>/dev/null | head -1)"
    [ -n "$CLIENT_JSON" ] || die \
      "no client_secret_*.json found in ~/Downloads." \
      "Download it from the Clients page, or pass --client <path>."
    say "client: $CLIENT_JSON (newest in ~/Downloads)"
  fi
  [ -f "$CLIENT_JSON" ] || die "no such file: $CLIENT_JSON"

  # Two traps that ARE readable, so they stop the run instead of surfacing later
  # as `redirect_uri_mismatch` and `403 org_internal` — neither of which names
  # its own cause.
  CHECK="$(python3 - "$CLIENT_JSON" "$PROJECT_ID" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit("that file is not readable JSON: %s" % e)
want = sys.argv[2]
if "web" in d and "installed" not in d:
    sys.exit("this is a WEB application client. The flow redirects to http://localhost, "
             "which a Web client rejects with redirect_uri_mismatch.\n  "
             "Create the client again with Application type = Desktop app.")
if "installed" not in d:
    sys.exit("this JSON has neither an `installed` nor a `web` client. "
             "Download it again from the Clients page (the button is on the client's row).")
got = d["installed"].get("project_id", "")
if got and got != want:
    sys.exit("this client belongs to project `%s`, but the APIs were enabled in `%s`.\n  "
             "Using it is the cause of `403 org_internal` and of `SERVICE_DISABLED` errors.\n  "
             "Download the client from %s, or re-run with --project-id %s." % (got, want, want, got))
print(d["installed"].get("client_id", ""))
PY
)" || die "$CHECK"
  CLIENT_ID="$CHECK"

  mkdir -p "$CRED_DIR"
  if [ "$DRY_RUN" = 1 ]; then
    say "dry-run: would copy $CLIENT_JSON → $CRED_DIR/client_secret.json (chmod 600)"
  else
    cp "$CLIENT_JSON" "$CRED_DIR/client_secret.json" || die "could not write $CRED_DIR/client_secret.json"
    chmod 600 "$CRED_DIR/client_secret.json"
    say "✓ client installed at $CRED_DIR/client_secret.json (0600, machine-local, never in the vault)"
  fi
  say "✓ Desktop client, and it belongs to $PROJECT_ID"
  say ""
  b "Register the connector"
  say "Run /aios:mcps-setup and pick Google Workspace, or register it directly:"
  say ""
  python3 - "$MANIFEST" "$CRED_DIR" <<'PY'
import json, sys, shlex
d = json.load(open(sys.argv[1]))
reg = d.get("register", {})
args = reg.get("args", [])
cmd = ["claude", "mcp", "add", d.get("id", "google-workspace"), "--scope", "user",
       "--env", "GOOGLE_CLIENT_SECRET_PATH=%s/client_secret.json" % sys.argv[2],
       "--env", "OAUTHLIB_RELAX_TOKEN_SCOPE=1",
       "--", reg.get("command", "uvx")] + args
print("  " + " ".join(shlex.quote(c) for c in cmd))
PY
  say ""
  say "Then restart your Claude session — MCP tools register at session start, so one added"
  say "mid-session is not callable until the next one."
  exit 0
fi

# ── verify: read the enabled APIs back ───────────────────────────────────────
if [ "$MODE" = verify ]; then
  [ -n "$PROJECT_ID" ] || die "--verify needs --project-id"
  ENABLED="$(gcloud services list --enabled --project="$PROJECT_ID" --format='value(config.name)' 2>&1)" \
    || die "could not list services for $PROJECT_ID" "$ENABLED"
  MISSING=""
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    has_line "$a" "$ENABLED" || MISSING="${MISSING:+$MISSING }$a"
  done <<EOF
$APIS
EOF
  if [ -n "$MISSING" ]; then
    say "✗ not enabled in $PROJECT_ID:"
    for m in $MISSING; do say "    $m"; done
    say ""
    say "  Enable them:  gcloud services enable$(printf ' %s' $MISSING) --project=$PROJECT_ID"
    exit 1
  fi
  say "✓ all $API_COUNT APIs enabled in $PROJECT_ID"
  say "  (the consent screen and the client cannot be read back — Google exposes no API for"
  say "   either. If the connector still fails, TROUBLESHOOTING.md maps each error to its page.)"
  exit 0
fi

# ── connect: the main path ───────────────────────────────────────────────────
b "Google Workspace connector"
say "account:  $ACCOUNT"
say "APIs:     $API_COUNT, derived from connector.json's --permissions"
say ""

if [ -z "$PROJECT_ID" ]; then
  EXISTING="$(gcloud projects list --filter='projectId:aios-workspace-*' --format='value(projectId)' 2>/dev/null)"
  if [ -n "$EXISTING" ] && [ "$FORCE_NEW" = 0 ]; then
    say "You already have a project from a previous run:"
    printf '%s\n' "$EXISTING" | sed 's/^/    /'
    say ""
    die "not creating a second one." \
        "Re-run with --project-id <one of the above> to continue with it,
  or --new to create another anyway."
  fi
  PROJECT_ID="aios-workspace-$(date +%y%m%d)-$(printf '%04d' $((RANDOM % 10000)))"
  if [ "$DRY_RUN" = 1 ]; then
    say "dry-run: would create project $PROJECT_ID"
  else
    say "Creating project $PROJECT_ID …"
    OUT="$(gcloud projects create "$PROJECT_ID" --name='AIOS Google Workspace' 2>&1)" || {
      case "$OUT" in
        *already*in*use*|*ALREADY_EXISTS*)
          die "project id $PROJECT_ID is taken (ids are globally unique across all of Google)." \
              "Re-run — the suffix is random — or pass your own with --project-id." ;;
        *)
          die "gcloud projects create failed." "$OUT" ;;
      esac
    }
    say "✓ project created"
  fi
else
  say "Using project $PROJECT_ID"
fi

# One stable, greppable line. A session driving this reads THIS, never the prose
# below it -- prose is written for the human and is free to be rewritten.
printf 'AIOS_PROJECT_ID=%s\n' "$PROJECT_ID"
if [ "$DRY_RUN" = 0 ]; then
  mkdir -p "$CRED_DIR" && printf '%s\n' "$PROJECT_ID" > "$CRED_DIR/.aios-project"
fi

if [ "$DRY_RUN" = 1 ]; then
  say "dry-run: would enable $API_COUNT APIs in $PROJECT_ID:"
  printf '%s\n' "$APIS" | sed 's/^/    /'
else
  say ""
  say "Enabling $API_COUNT APIs (one call — this is the step that takes ten searches in the console) …"
  # shellcheck disable=SC2046  # deliberate split: gcloud takes the APIs as separate args
  OUT="$(gcloud services enable $(printf '%s ' $APIS) --project="$PROJECT_ID" 2>&1)" \
    || die "could not enable the APIs in $PROJECT_ID." "$OUT"
  say "✓ enabled:"
  printf '%s\n' "$APIS" | sed 's/^/    /'
fi

CONSOLE="https://console.cloud.google.com"
say ""
b "What is left — it is console-only, because Google publishes no API for it"
say ""
say "  1. Branding — app name + your email on the consent screen"
say "     $CONSOLE/auth/branding?project=$PROJECT_ID"
say ""
if [ "$ACCOUNT_KIND" = workspace ]; then
  say "  2. Audience → Internal"
  say "     $CONSOLE/auth/audience?project=$PROJECT_ID"
  say "     $ACCOUNT is a Workspace account, so Internal is available and is the one"
  say "     you want: the app is internal to your org, trusted by default, with no test-user"
  say "     list and no 7-day re-auth clock. (If your admin gates internal apps, this is the"
  say "     step where you will find out — it is a one-line ask, not a review.)"
else
  say "  2. Audience → External, then add $ACCOUNT as a Test user"
  say "     $CONSOLE/auth/audience?project=$PROJECT_ID"
  say "     A consumer account has no organization, so External is the only option Google"
  say "     offers — and the account must be on the test-user list or consent returns"
  say "     403 access_denied."
  say ""
  say "     ⚠ Testing expires the refresh token after 7 days. It fails weeks later, on a"
  say "       machine you are not watching, as \`invalid_grant\` — the single most expensive"
  say "       trap in this setup, because it does not fail during setup. If anything"
  say "       scheduled depends on this connector, publish the app (Audience → Publish app)"
  say "       and read what Google asks of you at that screen before assuming it is free:"
  say "       Gmail and Drive are sensitive scopes."
fi
say ""
say "  3. Create the OAuth client — Application type: Desktop app — and download the JSON"
say "     $CONSOLE/auth/clients/create?project=$PROJECT_ID"
say "     Desktop is required: it is the only type that allows the http://localhost redirect"
say "     this flow uses. A Web client fails with redirect_uri_mismatch."
say ""
b "Then say \"done\" — your Claude session finishes the rest"
say "  It reads the project id and the downloaded client on its own. By hand:"
say "  bash $0 --finish"
say ""
say "It checks the client is Desktop and belongs to this project — the two mistakes that"
say "otherwise surface much later as redirect_uri_mismatch and 403 org_internal — installs"
say "it 0600 outside the vault, and prints the registration command."
say ""
say "Re-check the APIs any time:  bash $0 --verify --project-id $PROJECT_ID"

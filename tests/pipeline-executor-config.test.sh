#!/usr/bin/env bash
# Regression suite for USER.md config-value parsing (hooks/pipeline-executor.py →
# parse_sources()).
#
# Sibling of source-detector.test.sh, which covers whether a source is ON. This file
# covers the VALUES parsed once it is on — the account addresses, tasks list and
# timezone that every downstream lookup is built from.
#
# TEST 1 IS THE CANARY: a USER.md whose "### Google accounts" carries a second block
# naming another address must still report the PRIMARY one. It fails against the pre-fix
# code, which walked every line and let the LAST match win — so a second block silently
# replaced an address that had already been read correctly, and every credentials path
# derived from it (GOOGLE_CREDS_DIR_PRIMARY / f"{email}.json") pointed at a file that
# does not exist. /today then reported Calendar and Tasks as "configured but credentials
# missing" while the primary account's OAuth token was valid throughout.

set -u

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias: a real file on
# PATH that satisfies every existence probe, exits 49 and produces nothing. A
# test that shells out to it does not fail for its own reason — it fails, or
# worse reports a CONTROL as inconclusive, for an environmental one. Same probe
# hooks/claude-identity/claude-identity.sh and mcps/setup.sh already use.
# $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
have(){ [ "$1" = "$2" ] && ok "$3" || { no "$3"; printf '       expected %s, got %s\n' "$2" "$1"; }; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC="$ROOT/hooks/pipeline-executor.py"
[ -f "$EXEC" ] || { echo "cannot find hooks/pipeline-executor.py"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'USER.md config-value parsing\n'

# Load the SHIPPED module and point it at a fixture USER.md, so the test exercises the
# real parse_sources() rather than a copy that can drift away from it.
field(){ # $1 = USER.md content, $2 = config key  →  prints the parsed value
  printf '%s' "$1" > "$TMP/USER.md"
  $PYBIN - "$EXEC" "$TMP/USER.md" "$2" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("pipeline_executor", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.SOURCES_PATH = Path(sys.argv[2])
print(mod.parse_sources()[sys.argv[3]])
PY
}

# ---------------------------------------------------------------------------
# TEST 1 — THE CANARY. A second account block must not overwrite the primary.
# ---------------------------------------------------------------------------
TWO_BLOCKS='## Sources

### Google accounts

*Primary:*
- Google email: `primary@example.com`
- Google Tasks list: `list-primary`

*Secondary:*
- Google email: `secondary@example.com`
- Google Tasks list: `list-secondary`
'
have "$(field "$TWO_BLOCKS" google_email_primary)" "primary@example.com" \
  "1. canary: a second block does not overwrite the primary email"
have "$(field "$TWO_BLOCKS" google_tasks_list)" "list-primary" \
  "1b. canary: nor the primary tasks list"

# ---------------------------------------------------------------------------
# TEST 2 — label-agnostic. The guard must not depend on the word "Secondary".
# ---------------------------------------------------------------------------
ODD_LABEL='## Sources

### Google accounts

- Google email: `primary@example.com`

*Old account (not connected via MCP):*
- Google email: `retired@example.com`
'
have "$(field "$ODD_LABEL" google_email_primary)" "primary@example.com" \
  "2. any later block loses, whatever the operator called it"

# ---------------------------------------------------------------------------
# TEST 3 — no regression on the single-block case the template ships.
# ---------------------------------------------------------------------------
ONE_BLOCK='## Sources

### General
- Timezone: `America/Mexico_City`

### Google accounts

*Primary:*
- Google email: `only@example.com`
- Google Tasks list: `only-list`

*Personal (optional):*
- Google email (Personal): `personal@example.com`
'
have "$(field "$ONE_BLOCK" google_email_primary)" "only@example.com" "3. single block still parses"
have "$(field "$ONE_BLOCK" google_tasks_list)"    "only-list"         "3b. tasks list still parses"
have "$(field "$ONE_BLOCK" timezone)"             "America/Mexico_City" "3c. timezone still parses"

# ---------------------------------------------------------------------------
# TEST 4 — the personal address has its own key and is unaffected by the guard.
# ---------------------------------------------------------------------------
have "$(field "$ONE_BLOCK" google_email_personal)" "personal@example.com" \
  "4. the (Personal) line still fills its own field"

# A second block naming a plain address must not leak into the personal field either.
have "$(field "$TWO_BLOCKS" google_email_personal)" "None" \
  "4b. a second plain address does not become the personal account"

# ---------------------------------------------------------------------------
# TEST 5 — the shipped template's EXAMPLE-ONLY lines declare nothing.
# ---------------------------------------------------------------------------
TEMPLATE='## Sources

### Google accounts

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

*Primary:*
- *Google email: `you@company.com`*
- *Google Tasks list: `your-list-id`*
'
have "$(field "$TEMPLATE" google_email_primary)" "None" \
  "5. a template-only USER.md parses no address"

# ---------------------------------------------------------------------------
# TEST 6 — a missing USER.md still returns defaults rather than raising.
# ---------------------------------------------------------------------------
MISSING="$($PYBIN - "$EXEC" "$TMP/absent-USER.md" 2>/dev/null <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("pipeline_executor", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.SOURCES_PATH = Path(sys.argv[2])
print(mod.parse_sources()["timezone"])
PY
)"
have "$MISSING" "UTC" "6. a missing USER.md falls back to the UTC default"

# ---------------------------------------------------------------------------
# TEST 7 — Calendars to skip, as the template writes it (#243). Only the bold label
# used to match, so the template's own shape gave an empty list and every skipped
# calendar's events still reached the plan, with nothing saying so.
# ---------------------------------------------------------------------------
have "$(field '- Calendars to skip: `Feed Calendar, Formula 1` (sports feeds)
' calendars_skip)" "['Feed Calendar', 'Formula 1']" \
  "7. plain label, backticked value: names read, trailing note ignored"
have "$(field '- Calendars to skip: `Feed Calendar`, `Formula 1`
' calendars_skip)" "['Feed Calendar', 'Formula 1']" \
  "7b. one backtick pair per name"
have "$(field '- **Calendars to skip:** Feed Calendar, Formula 1
' calendars_skip)" "['Feed Calendar', 'Formula 1']" \
  "7c. the older bold label still reads"
have "$(field '- *Calendars to skip: `Formula 1, Holidays in Spain`*
' calendars_skip)" "[]" \
  "7d. the template's italic placeholder is not read as configured"

# ---------------------------------------------------------------------------
# TEST 8 — accounts beyond Primary and Personal. Each is "- Google email (<Label>)" and is
# queried only when "- Google Calendar (<Label>)" is on an operator line too, so an
# address kept for reference switches nothing on.
# ---------------------------------------------------------------------------
THREE='## Sources

### Google accounts

*Primary:*
- Google email: `work@example.com`
- Google Calendar — via Google Workspace MCP

*Personal:*
- Google email (Personal): `me@example.com`
- Google Calendar (Personal) — merged into daily plan

*Second company:*
- Google email (Acme.Labs): `me@acme.example`
- Google Calendar (Acme.Labs) — merged into daily plan
- Google email (Acme.Labs): `later@acme.example`

*Archive:*
- Google email (Old job): `old@example.com`
'
have "$(field "$THREE" google_accounts_extra)" "[('Acme.Labs', 'me@acme.example')]" \
  "8. a labelled third account is read; first line per label wins; no calendar line = off"
have "$(field "$THREE" google_email_primary)" "work@example.com" \
  "8b. the primary is untouched by labelled accounts"
have "$(field "$THREE" google_email_personal)" "me@example.com" \
  "8c. Personal keeps its own slot and is not repeated as an extra"
have "$(field '- Google email (personal): `me@example.com`
- Google Calendar (personal)
' google_accounts_extra)" "[]" \
  "8d. Personal in any case never becomes an extra account"
have "$(field '*EXAMPLE ONLY (Claude: ignore these):*

- *Google email (Team): `team@example.com`*
- *Google Calendar (Team) — merged*
' google_accounts_extra)" "[]" \
  "8e. the template's italic placeholders declare no extra account"

SLUGS="$($PYBIN - "$EXEC" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pipeline_executor", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod._account_slug("Acme.Labs"), mod._account_slug("Personal"),
      mod._extra_account_creds("Side Project", "a@b.c").relative_to(mod.GOOGLE_CREDS_ROOT))
print(mod._extra_account_creds("Personal", "x@y.z").parent == mod.GOOGLE_CREDS_DIR_PERSONAL)
PY
)"
have "$SLUGS" "acme-labs personal credentials-side-project/a@b.c.json
True" \
  "8f. credentials live in credentials-<slug>/, and Personal's slug is its existing folder"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

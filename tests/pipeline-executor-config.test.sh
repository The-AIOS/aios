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
  python3 - "$EXEC" "$TMP/USER.md" "$2" <<'PY'
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
MISSING="$(python3 - "$EXEC" "$TMP/absent-USER.md" 2>/dev/null <<'PY'
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

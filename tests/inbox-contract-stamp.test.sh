#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The declared spawn-inbox contract against the number the surfaces really stamp
#
# skills/aios/orchestration-ladder/inbox-contract.json declares the current
# contract, and tests/inbox-contract-number.test.sh keeps CLAUDE.md and the skill
# in step with it. That still leaves the declaration itself hand-typed: if the
# App and Glass move to the next contract, nothing inside this repo changes and
# every local check stays green (#409).
#
# The stamp is written by the surfaces, and their source is not in this repo. So
# this suite READS it, `export const INBOX_CONTRACT = N;`, from the default branch
# of The-AIOS/aios-app and The-AIOS/aios-glass. Where it lives moved once, when
# both surfaces adopted the shared package @the-aios/core, so each surface has a
# list of known places:
#   aios-app    packages/core/src/sendQueue.ts       (the package, in the App repo)
#               src/core/sendQueue.ts                (before the package)
#   aios-glass  src/core/sendQueue.ts                (before the package)
#               package.json "dependencies" pins "@the-aios/core": "<V>" exactly;
#               the stamp is packages/core/src/sendQueue.ts in aios-app at tag
#               core-v<V>, the tag publish-core.yml publishes V from (it refuses a
#               tag that does not match the version). A version published by hand,
#               or a tag moved after the publish, would be read wrongly; nothing is
#               downloaded from npm to compare.
# One place is AUTHORITATIVE per surface and must hold the stamp: for the App the
# package file when it exists, else the old one; for Glass the pinned tag when
# package.json pins the package, else the old file. The other place, when it exists
# and holds a stamp, must agree: a file left behind after the move must not pass for
# what the surface ships. Without a stamp (a re-export) it is ignored.
# A surface never overwrites a README stamped with a higher contract than its own,
# so the number an agent finds on a machine running both is the HIGHER of the
# two — that is what the declaration must equal.
#
# Three outcomes, and they are kept apart on purpose:
#   exit 0   both surfaces were read and the declaration matches
#   exit 1   both were read and it does not match; or a surface was reached and
#            the stamp is in none of its known places, or a file was read and the
#            stamp was not in it. The instrument went stale, which is a verdict
#            too: fix where this suite reads from.
#   exit 75  a surface could not be reached (the network failed, or answered with
#            something other than the file or a clean "not found"). That is NOT a
#            verdict: nothing was compared. INCONCLUSIVE, never a pass.
#
# Reading local checkouts instead of the network:
#   AIOS_APP_SRC=/path/to/aios-app  AIOS_GLASS_SRC=/path/to/aios-glass
#   AIOS_CORE_TAG_BASE=<url or folder holding core-v<V>/packages/core/src/sendQueue.ts>
#   (default: the aios-app repo on raw.githubusercontent.com)
#
# Written for bash 3.2. Needs curl when a surface is read over the network, and
# python3 to read Glass's package.json (without it Glass is reported as not read,
# exit 75) and for the controls that serve fixtures over local HTTP.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SELF="tests/inbox-contract-stamp.test.sh"
PASS=0; FAIL=0; UNREAD=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
unread(){ UNREAD=$((UNREAD+1)); printf '  ????  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

DECL="${AIOS_CONTRACT_DECL:-skills/aios/orchestration-ladder/inbox-contract.json}"
RAW="${AIOS_SURFACE_RAW_BASE:-https://raw.githubusercontent.com/The-AIOS}"
CORE_TAGS="${AIOS_CORE_TAG_BASE:-$RAW/aios-app}"
PKG_REL="packages/core/src/sendQueue.ts"
OLD_REL="src/core/sendQueue.ts"
TMP="$(mktemp -d)"; SERVER=''; trap '[ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null; rm -rf "$TMP"' EXIT

CUR="$([ -f "$DECL" ] && grep -oE '"current" *: *[0-9]+' "$DECL" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/ $//')"
stamp_in(){ grep -oE '^export const INBOX_CONTRACT *= *[0-9]+' "$1" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

# get <url-or-path> <dest> → prints ok, missing (a clean "not found") or unreachable. A redirect
# that lands on another host (a captive portal, a proxy page) is unreachable, not a file.
get(){
  case "$1" in
    http://*|https://*)
      command -v curl >/dev/null 2>&1 || { echo unreachable; return 0; }
      res="$(curl -sSL --max-time 20 --retry 2 -o "$2" -w '%{http_code} %{url_effective}' "$1" 2>/dev/null)" || { echo unreachable; return 0; }
      want="$(printf '%s' "$1" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"; got="$(printf '%s' "${res#* }" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"
      [ "$want" = "$got" ] || { echo unreachable; return 0; }
      case "${res%% *}" in 200) echo ok ;; 404) echo missing ;; *) echo unreachable ;; esac ;;
    *) if [ -f "$1" ]; then cp "$1" "$2" && echo ok || echo unreachable; else echo missing; fi ;;
  esac
}

# pin_of <package.json> → prints the "@the-aios/core" entry of "dependencies", or nothing when
# there is none; fails (exit 2) when the file cannot be read as that, so "unreadable" is never
# mistaken for "not pinned".
pin_of(){
  python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1], encoding="utf-8"))
    deps=d.get("dependencies", {}) if isinstance(d, dict) else None
    if not isinstance(deps, dict): sys.exit(2)
    v=deps.get("@the-aios/core")
    if v is not None and (not isinstance(v, str) or not v): sys.exit(2)
    if v is None:
        # Declared only where npm does not install it for the surface to run: unreadable, not
        # "not pinned", or a file left behind would stand in for the package.
        for k in ("devDependencies", "peerDependencies", "optionalDependencies"):
            o=d.get(k)
            if isinstance(o, dict) and "@the-aios/core" in o: sys.exit(2)
    print(v or "")
except SystemExit: raise
except Exception: sys.exit(2)' "$1" 2>/dev/null
}

# read_surface <repo> <local-dir-or-empty> → sets GOT to a number, or to '' with WHY set to
# "unreachable" (no verdict) or "broken" (reached, and the authoritative place holds no single
# stamp, or the other place disagrees). FROM names what was read, or what was tried.
read_surface(){
  repo="$1"; base="${2:-$RAW/$repo/main}"; GOT=''; WHY=''; FROM=''; HINT=''
  if [ -n "$2" ] && [ ! -d "$2" ]; then FROM="$2 is not a folder"; WHY=unreachable; return 0; fi
  STALE="the file moved or the symbol was renamed: this suite can no longer read the stamp, so teach it the new place"
  # fetch_stamp <url-or-path> → sets ST (ok|missing|unreachable) and V (the single stamp, or '').
  fetch_stamp(){ f="$TMP/$repo.$$.$RANDOM.ts"; ST="$(get "$1" "$f")"; V=''
    [ "$ST" = ok ] || return 0
    V="$(stamp_in "$f")"; case "$V" in *' '*) V='' ;; esac; }
  if [ "$repo" = aios-app ]; then
    fetch_stamp "$base/$PKG_REL"; A_ST="$ST"; A_V="$V"; A="$base/$PKG_REL"
    fetch_stamp "$base/$OLD_REL"; O_ST="$ST"; O_V="$V"; O="$base/$OLD_REL"
    if [ "$A_ST" = unreachable ] || [ "$O_ST" = unreachable ]; then FROM="$base"; WHY=unreachable; return 0; fi
    # The package file, when it exists, is the authority; otherwise the old file is.
    if [ "$A_ST" = missing ]; then A="$O"; A_ST="$O_ST"; A_V="$O_V"; O_ST=missing; fi
    [ "$A_ST" = ok ] || { FROM="$base/{$PKG_REL,$OLD_REL}: not found in either"; HINT="$STALE"; WHY=broken; return 0; }
  else
    O="$base/$OLD_REL"; fetch_stamp "$O"; O_ST="$ST"; O_V="$V"
    [ "$O_ST" = unreachable ] && { FROM="$O"; WHY=unreachable; return 0; }
    pj="$TMP/$repo.json"; PST="$(get "$base/package.json" "$pj")"
    [ "$PST" = unreachable ] && { FROM="$base/package.json"; WHY=unreachable; return 0; }
    pin=''
    if [ "$PST" = ok ]; then
      command -v python3 >/dev/null 2>&1 || { FROM="python3 not found, needed to read $base/package.json"; WHY=unreachable; return 0; }
      pin="$(pin_of "$pj")" || { FROM="$base/package.json: @the-aios/core cannot be read from \"dependencies\" (not JSON, empty, or declared only in dev/peer/optional dependencies)"; HINT="Glass ships what \"dependencies\" pins; read it there, or teach this suite the new place"; WHY=broken; return 0; }
    fi
    if [ -n "$pin" ]; then
      case "$pin" in *[!0-9A-Za-z.-]*) FROM="$base/package.json pins @the-aios/core \"$pin\", not one exact version"; HINT="a range names no single source; this suite reads an exact pin"; WHY=broken; return 0 ;; esac
      if ! printf '%s\n' "$pin" | LC_ALL=C grep -qxE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?'; then
        FROM="$base/package.json pins @the-aios/core \"$pin\", not one exact version"; HINT="a range names no single source; this suite reads an exact pin"; WHY=broken; return 0
      fi
      # Pinned: the tag is the authority.
      A="$CORE_TAGS/core-v$pin/$PKG_REL"; fetch_stamp "$A"; A_ST="$ST"; A_V="$V"
      [ "$A_ST" = unreachable ] && { FROM="$A"; WHY=unreachable; return 0; }
      [ "$A_ST" = ok ] || { FROM="$A: no such tag or file"; HINT="is core-v$pin published from that tag? Glass pins a version the App repo has no tag for"; WHY=broken; return 0; }
    else
      A="$O"; A_ST="$O_ST"; A_V="$O_V"; O_ST=missing
      [ "$A_ST" = ok ] || { FROM="$base/{$OLD_REL,package.json}: no file and no pin"; HINT="$STALE"; WHY=broken; return 0; }
    fi
  fi
  [ -n "$A_V" ] || { FROM="$A: no single INBOX_CONTRACT in it"; HINT="$STALE"; WHY=broken; return 0; }
  if [ "$O_ST" = ok ] && [ -n "$O_V" ] && [ "$O_V" != "$A_V" ]; then
    FROM="$A stamps $A_V and the file left at $O stamps $O_V"; HINT="the surface repo keeps two stamps: remove the leftover there, or make them agree"; WHY=broken; return 0
  fi
  GOT="$A_V"; FROM="$A"
}

echo "── 1. the declaration ──"
case "$CUR" in
  ''|*' '*) no "$DECL does not declare exactly one current contract (read: '${CUR}')"
            printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"; exit 1 ;;
  *)        ok "declared current contract: $CUR" ;;
esac

echo "── 2. what each surface stamps ──"
HIGH=''
for pair in "aios-app:${AIOS_APP_SRC:-}" "aios-glass:${AIOS_GLASS_SRC:-}"; do
  repo="${pair%%:*}"; dir="${pair#*:}"
  read_surface "$repo" "$dir"
  if [ -n "$GOT" ]; then
    ok "$repo stamps contract $GOT ($FROM)"
    { [ -z "$HIGH" ] || [ "$GOT" -gt "$HIGH" ]; } && HIGH="$GOT"
  elif [ "$WHY" = broken ]; then
    no "$repo: the stamp could not be read where this suite knows to look ($FROM)" "$HINT"
  else
    unread "$repo could not be read ($FROM)" "nothing was compared for this surface"
  fi
done

echo "── 3. the declaration equals the higher stamp ──"
if [ "$FAIL" -gt 0 ]; then
  :
elif [ -n "$HIGH" ] && [ "$HIGH" -gt "$CUR" ]; then
  # True whatever the unread surface says: the higher stamp can only be this or more.
  no "a surface stamps contract $HIGH and $DECL declares $CUR" \
     "the documents lag behind the code. Read what contract $HIGH adds, then raise the number in $DECL and in the sentence CLAUDE.md and the skill repeat (tests/inbox-contract-number.test.sh names both)"
elif [ "$UNREAD" -gt 0 ]; then
  :
elif [ "$HIGH" -lt "$CUR" ]; then
  no "$DECL declares contract $CUR and no surface stamps more than $HIGH" \
     "the declaration is the contract IN FORCE, the one an agent finds stamped; a contract only specified here is not current yet"
else
  ok "declared $CUR = stamped $HIGH"
fi

if [ -z "${AIOS_STAMP_CONTROL:-}" ]; then
  echo "── 4. CONTROL — each outcome is reachable, from fixtures, with no network ──"
  # A fixture surface: before the package (src/core), the App after it (packages/core), or Glass after
  # it (package.json pinning a version, with that version's source under a tags folder).
  st_line(){ printf 'export const INBOX_CONTRACT = %s;\n' "$1"; }
  fx_old(){ mkdir -p "$TMP/$1/src/core"; printf '%s\n' "$2" > "$TMP/$1/src/core/sendQueue.ts"; }
  fx_pkg(){ mkdir -p "$TMP/$1/packages/core/src"; printf '%s\n' "$2" > "$TMP/$1/packages/core/src/sendQueue.ts"; }
  fx_pin(){ mkdir -p "$TMP/$1"; printf '{ "dependencies": { "@the-aios/core": "%s" } }\n' "$2" > "$TMP/$1/package.json"; }
  fx_tag(){ mkdir -p "$TMP/tags/core-v$1/packages/core/src"; st_line "$2" > "$TMP/tags/core-v$1/packages/core/src/sendQueue.ts"; }
  run(){ AIOS_STAMP_CONTROL=1 AIOS_CONTRACT_DECL="$DECL" AIOS_APP_SRC="${1:-}" AIOS_GLASS_SRC="${2:-}" \
         AIOS_SURFACE_RAW_BASE="${3:-$RAW}" AIOS_CORE_TAG_BASE="${4:-$TMP/tags}" "$BASH" "$SELF" >/dev/null 2>&1; echo $?; }
  expect(){ want="$1"; label="$2"; why="$3"; shift 3; R="$(run "$@")"
    [ "$R" = "$want" ] && ok "control: $label → $want" || no "control: $label gave exit $R, expected $want" "$why"; }
  fx_old same  "$(st_line "$CUR")"
  fx_old ahead "$(st_line $((CUR+1)))"
  fx_old gone  "export const SOMETHING_ELSE = $CUR;"
  fx_pkg app-pkg "$(st_line "$CUR")"
  fx_pin glass-pin 9.9.1; fx_tag 9.9.1 "$CUR"
  fx_pin glass-pin-ahead 9.9.2; fx_tag 9.9.2 $((CUR+1))
  fx_pin glass-pin-untagged 9.9.3
  fx_pin glass-pin-range '^9.9.1'
  fx_pin glass-pin-loose 9.9
  mkdir -p "$TMP/empty" "$TMP/glass-nodep"; printf '{ "devDependencies": { "@the-aios/core": "9.9.1" } }\n' > "$TMP/glass-nodep/package.json"
  # A file left behind after the move, beside the pin: agreeing passes, disagreeing fails.
  fx_old glass-both-agree "$(st_line "$CUR")"; fx_pin glass-both-agree 9.9.1
  fx_old glass-both-stale "$(st_line "$CUR")"; fx_pin glass-both-stale 9.9.2
  fx_old glass-shim "export { INBOX_CONTRACT } from '@the-aios/core/sendQueue';"; fx_pin glass-shim 9.9.1
  fx_pkg app-both-stale "$(st_line $((CUR+1)))"; fx_old app-both-stale "$(st_line "$CUR")"
  fx_old glass-both-untagged "$(st_line "$CUR")"; fx_pin glass-both-untagged 9.9.3
  # Only the disagreement can fail these: the authority stamps exactly the declared contract.
  fx_old glass-left-behind "$(st_line $((CUR-1)))"; fx_pin glass-left-behind 9.9.1
  fx_pkg app-left-behind "$(st_line "$CUR")"; fx_old app-left-behind "$(st_line $((CUR-1)))"
  fx_pkg app-shim "export * from './queue';"; fx_old app-shim "$(st_line "$CUR")"
  fx_old glass-badjson "$(st_line "$CUR")"; printf '{ "dependencies": [ \n' > "$TMP/glass-badjson/package.json"
  fx_old glass-devdep-left "$(st_line "$CUR")"; printf '{ "devDependencies": { "@the-aios/core": "9.9.2" } }\n' > "$TMP/glass-devdep-left/package.json"
  DEAD="http://127.0.0.1:9"   # the discard port: refused at once, no network involved
  expect 0  "both surfaces before the package, on $CUR" "the old layout no longer reads" "$TMP/same" "$TMP/same"
  expect 0  "App after the package, Glass before" "the App's package path is not read" "$TMP/app-pkg" "$TMP/same"
  expect 0  "App before, Glass after (pinned version, read at its tag)" "Glass's pin is not followed to its tag" "$TMP/same" "$TMP/glass-pin"
  expect 0  "both after the package" "the after layouts do not read together" "$TMP/app-pkg" "$TMP/glass-pin"
  expect 1  "one surface on $((CUR+1))" "this suite cannot see the drift it exists for" "$TMP/same" "$TMP/ahead"
  expect 1  "Glass's pinned version stamps $((CUR+1))" "a newer package pinned by Glass goes unseen" "$TMP/app-pkg" "$TMP/glass-pin-ahead"
  expect 1  "stamp missing from a file that was read" "an unreadable stamp must not pass" "$TMP/same" "$TMP/gone"
  expect 1  "the App reached with the stamp in no known place" "a moved file must be RED: the suite went stale" "$TMP/empty" "$TMP/same"
  expect 1  "Glass with no src/core and @the-aios/core only in devDependencies" "a moved file must be RED: the suite went stale" "$TMP/same" "$TMP/glass-nodep"
  expect 0  "Glass keeps the old file beside the pin, both on $CUR" "a leftover that agrees must not fail" "$TMP/same" "$TMP/glass-both-agree"
  expect 1  "Glass keeps the old file on $CUR while its pin stamps $((CUR+1))" "a leftover must not pass for what Glass ships" "$TMP/same" "$TMP/glass-both-stale"
  expect 0  "Glass's old file is a re-export, the pin holds the stamp" "a place without a stamp is skipped when another holds one" "$TMP/same" "$TMP/glass-shim"
  expect 1  "Glass keeps the old file on $CUR and pins a version with no tag" "a leftover must not stand in for a pin that cannot be read" "$TMP/same" "$TMP/glass-both-untagged"
  expect 75 "Glass keeps the old file and the pinned tag cannot be reached" "a fetch that failed must not leave an earlier stamp standing" "$TMP/same" "$TMP/glass-both-agree" "$RAW" "http://127.0.0.1:9"
  expect 1  "the App's package file holds no stamp, a stale old file does" "the package file is the authority when it exists" "$TMP/app-shim" "$TMP/same"
  expect 1  "Glass's package.json cannot be read as JSON, beside a leftover" "unreadable must not read as not pinned" "$TMP/same" "$TMP/glass-badjson"
  expect 1  "Glass declares the package only in devDependencies, beside a leftover" "a leftover must not stand in for a package declared elsewhere" "$TMP/same" "$TMP/glass-devdep-left"
  expect 75 "a local surface folder that does not exist" "a mistyped folder is not a moved file" "$TMP/no-such-folder" "$TMP/same"
  expect 1  "the App's package and old file disagree" "two stamps in one surface must fail" "$TMP/app-both-stale" "$TMP/same"
  expect 1  "Glass's pin stamps $CUR and a file left behind stamps $((CUR-1))" "a disagreeing leftover fails even when the authority matches" "$TMP/same" "$TMP/glass-left-behind"
  expect 1  "the App's package stamps $CUR and a file left behind stamps $((CUR-1))" "a disagreeing leftover fails even when the authority matches" "$TMP/app-left-behind" "$TMP/same"
  expect 1  "Glass pins 9.9, which npm reads as a range" "a range names no single source" "$TMP/same" "$TMP/glass-pin-loose"
  expect 75 "Glass's pinned tag cannot be reached" "a tag that did not answer is not a verdict" "$TMP/same" "$TMP/glass-pin" "$RAW" "http://127.0.0.1:9"
  expect 1  "Glass pins a version with no core-v tag" "an unpublished pin must be RED, not skipped" "$TMP/same" "$TMP/glass-pin-untagged"
  expect 1  "Glass pins a range, not a version" "a range names no single source" "$TMP/same" "$TMP/glass-pin-range"
  expect 75 "one surface unreachable" "a check that did not run must not read as green" "$TMP/same" "" "$DEAD"
  expect 1  "one ahead, the other unreachable" "the higher stamp is known whatever the other says" "$TMP/ahead" "" "$DEAD"
  # Over HTTP: a clean 404 everywhere is RED, the network failing is 75. Fixtures served from a
  # local port, laid out as raw.githubusercontent.com lays out <repo>/<ref>/<path>.
  if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    W="$TMP/www"; mkdir -p "$W/aios-app/main/packages/core/src" "$W/aios-glass/main" "$W/aios-app/core-v9.9.1/packages/core/src"
    st_line "$CUR" > "$W/aios-app/main/packages/core/src/sendQueue.ts"
    st_line "$CUR" > "$W/aios-app/core-v9.9.1/packages/core/src/sendQueue.ts"
    printf '{ "dependencies": { "@the-aios/core": "9.9.1" } }\n' > "$W/aios-glass/main/package.json"
    PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
    (cd "$W" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) & SERVER=$!
    disown "$SERVER" 2>/dev/null || true   # killed by the EXIT trap; no job notice when it goes
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.25; done
    H="http://127.0.0.1:$PORT"
    expect 0 "over HTTP, both after the package" "the network path does not read the after layouts" "" "" "$H" "$H/aios-app"
    rm "$W/aios-app/main/packages/core/src/sendQueue.ts"
    expect 1 "over HTTP, the App answers 404 in every known place" "a clean not-found must be RED, never inconclusive" "" "" "$H" "$H/aios-app"
    st_line "$CUR" > "$W/aios-app/main/packages/core/src/sendQueue.ts"; rm "$W/aios-glass/main/package.json"
    expect 1 "over HTTP, Glass answers 404 for src/core and package.json" "a clean not-found must be RED, never inconclusive" "" "" "$H" "$H/aios-app"
  else
    printf '  SKIP  control over HTTP: needs python3 and curl\n'
  fi
fi

printf '\n%d passed · %d failed · %d not read\n' "$PASS" "$FAIL" "$UNREAD"
[ "$FAIL" -eq 0 ] || exit 1
if [ "$UNREAD" -gt 0 ]; then
  echo "INCONCLUSIVE: a surface could not be read, so the declared contract was NOT checked against it."
  exit 75
fi
exit 0

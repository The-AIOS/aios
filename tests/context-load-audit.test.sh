#!/usr/bin/env bash

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

# ─────────────────────────────────────────────────────────────────────────────
# hooks/context-load-audit.py — the instrument behind /aios:housekeeping's
# Bucket 30, tested against synthetic transcripts with known answers
#
# This exists because the FIRST version of this measurement was wrong, and wrong
# in the direction that gets trusted: it matched only `context/…/<file>.md`, so
# it missed every worker that did `cd <context dir> && grep '^### ' patterns.md`
# -- which is what workers actually do. It reported three workers at zero that
# had read the entire floor, and the clean number was believed.
#
# So the refusal cases come first (antifragile #110): the cd-relative read, and
# the control that must abort rather than reassure. A detector that cannot fail
# reports "all clear" just as convincingly when it is broken.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/context-load-audit.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HOME_FAKE="$TMP/home"; mkdir -p "$HOME_FAKE/.claude/projects/proj"
# A fixture VAULT, so the DERIVED filename list has a source. The detector no longer
# ships a hand-written list (the first one named four files from a single operator's
# vault -- a canonical leak that also matched nothing anywhere else), so bare-filename
# reads after a `cd` can only be resolved from the vault in front of it.
FAKE_VAULT="$TMP/vaultroot"
mkdir -p "$FAKE_VAULT/vault/00 - notes/context/declared" \
         "$FAKE_VAULT/vault/00 - notes/context/observed"
for n in about_me personal_voice working_style; do
  printf '# %s\n' "$n" > "$FAKE_VAULT/vault/00 - notes/context/declared/$n.md"
done
for n in antifragile patterns preferences growth; do
  printf '# %s\n' "$n" > "$FAKE_VAULT/vault/00 - notes/context/observed/$n.md"
done
export AIOS_VAULT="$FAKE_VAULT"
# Primaries are DECLARED, in USER.md's Identity table -- the same table that decides how a
# session is greeted. The italic rows are the template's examples and must never count.
cat > "$FAKE_VAULT/USER.md" <<'USEREOF'
# USER

## Identity

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

| Name | Role | Greeting style |
|------|------|----------------|
| *`buddy`* | *My main session* | *Warm co-pilot* |
| `main-seat` | Main session | Brief |

## Settings

| `not-a-primary` | a table in another section | - |
USEREOF

# Build a transcript: agent name + N tool_use events with the given commands.
mk(){ # $1 name · $2 sid · $3.. commands
  local name="$1" sid="$2"; shift 2
  local f="$HOME_FAKE/.claude/projects/proj/$sid.jsonl"
  printf '{"type":"agent-name","agentName":"%s","sessionId":"%s"}\n' "$name" "$sid" > "$f"
  local i=0
  for cmd in "$@"; do
    i=$((i+1))
    $PYBIN - "$f" "$cmd" <<'PY'
import json, sys
f, cmd = sys.argv[1], sys.argv[2]
rec = {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":cmd}}]}}
open(f,"a").write(json.dumps(rec)+"\n")
PY
  done
  # pad to clear the --min-tools threshold
  while [ "$i" -lt 25 ]; do
    i=$((i+1))
    $PYBIN - "$f" <<'PY'
import json, sys
rec={"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}}
open(sys.argv[1],"a").write(json.dumps(rec)+"\n")
PY
  done
}
# NOTE: USERPROFILE is set alongside HOME on purpose. On Windows, Python's
# `Path.home()` / `expanduser('~')` read USERPROFILE and IGNORE HOME, so a test
# that isolates a Python hook with HOME alone does not isolate it at all — it
# silently reads the operator's REAL ~/.claude. That is worse than a failing
# test: it can pass or fail for reasons having nothing to do with the fixture.
# Harmless on macOS/Linux, where USERPROFILE is unused.
run(){ HOME="$HOME_FAKE" USERPROFILE="$HOME_FAKE" AIOS_VAULT="$FAKE_VAULT" $PYBIN "$H" "$@" 2>&1; }

echo "── 1. REFUSAL: a cd-relative read must be COUNTED (the original bug) ──"
mk worker-cd cd000001 \
  'cd "/Users/x/aios/vault/00 - notes/context/observed" && for f in antifragile preferences patterns growth; do grep "^### " "$f.md"; done'
OUT="$(run --session cd000001 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
[ "$N" = 4 ] && ok "cd-then-bare-filename counts all 4 floor files" \
  || no "cd-relative read scored $N, expected 4" "this is the exact miss that reported live workers as zero"
T=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(len(json.load(sys.stdin)[0]["titles_only"]))' 2>/dev/null || echo -1)
[ "$T" = 4 ] && ok "and is classified titles-only, not a full read" \
  || no "depth misclassified: titles_only=$T" "a floor degrading to nothing must not look like a full load"

echo "── 2. a full-path read is counted, and as a FULL read ──"
mk worker-path fu000002 \
  'cat "/Users/x/aios/vault/00 - notes/context/declared/personal_voice.md"' \
  'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
OUT="$(run --session fu000002 --min-tools 0 --json)"
F=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(len(json.load(sys.stdin)[0]["full"]))' 2>/dev/null || echo -1)
[ "$F" = 2 ] && ok "full-path reads counted as full (2)" || no "full-path read scored $F, expected 2"

echo "── 3. REFUSAL: prose mentioning a path is NOT a read ──"
# A transcript quotes context paths constantly. Only a tool call is evidence.
f="$HOME_FAKE/.claude/projects/proj/pr000003.jsonl"
printf '{"type":"agent-name","agentName":"worker-prose","sessionId":"pr000003"}\n' > "$f"
$PYBIN - "$f" <<'PY'
import json, sys
p = sys.argv[1]
# assistant TEXT and a tool_result both mention the path; neither is a tool_use
open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":"I should read context/observed/patterns.md next"}]}})+"\n")
open(p,"a").write(json.dumps({"type":"user","message":{"content":[{"type":"tool_result","content":"context/observed/antifragile.md"}]}})+"\n")
for _ in range(25):
    open(p,"a").write(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo filler"}}]}})+"\n")
PY
OUT="$(run --session pr000003 --min-tools 0 --json)"
N=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(json.load(sys.stdin)[0]["total"])' 2>/dev/null || echo -1)
[ "$N" = 0 ] && ok "prose and tool_result do not count as reads" \
  || no "scored $N from text alone" "mentioning a path is not opening it"

echo "── 4. CONTROL: with no scoring primary, it must ABORT, not reassure ──"
mk worker-zero ze000004 'echo "did no context reading at all"'
OUT="$(run --min-tools 0)"; RC=$?
if printf '%s' "$OUT" | grep -q 'ABORT'; then
  ok "no primary scored → aborts instead of reporting a clean number"
else
  no "reported worker numbers with no working control" "$(printf '%s' "$OUT" | head -3)"
fi

echo "── 5. with a scoring primary, it reports and flags the zero ──"
mk main-seat pr000005 'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
OUT="$(run --min-tools 0)"
printf '%s' "$OUT" | grep -q 'control — primary sessions: 1/1' \
  && ok "primary recognised as the control" || no "primary not detected" "$(printf '%s' "$OUT" | head -2)"
printf '%s' "$OUT" | grep -q 'worker-zero' \
  && ok "the zero-context worker is named" || no "a worker at zero was not surfaced"

echo "── 6. the detector knows what CORRECT looks like under the rule it audits ──"
# A worker that runs the one-call floor has loaded the whole floor. Matching only file
# PATHS scores that worker at zero -- reporting correct behaviour as the WORST possible
# behaviour, so an after-vs-before comparison would show the new wiring as a regression.
grep -q 'context-floor' "$H" \
  && ok "the audit recognises the one-call floor command" \
  || no "a worker running context-floor.py would score ZERO" \
        "correct behaviour would be reported as the worst behaviour"
if grep -qE 'thinker-collaborations|coding-practices|psychometric-profile' "$H"; then
  no "the audit hardcodes personal context filenames" \
     "a canonical leak, and a list that matches nothing in another vault"
else
  ok "no hardcoded or personal context filenames in the detector"
fi
grep -q '_context_names' "$H" \
  && ok "context filenames are derived from the vault at runtime" \
  || no "filenames are not derived" "both folders vary per vault; a fixed list goes stale silently"

echo "── 7. FIT is measured, not just volume ──"
# "Was the answer good" is subjective. "Did a worker that published in the operator's name
# ever read the file that says how they write" is a fact on the transcript -- and it is the
# failure that does NOT announce itself, since the output reads fluent either way. That
# makes reinforced learning checkable rather than a matter of taste.
grep -q 'OUTWARD' "$H" \
  && ok "the audit detects outward-facing actions" \
  || no "no notion of outward-facing work" "then fit cannot be measured, only volume"
grep -q 'DECLARED_NAMES' "$H" \
  && ok "it tracks which declared/ files a worker read" \
  || no "declared reads are not separated" "the voice-without-voice-context case is invisible"
if grep -qE 'outward.*declared|declared.*outward' "$H"; then
  ok "it cross-references the two into a fit finding"
else
  no "outward actions and declared reads are never compared" \
     "each alone is a count; the FINDING is the pair"
fi
# And the declared list must be derived, like everything else here.
grep -q '_declared_names' "$H" \
  && ok "declared filenames are derived from the vault" \
  || no "declared names are hardcoded" "that list is empty on any vault that renamed them"

echo "── 8. primaries come from USER.md, never from names written in the hook ──"
mk buddy ex000008 'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
mk not-a-primary np000008 'echo x'
OUT="$(run --min-tools 0 --json)"
P=$(printf '%s' "$OUT" | $PYBIN -c 'import json,sys; print(",".join(sorted(r["name"] for r in json.load(sys.stdin) if r["primary"])))' 2>/dev/null)
[ "$P" = "main-seat" ] && ok "only the declared row is a primary (example row and other sections ignored)" \
  || no "primaries were [$P], expected [main-seat]" "an example row or a table from another section was read as an identity"
OUT="$(run --min-tools 0 --json --primary worker-zero)"
printf '%s' "$OUT" | $PYBIN -c 'import json,sys; sys.exit(0 if [r for r in json.load(sys.stdin) if r["name"]=="worker-zero" and r["primary"]] else 1)' \
  && ok "--primary adds a name" || no "--primary was ignored"
if grep -qiE 'buddai|sarah|vault-sync' "$H"; then
  no "the hook names another operator's sessions" "canonical ships to every vault; those names match nothing there"
else
  ok "no session names are written into the hook"
fi
NV="$TMP/nouser"; mkdir -p "$NV/vault/00 - notes/context/declared" "$NV/vault/00 - notes/context/observed"
OUT="$(HOME="$HOME_FAKE" USERPROFILE="$HOME_FAKE" AIOS_VAULT="$NV" $PYBIN "$H" --min-tools 0 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'Identity' && printf '%s' "$OUT" | grep -q -- '--primary'; } \
  && ok "no USER.md → aborts and says how to declare a primary" || no "no-USER.md run did not explain itself (rc=$RC)" "$OUT"

echo "── 9. FIT reads the whole transcript and respects order ──"
# Built in one process: a worker's calls in order, "filler*N" expands to N no-op calls.
mkseq(){ # $1 name · $2 sid · $3.. steps
  local f="$HOME_FAKE/.claude/projects/proj/$2.jsonl" name="$1"; shift 2
  $PYBIN - "$f" "$name" "$@" <<'PY'
import json, sys
f, name, steps = sys.argv[1], sys.argv[2], sys.argv[3:]
dump = lambda o: json.dumps(o, separators=(",", ":"))   # compact, as real transcripts are
sid = f.rsplit("/", 1)[-1][:-6]
out = [dump({"type": "agent-name", "agentName": name, "sessionId": sid})]
for s in steps:
    cmds = ["echo filler"] * int(s[7:]) if s.startswith("filler*") else [s]
    for c in cmds:
        out.append(dump({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": c}}]}}))
open(f, "w").write("\n".join(out) + "\n")
PY
}
VOICE='cat "/Users/x/aios/vault/00 - notes/context/declared/personal_voice.md"'
SHIP='cp draft.md "/Users/x/aios/vault/03 - export/post.md"'
mkseq fit-late-ship  fl000009 'filler*130' "$SHIP"
mkseq fit-read-after fa000009 "$SHIP" "$VOICE" 'filler*30'
mkseq fit-late-good  fg000009 'filler*130' "$VOICE" "$SHIP"
# One call that acts and reads: credited only when the read comes first in the call.
mkseq fit-same-ship-first ss000009 "$SHIP && $VOICE" 'filler*30'
mkseq fit-same-read-first sr000009 "$VOICE && $SHIP" 'filler*30'
# The declared name also appears earlier inside another word; that is not the read.
mkseq fit-same-lookalike sl000009 "echo backup_personal_voice.md && $SHIP && $VOICE" 'filler*30'
fit(){ # $1 hook · prints the names flagged by the fit section
  HOME="$HOME_FAKE" USERPROFILE="$HOME_FAKE" AIOS_VAULT="$FAKE_VAULT" $PYBIN "$1" --min-tools 0 2>&1 \
    | sed -n '/^fit/,$p' | grep -oE 'fit-[a-z-]+' | sort | tr '\n' ' '
}
NEWF="$(fit "$H")"
[ "$NEWF" = "fit-late-ship fit-read-after fit-same-lookalike fit-same-ship-first " ] \
  && ok "flags a ship past the loading cap, a ship before the read, and a ship-then-read in one call" \
  || no "fit flagged [$NEWF], expected [fit-late-ship fit-read-after fit-same-lookalike fit-same-ship-first]" "a read before a ship must pass, in one call or two; the others must not"

# The same fixture against the pre-change hook, pinned by sha so the reproduction does not
# move when this change lands. Skipped, with a message, when that commit is not present.
PIN=3d135ded112bf7b77156b61bb29e6233ff7c7285
OLD="$TMP/old-audit.py"
if git cat-file -e "$PIN:$H" 2>/dev/null && git show "$PIN:$H" > "$OLD" && ! cmp -s "$OLD" "$H"; then
  # The old hook recognised its primaries by hardcoded name; give it one so it reports.
  mk buddai ob000009 'cat "/Users/x/aios/vault/00 - notes/context/observed/patterns.md"'
  OLDOUT="$(HOME="$HOME_FAKE" USERPROFILE="$HOME_FAKE" AIOS_VAULT="$FAKE_VAULT" $PYBIN "$OLD" --min-tools 0 2>&1)"
  OLDF="$(fit "$OLD")"
  rm -f "$HOME_FAKE/.claude/projects/proj/ob000009.jsonl"
  # The old run must be a VALID report -- a scoring control and a fit section -- before an
  # empty flag list means anything. An aborted or crashed run also flags nothing.
  { printf '%s' "$OLDOUT" | grep -q 'control — primary sessions: [1-9]' \
    && printf '%s' "$OLDOUT" | grep -q '^fit — workers whose output went outward: [1-9]' \
    && [ "$OLDF" = "" ]; } \
    && ok "OLD: neither case was flagged (the cap hid the late ship, order was ignored)" \
    || no "old hook flagged [$OLDF]; the reproduction no longer holds" "check the pin"
else
  echo "  SKIP  old-hook reproduction: $PIN not present or identical"
fi

echo "── 10. --min-tools still filters on the loading window ──"
mkseq window-short ws000010 'filler*30'
N2=$(run --cap 10 --min-tools 20 --json | $PYBIN -c 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r["name"]=="window-short"))' 2>/dev/null)
T=$(run --session ws000010 --cap 10 --min-tools 0 --json | $PYBIN -c 'import json,sys; r=json.load(sys.stdin)[0]; print(r["tools"], r["tools_total"])' 2>/dev/null)
{ [ "$N2" = 0 ] && [ "$T" = "10 30" ]; } \
  && ok "a 30-call session with --cap 10 is below --min-tools 20 (tools=10, tools_total=30)" \
  || no "the loading window no longer drives --min-tools (swept=$N2, tools/total=$T)" "reading the whole transcript for fit must not change which sessions are audited"

echo "── 11. the Identity table parser: real tables in, everything else out ──"
PT="$TMP/parse"; mkdir -p "$PT"
$PYBIN - "$H" "$PT" <<'PY'
import importlib.util, os, sys
hook, d = sys.argv[1], sys.argv[2]
os.environ["AIOS_VAULT"] = d
spec = importlib.util.spec_from_file_location("audit", hook)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
T = "| Name | Role |\n|---|---|\n"          # header + delimiter: what makes it a table
cases = {
    "no outer pipes":   ("## Identity\n\nName | Role\n--- | ---\n`bare-seat` | main\n", {"bare-seat"}),
    "bold is a name":   ("## Identity\n\n" + T + "| **bold-seat** | main |\n", {"bold-seat"}),
    "italic example":   ("## Identity\n\n" + T + "| *`ex`* | x |\n| _ex2_ | x |\n| `real` | y |\n", {"real"}),
    "header not a name": ("## Identity\n\n| Session | Role |\n|---|---|\n| `a` | x |\n", {"a"}),
    "h1 ends section":  ("## Identity\n\nnone yet\n\n# Settings\n\n" + T + "| `b` | y |\n", set()),
    "h3 does not end":  ("## Identity\n\n### Mine\n\n" + T + "| `a` | x |\n", {"a"}),
    "only first table": ("## Identity\n\n" + T + "| `a` | x |\n\n## Contacts\n\n" + T + "| `bob` | y |\n", {"a"}),
    "code block":       ("## Identity\n\n```\n" + T + "| `fenced` | x |\n```\n" + T + "| `a` | x |\n", {"a"}),
    "mixed fences":     ("## Identity\n\n````\n~~~\n" + T + "| `ghost` | x |\n```\n" + T + "| `ghost2` | x |\n````\n" + T + "| `a` | x |\n", {"a"}),
    "not a fence (inline code)": ("```example`text\n\n## Identity\n\n" + T + "| `a` | x |\n", {"a"}),
    "not a fence (indented)":    ("    ```\n\n## Identity\n\n" + T + "| `a` | x |\n", {"a"}),
    "indented heading":  ("  ## Identity\n\n" + T + "| `a` | x |\n", {"a"}),
    "closing hashes":    ("## Identity ##\n\n" + T + "| `a` | x |\n", {"a"}),
    "setext heading":    ("## Identity\n\n| Name | Role |\n| --- | --- |\n| Ana | Owner |\n\nContacts\n--------\n\n| Name | Role |\n| --- | --- |\n| Bruno | Accountant |\n", {"Ana"}),
    "pipe in the intro": ("## Identity\n> Fill in the columns Name | Role.\n\n| Name | Role |\n| --- | --- |\n| Ana | Owner |\n", {"Ana"}),
    "pipe in plain text": ("## Identity\nColumns: Name | Role\n\n" + T + "| `a` | x |\n", {"a"}),
    "quote after table": ("## Identity\n\n" + T + "| `a` | x |\n> tip: a | b\n", {"a"}),
    "heading glued to table": ("## Identity\n\n" + T + "| Ana | Owner |\n## Contacts | Work\n" + T + "| Bruno | Accountant |\n", {"Ana"}),
    "unclosed fence":   ("## Identity\n\n" + T + "| `a` | x |\n\n```\n" + T + "| `ghost` | x |\n", {"a"}),
}
bad = []
for label, (text, want) in cases.items():
    open(os.path.join(d, "USER.md"), "w").write("# USER\n\n" + text)
    got = m._primary_names(d)
    if got != want:
        bad.append("%s: got %s want %s" % (label, sorted(got), sorted(want)))
if bad:
    print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "outer pipes optional, bold kept, italic skipped, # ends the section, code blocks ignored" \
             || no "the Identity parser misread a table" "see above"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

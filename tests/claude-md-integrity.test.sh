#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# CLAUDE.md integrity — the two things a condensation can silently break
#
# CLAUDE.md is Tier-1 and syncs to every operator. Other docs point INTO it with
# "§ <section>" references, and its rules carry backticked literals (flags, paths,
# verbs, file names) that sessions copy verbatim. A rewrite that drops a heading
# breaks every inbound "§" link — and a dead § reads as prose, so nobody notices.
# A rewrite that drops a literal removes the exact string a session needed.
#
#   1. Every "§ …" reference in the repo's docs that names a CLAUDE.md section
#      must resolve to a live heading (roman-numeral shorthand allowed: "§ VI").
#   2. Every literal listed in tests/fixtures/claude-md-literals.txt must still
#      appear, backticked, in CLAUDE.md. The manifest is edited DELIBERATELY when
#      a literal is retired — that edit is the review surface, not an accident.
#
# WHAT THIS CANNOT PROTECT, stated so a green run is not over-read: the manifest pins
# LITERALS, so it guards paths, flags, verbs and JSON shapes — never the one-clause
# *why* beside them. Measured: 279 bytes of pure reason-clause removed from the section,
# zero literals touched, both checks green. The reasoning is guarded by the task-shaped
# rubric a condensation PR runs (see #93 / #98), which needs credentials and cannot live
# in CI. So for each further section: green here means no literal was dropped, NOT that
# nothing was lost. Run the rubric per section; this suite is the floor, not the ceiling.
#
# Both halves run anywhere (no claude binary, no credentials). Written for bash 3.2.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

echo "-- 1. every inbound '§ …' reference resolves to a CLAUDE.md heading --"
python3 - <<'PY'
import re, sys, os, glob, subprocess
ROMAN = re.compile(r'^(?:[ivx]+)\b\.?\s*', re.I)
def norm(s):
    s = s.strip().lower()
    s = re.sub(r'[*_`"“”]', '', s)
    s = re.sub(r'\s+', ' ', s)
    return s
heads = []
for line in open('CLAUDE.md', encoding='utf-8'):
    m = re.match(r'^#{2,3}\s+(.+?)\s*$', line)
    if m:
        h = norm(m.group(1))
        heads.append(h)
        stripped = ROMAN.sub('', h)
        if stripped != h: heads.append(stripped)
        rm = re.match(r'^([ivx]+)\.', h)
        if rm: heads.append(rm.group(1))           # bare numeral: "vi"
        # also the part before an em-dash / colon (long headings get cited short)
        for sep in (' — ', ' – ', ': '):
            if sep in stripped: heads.append(stripped.split(sep)[0].strip())
heads = set(heads)
def _match(cand):
    cand = cand.rstrip('.,;:)]|·→—–"')
    if not cand: return False
    if re.fullmatch(r'[ivx]+', cand): return cand in heads          # bare numeral: "v", "vi"
    if len(cand) < 3: return False
    for h in heads:
        if cand == h or h.startswith(cand) or (len(h) >= 3 and cand.startswith(h)):
            return True
    return False
def resolves(ref):
    raw = re.sub(r'^[\s→"“”\'*:]+', '', ref.strip())
    words = norm(raw).split(' ')
    m = re.match(r'^([ivx]+)\.?$', words[0]) if words else None
    if m:
        # "§ VI" / "§ V. Vault Commands" / "§ VI holds the always-on …" — the numeral must exist;
        # if a Capitalised phrase follows (a section name, not prose), that phrase must resolve
        # too, so a renamed sub-section is caught rather than hidden behind the numeral.
        if m.group(1) not in heads: return False
        rest_raw = re.sub(r'^[ivxIVX]+\.?\s*', '', raw)
        rest_raw = re.sub(r'^[\s→"“”\'*:]+', '', rest_raw)
        if rest_raw and rest_raw[0].isupper():
            rw = norm(rest_raw).split(' ')
            return any(_match(' '.join(rw[:n])) for n in range(min(6, len(rw)), 0, -1))
        return True
    return any(_match(' '.join(words[:n])) for n in range(min(6, len(words)), 0, -1))
files = [f for f in subprocess.run(['git','ls-files','*.md','*.py'],capture_output=True,text=True).stdout.split('\n')
         if f and not f.startswith('vault/') and not f.startswith('tests/') and f != 'CHANGELOG.md']
bad = []; total = 0
pat = re.compile(r'CLAUDE\.md[^§\n]{0,25}§\s*([^\n]{2,80})|§\s*(Spawning Sessions|Session (?:Start|End)|Discipline|Identity & Greeting|Observed Context Rules|File Placement Router|Wiki-Linking|MCP Policy[^\n]{0,30}|Context Hierarchy|Comprehension debt|Ship-time truth-flip[^\n]{0,30}|Proactive Execution|Mandatory First Action|Project Focus Protocol|Index Maintenance|Git & Commit Conventions|Live daily[^\n]{0,20}|Clickable file paths|Deliverables land standalone|Match the literal signal|Time estimates|Anti-values|Growth Mindset|Agentic Culture|The Belief|Structure|Documentation map|Vault Commands|Personalization|Hooks · Skills · Plugins|Project naming convention|Project Note Hygiene|[IVX]{1,4}\.?(?:\s|$)[^\n]{0,30})')
for f in files:
    try: txt = open(f, encoding='utf-8').read()
    except Exception: continue
    for i, line in enumerate(txt.split('\n'), 1):
        for m in pat.finditer(line):
            ref = m.group(1) or m.group(2)
            if not ref: continue
            total += 1
            if not resolves(ref): bad.append((f, i, ref.strip()[:70]))
print(f"     scanned {total} references in {len(files)} files")
for f, i, r in bad: print(f"     UNRESOLVED {f}:{i}: § {r}")
sys.exit(1 if bad else 0)
PY
rc=$?
[ "$rc" = "0" ] && ok "every inbound § reference resolves" || no "unresolved § references (listed above)" "a dead § reads as prose — nobody notices it broke"

echo "-- 2. every pinned literal still appears, backticked, in CLAUDE.md --"
M=tests/fixtures/claude-md-literals.txt
[ -s "$M" ] || { no "manifest $M is empty or missing" "an empty manifest would pass vacuously"; echo; echo "-- $PASS passed, $FAIL failed --"; exit 1; }
missing=0; n=0
while IFS= read -r lit; do
  [ -n "$lit" ] || continue; n=$((n+1))
  grep -qF -- "\`${lit}\`" CLAUDE.md || { missing=$((missing+1)); printf '     MISSING `%s`\n' "$lit"; }
done < "$M"
[ "$missing" = "0" ] && ok "all $n pinned literals present" || no "$missing of $n pinned literals missing from CLAUDE.md" "retire a literal by editing $M in the same PR — never by letting it vanish"

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]

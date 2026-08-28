#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# connector.json — the manifest contract (AI-122, Front A · C1-C5)
#
# The AIOS App reads mcps/*/connector.json to build its Connectors card and ships
# NO copy of any register command. That is the whole contract: mcps/ is the single
# source, the App is a reader. It makes these manifests load-bearing in a way the
# usual "docs drift a bit" tolerance does not cover — a malformed or missing
# manifest does not degrade the card, it removes a connector from existence.
#
# So the failure modes worth asserting are the ones that are SILENT:
#   - a literal ~/aios in a path. That is a symlink on some machines, so the
#     documented command differs from the working one — and it is invisible on
#     every machine where the clone and the symlink agree, which is most of them.
#   - an `id` that does not match the registered server name: a reader cannot pair
#     manifest to registration, so a connected service reads as unconnected.
#   - "MCP" in an operator-facing string: the word the whole change removes.
#   - a folder with no server pretending it has one: the App would write a
#     registration that fails at first use, which is the failure class AI-122 exists
#     to remove rather than relocate.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

echo "── 1. every bundled MCP folder carries a manifest ──"
missing=""
for d in mcps/*-mcp/; do
  [ -d "$d" ] || continue
  [ -f "${d}connector.json" ] || missing="$missing $(basename "$d")"
done
[ -z "$missing" ] && ok "all bundled folders have connector.json" \
  || no "folders without a manifest:$missing" "the App does not list a connector whose manifest is absent — it vanishes silently"

echo "── 2. the contract's own acceptance criteria ──"
python3 - <<'PY'
import json, glob, os, re, sys
bad = []
for f in sorted(glob.glob("mcps/*-mcp/connector.json")):
    folder = os.path.basename(os.path.dirname(f))
    want_id = folder[:-4]
    try:
        d = json.load(open(f))
    except Exception as e:
        bad.append(f"{folder}: unparseable JSON ({e})"); continue
    blob = json.dumps(d)
    if d.get("id") != want_id:
        bad.append(f"{folder}: id {d.get('id')!r} must equal the registered server name {want_id!r}")
    if re.search(r'\bMCPs?\b', str(d.get("service", "")), re.I):
        bad.append(f"{folder}: service names the protocol: {d.get('service')!r}")
    for m in re.findall(r'~/aios[^\"]*', blob):
        bad.append(f"{folder}: literal ~/aios ({m[:50]}) — use {{framework}}")
    if d.get("connect") not in ("one-click", "needs-key", "guided"):
        bad.append(f"{folder}: connect={d.get('connect')!r} is not one of the three modes")
    for k in ("service", "value", "docs"):
        if not d.get(k): bad.append(f"{folder}: missing {k}")
    docs = d.get("docs")
    if docs and not os.path.isfile(os.path.join(os.path.dirname(f), docs)):
        bad.append(f"{folder}: docs points at {docs}, which does not exist")
    if d.get("registers", True):
        if not d.get("register", {}).get("command"):
            bad.append(f"{folder}: registers is true but there is no register.command")
    else:
        if not d.get("_note") and not d.get("delivery"):
            bad.append(f"{folder}: registers:false must say how capability is delivered instead")
for b in bad: print("  FAIL  " + b)
pass
PY
n=$(python3 - <<'PY'
import json,glob,os,re
c=0
for f in sorted(glob.glob("mcps/*-mcp/connector.json")):
    folder=os.path.basename(os.path.dirname(f))
    try: d=json.load(open(f))
    except Exception: c+=1; continue
    blob=json.dumps(d)
    if d.get("id")!=folder[:-4]: c+=1
    if re.search(r'\bMCPs?\b',str(d.get("service","")),re.I): c+=1
    c+=len(re.findall(r'~/aios[^"]*',blob))
    if d.get("connect") not in ("one-click","needs-key","guided"): c+=1
    for k in ("service","value","docs"):
        if not d.get(k): c+=1
    docs=d.get("docs")
    if docs and not os.path.isfile(os.path.join(os.path.dirname(f),docs)): c+=1
    if d.get("registers",True):
        if not d.get("register",{}).get("command"): c+=1
    elif not d.get("_note") and not d.get("delivery"): c+=1
print(c)
PY
)
[ "$n" -eq 0 ] && ok "all manifests satisfy the contract (id · no \"MCP\" · {framework} · connect mode · docs exists)" \
  || no "$n contract violation(s) — see FAIL lines above" ""

echo "── 3. _index.md points at the manifests instead of holding commands ──"
if grep -qE '^\s*claude mcp add (google-workspace|atlassian|github|slack|stitch|spotify-dj|nano-banana|pdf-generator)\b' mcps/_index.md; then
  no "_index.md still holds a register command" "it declared itself the source of truth while carrying 1 of 11 — a section that HOLDS data drifts; one that POINTS cannot"
else
  ok "_index.md holds no register commands"
fi
grep -qF 'connector.json' mcps/_index.md \
  && ok "_index.md names connector.json as the source" \
  || no "_index.md does not point anywhere" "removing the commands without naming their replacement is worse than leaving them"

echo "── 4. adding a new MCP requires a manifest ──"
if awk '/^## Adding a new MCP/,0' mcps/_index.md | grep -qF 'connector.json'; then
  ok "the add-an-MCP checklist requires connector.json"
else
  no "a new MCP can be added without a manifest" "it would be invisible to the App with nothing reporting why"
fi

echo "── 5. CONTROL — the criteria must be able to fail ──"
T=$(mktemp -d); mkdir -p "$T/mcps/broken-mcp"
cat > "$T/mcps/broken-mcp/connector.json" <<'J'
{ "id": "wrong", "service": "Broken MCP", "value": "v", "connect": "sometimes",
  "requires": ["~/aios/mcps/broken-mcp/x"], "register": {}, "docs": "NOPE.md" }
J
hits=$(cd "$T" && python3 - <<'PY'
import json,glob,os,re
c=0
for f in sorted(glob.glob("mcps/*-mcp/connector.json")):
    folder=os.path.basename(os.path.dirname(f)); d=json.load(open(f)); blob=json.dumps(d)
    if d.get("id")!=folder[:-4]: c+=1
    if re.search(r'\bMCPs?\b',str(d.get("service","")),re.I): c+=1
    c+=len(re.findall(r'~/aios[^"]*',blob))
    if d.get("connect") not in ("one-click","needs-key","guided"): c+=1
    docs=d.get("docs")
    if docs and not os.path.isfile(os.path.join(os.path.dirname(f),docs)): c+=1
    if d.get("registers",True) and not d.get("register",{}).get("command"): c+=1
print(c)
PY
)
rm -rf "$T"
[ "${hits:-0}" -ge 5 ] && ok "CONTROL FIRES: a deliberately broken manifest trips $hits criteria" \
  || no "CONTROL DID NOT FIRE (only ${hits:-0}) — section 2 proves nothing"


echo "── 6. mcps/custom/ — validated if present, never required ──"
# The App reads manifests from every folder under mcps/, custom/ included, and a
# custom MCP with no manifest is not shown as broken — it is not shown at all. A
# real one was found registered and working, invisible to the card, and it
# surfaced only when the App started reporting unmanifested folders.
#
# But this suite CANNOT be the guard for that, and the reason is structural rather
# than an oversight: mcps/custom/ is operator content that /aios:update never
# touches, and tests/ is repo infrastructure deliberately never synced to a vault
# (Tier 0). So canonical CI runs where there is no custom content, and the operator
# who has custom content never runs canonical CI. Asserting a manifest EXISTS here
# would fail on nothing and protect nobody.
#
# What this suite can honestly do is two things: validate a custom manifest if one
# is ever present (a canonical example, or a contributor's fixture), and assert
# that the DOCUMENTATION carries the rule — because documentation is the only
# canonical surface that actually reaches the operator's machine.
CUSTOM=$(ls -d mcps/custom/*/ 2>/dev/null | wc -l | tr -d ' ')
CUSTOM_MANIFESTS=$(ls mcps/custom/*/connector.json 2>/dev/null | wc -l | tr -d ' ')
if [ "${CUSTOM:-0}" -eq 0 ]; then
  ok "no custom MCP folders in canonical — nothing to validate (expected)"
else
  bad_custom=$(python3 - <<'PY'
import json,glob,os,re
c=0
for f in sorted(glob.glob("mcps/custom/*/connector.json")):
    folder=os.path.basename(os.path.dirname(f))
    try: d=json.load(open(f))
    except Exception: c+=1; continue
    if d.get("id") != folder[:-4] if folder.endswith("-mcp") else False: c+=1
    if re.search(r'\bMCPs?\b', str(d.get("service","")), re.I): c+=1
    c += len(re.findall(r'~/aios[^"]*', json.dumps(d)))
    if d.get("connect") not in ("one-click","needs-key","guided"): c+=1
print(c)
PY
)
  [ "${bad_custom:-0}" -eq 0 ] \
    && ok "$CUSTOM custom folder(s), $CUSTOM_MANIFESTS manifest(s), 0 violations" \
    || no "$bad_custom violation(s) in a custom manifest" "same contract applies wherever a manifest lives"
fi

# The doc rule is the part that reaches an operator, so it is the part asserted.
if grep -qiE 'connector\.json' mcps/custom/_index.md; then
  ok "mcps/custom/_index.md tells an operator their MCP needs a manifest"
else
  no "the custom-MCP index does not mention connector.json" \
     "the App will silently not list their MCP, and this suite never reaches their machine to say so"
fi
if awk '/^## Adding a new MCP/,0' mcps/_index.md | grep -qiE 'custom'; then
  ok "the add-an-MCP checklist covers mcps/custom/ explicitly"
else
  no "the checklist does not mention custom/" "the case that most needs stating is the one nothing checks"
fi

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

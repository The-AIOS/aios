#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The model-routing ladder, the non-Claude rail, and the boundary between them
#
# THREE THINGS THIS PROTECTS
#
# 1. THE TWO WRAPPERS MUST AGREE. The tier→model map is implemented twice —
#    a bash `case` and a PowerShell `switch`. Nothing but a test connects them,
#    and a fix applied to one and not the other is the single most likely defect
#    in this feature: it is invisible on the author's own platform.
#
# 2. `mechanical` MUST KEEP RESOLVING TO SONNET 4.6. It predates the ladder and
#    is live in operators' habits, routines and scripts. Changing what an
#    existing flag resolves to changes the cost and behaviour of work already
#    running. This suite pins it so a future tidy-up cannot silently remap it —
#    the failure would be invisible (a spawn still works; it just costs
#    differently and answers differently).
#
# 3. NO INVENTED MODEL IDS. An id Claude Code does not recognise prints
#    [claude-code:unrecognized_model] and then bills ZERO tokens, so "the spawn
#    worked" is not evidence. The first draft of openrouter.py shipped two
#    plausible ids that did not exist — one absent from the public OpenRouter
#    catalog, one 404ing on generateContent. Both were caught by asking the live
#    catalogs. The assertions below pin the corrected values.
#
# Every check here is written so it CAN fail: the wrapper-agreement check parses
# both implementations and compares the maps rather than grepping for presence,
# and the rail checks run the script with a scrubbed HOME and env so a key on
# the developer's own machine cannot make an "unconfigured" assertion vacuous.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

SH=hooks/claude-identity/install-wrappers.sh
PS=hooks/claude-identity/install-wrappers.ps1
RAIL=hooks/openrouter.py
DOC=MODEL-ROUTING.md

echo "── the two wrappers implement the SAME ladder ──"
maps=$(python3 - "$SH" "$PS" <<'PY'
import re, sys
sh, ps = open(sys.argv[1], encoding='utf-8').read(), open(sys.argv[2], encoding='utf-8').read()

# bash:  frontier)    spawn_model='claude-fable-5-1' ;;
shmap = dict(re.findall(r"^\s*(frontier|scale|fast|mechanical)\)\s*spawn_model='([^']+)'", sh, re.M))
# judgment maps to the empty override (the frontier default) in both.
if re.search(r"^\s*judgment\|\"\"\)\s*spawn_model=\"\"", sh, re.M):
    shmap['judgment'] = '<default>'

# powershell:  'frontier'   { 'claude-fable-5-1' }
psmap = dict(re.findall(r"^\s*'(frontier|scale|fast|mechanical)'\s*\{\s*'([^']+)'\s*\}", ps, re.M))
if re.search(r"^\s*default\s*\{\s*\$null\s*\}", ps, re.M):
    psmap['judgment'] = '<default>'

print("SH:" + ",".join(f"{k}={v}" for k, v in sorted(shmap.items())))
print("PS:" + ",".join(f"{k}={v}" for k, v in sorted(psmap.items())))
print("AGREE" if shmap == psmap and len(shmap) == 5 else "DISAGREE")
PY
)
shrow=$(printf '%s\n' "$maps" | sed -n 's/^SH://p')
psrow=$(printf '%s\n' "$maps" | sed -n 's/^PS://p')
if printf '%s\n' "$maps" | grep -q '^AGREE$'; then
  ok "both wrappers map all 5 tiers identically"
  printf '       %s\n' "$shrow"
else
  no "the bash and PowerShell tier maps differ (or one is incomplete)" "sh=[$shrow] ps=[$psrow]"
fi

echo "── the back-compat contract: mechanical is still Sonnet 4.6 ──"
for f in "$SH" "$PS"; do
  if grep -qE "mechanical'?\)?\s*(spawn_model=)?'?\{?\s*'?claude-sonnet-4-6" "$f"; then
    ok "$(basename "$f"): mechanical → claude-sonnet-4-6"
  else
    no "$(basename "$f"): mechanical no longer resolves to claude-sonnet-4-6" \
       "remapping a live flag changes cost + behaviour of work already running"
  fi
done

echo "── the stale-shell guard knows EVERY tier word ──"
# A tier the guard does not list is a tier it goes silent on — which is the
# precise failure the guard exists to surface.
for w in mechanical judgment frontier scale fast; do
  g_sh=$(sed -n '/_bare_tier=1/p' "$SH")
  g_ps=$(grep -n "Task -in 'mechanical'" "$PS")
  case "$g_sh" in *"$w"*) a=1 ;; *) a=0 ;; esac
  case "$g_ps" in *"$w"*) b=1 ;; *) b=0 ;; esac
  if [ "$a$b" = "11" ]; then ok "guard lists '$w' on both platforms"
  else no "guard is missing tier word '$w'" "sh=$a ps=$b — a stale shell would silently make a junk worker"; fi
done

echo "── the routing doc names every rung and the boundary ──"
[ -f "$DOC" ] && ok "$DOC exists" || no "$DOC missing"
for s in frontier judgment scale fast 'Judge independence' 'containment boundary' 'unrecognized_model'; do
  grep -qF "$s" "$DOC" && ok "doc covers: $s" || no "doc never mentions: $s"
done
# The doc must ship to operator vaults or it is canonical-only trivia.
grep -qF '"MODEL-ROUTING.md"' plugins/aios/commands/update.md \
  && ok "MODEL-ROUTING.md is in the /aios:update sync list" \
  || no "MODEL-ROUTING.md is NOT in update.md's sync list" "it would never reach an operator vault"

echo "── the rail refuses rather than guessing (env + HOME scrubbed) ──"
TMPH=$(mktemp -d)
run_clean(){ env -u OPENROUTER_API_KEY -u GEMINI_API_KEY HOME="$TMPH" python3 "$RAIL" "$@" 2>&1; }
out=$(run_clean --prompt hi); rc=$?
if [ "$rc" = "3" ]; then ok "no key → exit 3 (a distinct code, not a generic 1)"
else no "no key → exit $rc, expected 3" "$(printf '%s' "$out" | head -2)"; fi
case "$out" in *OPENROUTER_API_KEY*) ok "refusal names the OpenRouter path" ;; *) no "refusal never names OPENROUTER_API_KEY" ;; esac
case "$out" in *GEMINI_API_KEY*) ok "refusal names the Gemini fallback path" ;; *) no "refusal never names GEMINI_API_KEY" ;; esac
case "$out" in *aios-secrets*) ok "refusal names the file to create" ;; *) no "refusal never names the secrets file" ;; esac
# Control: the assertions above are only meaningful if the scrub actually worked.
case "$(run_clean --check)" in *"resolved    : NONE"*) ok "control: the scrub really removed every key" ;;
  *) no "CONTROL FAILED — a key survived the scrub, so the refusal assertions proved nothing" ;; esac
rm -rf "$TMPH"

echo "── an empty completion is a failure, not an answer ──"
grep -qF 'treating as failure, not as an empty result' "$RAIL" \
  && ok "empty completion is reported as failure" \
  || no "an empty completion could pass as a result" "a judge returning nothing reads like a judge finding nothing wrong"

echo "── the corrected model ids are pinned (assignment lines only) ──"
# Scoped to what EXECUTES. A whole-file grep here fires on the comment that
# documents the bad guess — the mistake this very check was written after.
asg=$(grep -E '^(OPENROUTER|GEMINI)_DEFAULT[[:space:]]*=' "$RAIL")
[ "$(printf '%s\n' "$asg" | wc -l | tr -d ' ')" = "2" ] && ok "exactly 2 default assignments" || no "expected 2 default assignments" "$asg"
printf '%s\n' "$asg" | grep -qF 'OPENROUTER_DEFAULT = "google/gemini-2.5-pro"' \
  && ok "OpenRouter default is the verified catalog id" || no "OpenRouter default is not the verified id" "$asg"
printf '%s\n' "$asg" | grep -qF 'GEMINI_DEFAULT = "gemini-pro-latest"' \
  && ok "Gemini default is the verified floating alias" || no "Gemini default is not the verified alias" "$asg"

echo "── the rail is stdlib-only (must run from a routine on a fresh machine) ──"
nonstd=$(python3 - "$RAIL" <<'PY'
import ast, sys
stdlib = {"argparse","json","os","sys","urllib","pathlib","re","subprocess","typing"}
bad = []
for n in ast.walk(ast.parse(open(sys.argv[1], encoding="utf-8").read())):
    if isinstance(n, ast.Import):
        bad += [a.name.split(".")[0] for a in n.names if a.name.split(".")[0] not in stdlib]
    elif isinstance(n, ast.ImportFrom) and n.module:
        m = n.module.split(".")[0]
        if m not in stdlib: bad.append(m)
print(",".join(sorted(set(bad))))
PY
)
[ -z "$nonstd" ] && ok "no third-party imports" || no "third-party imports present: $nonstd" "breaks 'no pip install' on a fresh machine"

echo "── --check never makes a network call ──"
grep -q 'if a.check:' "$RAIL" && python3 - "$RAIL" <<'PY' && ok "--check returns before any request" || no "--check may reach the network"
import ast, sys, re
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
fn = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "main")
# find the `if a.check:` block and assert it ends in a return with no _post/urlopen inside
for node in ast.walk(fn):
    if isinstance(node, ast.If) and "check" in ast.dump(node.test):
        body = ast.dump(ast.Module(body=node.body, type_ignores=[]))
        assert "_post" not in body and "urlopen" not in body, "network call inside --check"
        assert "Return" in body, "--check does not return"
        sys.exit(0)
sys.exit(1)
PY

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]

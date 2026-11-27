#!/usr/bin/env bash
# tests/inbox-contract-5.test.sh
#
# Contract 5 adds the `open` verb: a session asks a surface to show a file in its own viewer. The
# decision is security-sensitive (any session can ask, and a session may have read someone else's
# text), and it has to come out the same in the App and in Glass. So it is written once, as an
# ordered list of checks in inbox-contract-5.md, and once more as a fixture both surfaces run.
#
# This suite holds the two together: every case in the fixture passes a reference implementation
# of the spec's twelve checks, the spec and the fixture name the same refusal codes, and the
# numbers the spec states (60 seconds, 5 opens, the line bound) are the ones the fixture uses.
# A control proves the reference can fail.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/skills/aios/orchestration-ladder"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; [ -n "${2:-}" ] && echo "      $2"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cat > "$T/ref.py" <<'PY'
"""Reference implementation of inbox-contract-5.md § The decision, in order."""
import json, re, sys

SECRET_SEGMENTS = {".ssh", ".gnupg", ".aws", "agent-secrets"}
EXEC_EXT = (".exe", ".com", ".bat", ".cmd", ".ps1", ".msi", ".scr", ".app", ".command")

def is_secret(path):
    segs = [s.lower() for s in path.split("/") if s]
    if not segs:
        return False
    if any(s in SECRET_SEGMENTS for s in segs):
        return True
    b = segs[-1]
    if b == ".env" or b.startswith(".env.") or b.endswith(".env") or b in (".envrc", ".netrc", ".pgpass"):
        return True
    if b.endswith((".pem", ".key", ".p12", ".pfx")):
        return True
    return re.fullmatch(r"id_(rsa|dsa|ecdsa|ed25519)(_sk)?", b) is not None

def sanitize(name):
    # the surfaces' sessionKey: trim, lower, whitespace to dashes, drop the rest, trim dashes
    s = re.sub(r"\s+", "-", str(name).strip().lower())
    return re.sub(r"[^a-z0-9-]", "", s).strip("-")

class FS:
    def __init__(self, entries):
        self.e = entries
    def resolve(self, path):
        queue = [c for c in path.split("/") if c]
        out, hops = [], 0
        while queue:
            c = queue.pop(0)
            if c == ".":
                continue
            if c == "..":
                if out: out.pop()
                continue
            cand = "/" + "/".join(out + [c])
            node = self.e.get(cand)
            if node and node["kind"] == "symlink":
                hops += 1
                if hops > 40:
                    return None
                queue = [x for x in node["to"].split("/") if x] + queue
                out = []
                continue
            out.append(c)
        p = "/" + "/".join(out)
        return p if self.exists(p) else None
    def exists(self, p):
        return p in self.e or any(k.startswith(p.rstrip("/") + "/") for k in self.e)
    def node(self, p):
        return self.e.get(p, {"kind": "dir"})

def decide(doc, case, now=1_000_000_000_000):
    k = doc["constants"]; fs = FS(doc["fs"]); req = case["request"]
    name = sanitize(req.get("name", "")) if isinstance(req.get("name"), str) else ""
    if not name:
        return {"do": "refuse", "why": "missing-name"}
    p = req.get("path")
    if not isinstance(p, str) or not p.strip() or any(ch in p for ch in "\x00\r\n"):
        return {"do": "refuse", "why": "bad-path"}
    p = p.strip()
    if p.startswith("~") or not p.startswith("/"):
        return {"do": "refuse", "why": "not-absolute"}
    if case.get("age_ms", 0) > k["max_age_ms"]:
        return {"do": "refuse", "why": "too-old"}
    line = req.get("line")
    if "line" in req and not (type(line) is int and 1 <= line <= k["max_line"]):
        return {"do": "refuse", "why": "bad-line"}
    if is_secret(p):
        return {"do": "refuse", "why": "secret"}
    real = fs.resolve(p)
    if real is None:
        return {"do": "refuse", "why": "not-found"}
    roots = [r for r in (fs.resolve(x) for x in doc["roots"]) if r]
    if not any(real == r or real.startswith(r.rstrip("/") + "/") for r in roots):
        return {"do": "refuse", "why": "outside-roots"}
    node = fs.node(real)
    if node["kind"] != "file":
        return {"do": "refuse", "why": "not-a-file"}
    if is_secret(real):
        return {"do": "refuse", "why": "secret"}
    if node.get("class") in ("binary", "large"):
        return {"do": "refuse", "why": "unreadable"}
    if node.get("executable") or real.lower().endswith(EXEC_EXT):
        return {"do": "refuse", "why": "executable"}
    recent = [x for x in case.get("recent", []) if sanitize(x["name"]) == name
              and x["ago_ms"] <= k["rate_window_ms"] and x["path"] != real]
    if len(recent) >= k["rate_max"]:
        return {"do": "refuse", "why": "rate-limited"}
    out = {"do": "open", "path": real, "mode": "source" if real.lower().endswith((".html", ".htm")) else "auto"}
    if "line" in req:
        out["line"] = line
    return out

doc = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
for c in doc["cases"]:
    got = decide(doc, c)
    if got != c["expect"]:
        bad.append("%s: expected %s, got %s" % (c["case"], c["expect"], got))
print("CASES", "ok %d" % len(doc["cases"]) if not bad else "; ".join(bad))
whys = sorted({c["expect"]["why"] for c in doc["cases"] if c["expect"]["do"] == "refuse"})
print("WHYS", ",".join(whys))
print("OPENS", sum(1 for c in doc["cases"] if c["expect"]["do"] == "open"))
PY

F="$D/inbox-contract-5.conformance.json"; S="$D/inbox-contract-5.md"
[ -f "$F" ] && [ -f "$S" ] || { no "the contract 5 spec or its fixture is missing"; echo "── RESULT: $PASS passed, $FAIL failed ──"; exit 1; }

echo "── every case passes the reference implementation of the spec ──"
out=$($PYBIN "$T/ref.py" "$F" 2>&1)
case "$(printf '%s\n' "$out" | grep '^CASES')" in "CASES ok "*) ok "$(printf '%s\n' "$out" | grep '^CASES' | sed 's/CASES ok //') cases agree with the reference" ;; *) no "fixture and reference disagree" "$(printf '%s\n' "$out" | head -5)" ;; esac
n=$(printf '%s\n' "$out" | grep '^OPENS' | cut -d' ' -f2)
[ "${n:-0}" -ge 10 ] && ok "$n cases open a file (the fixture is not all refusals)" || no "only '${n:-0}' cases open a file"

echo "── the spec and the fixture name the same refusals ──"
FIX=$(printf '%s\n' "$out" | grep '^WHYS' | cut -d' ' -f2 | tr ',' '\n' | sort -u)
SPEC=$(grep -oE '\[`[a-z-]+`\]' "$S" | tr -d '[]`' | sort -u)
[ -n "$SPEC" ] && [ "$FIX" = "$SPEC" ] && ok "same $(printf '%s\n' "$SPEC" | grep -c .) codes: $(printf '%s ' $SPEC)" \
  || no "codes differ" "only in the spec: $(comm -23 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ') · only in the fixture: $(comm -13 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ')"

echo "── the numbers the spec states are the ones the fixture uses ──"
k(){ $PYBIN -c "import json,sys; print(json.load(open(sys.argv[1]))['constants'][sys.argv[2]])" "$F" "$1"; }
[ "$(k max_age_ms)" = "60000" ] && grep -q 'older than \*\*60 seconds\*\*' "$S" && ok "60 seconds, in both" || no "the age bound differs between the spec and the fixture"
[ "$(k rate_max)" = "5" ] && [ "$(k rate_window_ms)" = "60000" ] && grep -q '\*\*5\*\* files opened by this surface in the last \*\*60 seconds\*\*' "$S" && ok "5 opens a minute, in both" || no "the rate differs between the spec and the fixture"
[ "$(k max_line)" = "10000000" ] && grep -q '1 to 10,000,000' "$S" && ok "the line bound, in both" || no "the line bound differs"

echo "── the spec says it is not in force yet, and the declared contract is not moved here ──"
grep -q 'Status: specified, not in force' "$S" && ok "the spec is marked as not in force" || no "the spec does not say it is not in force" "a session reading it would send a verb no surface implements"
if [ -f "$D/inbox-contract.json" ]; then
  grep -qE '"current" *: *5' "$D/inbox-contract.json" && no "inbox-contract.json declares 5 before any surface stamps it" || ok "the declared current contract is not 5 yet"
else
  ok "no declaration file on this branch (it arrives with the contract-number check)"
fi

echo "── CONTROL — a wrong expectation is caught ──"
$PYBIN - "$F" "$T/bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for c in d["cases"]:
    if c["case"] == "a link in the vault to a key outside the roots":
        c["expect"] = {"do": "open", "path": "/home/op/.ssh/id_ed25519", "mode": "auto"}
json.dump(d, open(sys.argv[2], "w"))
PY
case "$($PYBIN "$T/ref.py" "$T/bad.json" | grep '^CASES')" in "CASES ok "*) no "control: a fixture that opens an ssh key through a link still passed" ;; *) ok "control: a fixture that opens an ssh key through a link is caught" ;; esac

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ] && [ "$PASS" -ge 8 ]

#!/usr/bin/env bash
# tests/inbox-contract-5.test.sh
#
# Contract 5 adds the `open` verb: a session asks a surface to show a file in its own viewer. The
# decision is security-sensitive (any session can ask, and a session may have read someone else's
# text), and it has to come out the same in the App and in Glass. So it is written once, as an
# ordered list of checks in inbox-contract-5.md, and once more as a fixture both surfaces run.
#
# This suite holds the two together: every case in the fixture passes a reference implementation
# of the spec's checks, the spec and the fixture name the same refusal codes, and the numbers the
# spec states are the ones the fixture uses. A control proves the reference can fail.
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
import json, math, re, sys

SECRET_SEGMENTS = {".ssh", ".gnupg", ".aws", "agent-secrets", ".git", ".docker", ".kube", ".obsidian"}
SECRET_NAMES = {".envrc", ".netrc", ".pgpass", ".npmrc", ".pypirc", ".git-credentials", ".dockercfg", ".mcp.json", "storage_state.json"}
SECRET_EXT = (".pem", ".key", ".p12", ".pfx", ".kdbx", ".ovpn", ".ppk", ".jks", ".keystore")
DATA_EXT = (".json", ".yaml", ".yml", ".toml")
DATA_WORDS = ("token", "credential", "oauth", "secret", "cookie")
EXEC_EXT = (".exe", ".com", ".bat", ".cmd", ".ps1", ".msi", ".scr", ".app", ".command", ".lnk", ".url", ".webloc",
            ".desktop", ".terminal", ".jar", ".vbs", ".hta", ".reg", ".scpt", ".workflow", ".pkg", ".dmg", ".appimage")
SOURCE_EXT = (".html", ".htm", ".xhtml", ".xht", ".shtml", ".mht", ".mhtml")
RESERVED = re.compile(r"(con|prn|aux|nul|com[1-9]|lpt[1-9])", re.I)

def is_secret(path):
    segs = [s.lower() for s in re.split(r"[\\/]+", path) if s]
    if not segs:
        return False
    if any(s in SECRET_SEGMENTS for s in segs):
        return True
    b = segs[-1]
    if b == ".env" or b.startswith(".env.") or b.endswith(".env") or b in SECRET_NAMES:
        return True
    if b.endswith(SECRET_EXT):
        return True
    if b.startswith("service-account") and b.endswith(".json"):
        return True
    if b.endswith(DATA_EXT) and any(w in b for w in DATA_WORDS):
        return True
    return re.fullmatch(r"id_(rsa|dsa|ecdsa|ed25519)(_sk)?", b) is not None

def sanitize(name):
    # the surfaces' sessionKey: trim, lower, whitespace to dashes, drop the rest, trim dashes
    s = re.sub(r"\s+", "-", str(name).strip().lower())
    return re.sub(r"[^a-z0-9-]", "", s).strip("-")

def windows_shape(p):
    """The path-shape checks with Windows rules; None when they pass."""
    if p.startswith("\\\\") or p.startswith("//"):
        return "bad-path"
    if not re.match(r"^[A-Za-z]:[\\/]", p):
        return "not-absolute"
    rest = p[2:]
    if ":" in rest:
        return "bad-path"
    for seg in [s for s in re.split(r"[\\/]+", rest) if s]:
        if seg.endswith(".") or seg.endswith(" ") or RESERVED.fullmatch(seg.split(".")[0]):
            return "bad-path"
    return None

def lexical(p):
    out = []
    for c in p.split("/"):
        if c in ("", "."):
            continue
        if c == "..":
            if out: out.pop()
            continue
        out.append(c)
    return "/" + "/".join(out)

def under(p, r):
    return p == r or p.startswith(r.rstrip("/") + "/")

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
        return p if (p in self.e or any(k.startswith(p.rstrip("/") + "/") for k in self.e)) else None
    def node(self, p):
        return self.e.get(p, {"kind": "dir"})

def usable_roots(doc, fs):
    home = fs.resolve(doc["home"]) or doc["home"]
    keep = []
    for r in doc["roots"]:
        rr = fs.resolve(r)
        if not rr or rr == "/" or under(home, rr):
            continue   # the filesystem root, the home folder or one of its ancestors is never a root
        keep.append((lexical(r), rr))
    return keep

def decide(doc, case):
    k = doc["constants"]; fs = FS(doc["fs"]); req = case["request"]
    name = sanitize(req.get("name")) if isinstance(req.get("name"), str) else ""
    if not name or len(name) > k["max_name"]:
        return {"do": "refuse", "why": "bad-name"}
    recent = [x for x in case.get("recent", []) if x["ago_ms"] <= k["rate_window_ms"]]
    if len(recent) >= k["flood_max"]:
        return {"do": "refuse", "why": "flood"}
    if sum(1 for x in recent if sanitize(x["name"]) == name) >= k["rate_max"]:
        return {"do": "refuse", "why": "rate-limited"}
    p = req.get("path")
    if not isinstance(p, str) or any(ch in p for ch in "\x00\r\n") or not p.strip():
        return {"do": "refuse", "why": "bad-path"}
    p = p.strip()
    if p.startswith("~") or not p.startswith("/"):
        return {"do": "refuse", "why": "not-absolute"}
    if case.get("present_at_start") or case.get("age_ms", 0) > k["max_age_ms"]:
        return {"do": "refuse", "why": "too-old"}
    if "line" in req:
        line = req["line"]
        if isinstance(line, bool) or not isinstance(line, (int, float)) or not math.isfinite(line) \
                or float(line) != int(line) or not 1 <= int(line) <= k["max_line"]:
            return {"do": "refuse", "why": "bad-line"}
    if is_secret(p):
        return {"do": "refuse", "why": "secret"}
    roots = usable_roots(doc, fs)
    lp = lexical(p)
    if not any(under(lp, w) or under(lp, rr) for w, rr in roots):
        return {"do": "refuse", "why": "unavailable"}
    real = fs.resolve(p)
    if real is None or not any(under(real, rr) for _, rr in roots):
        return {"do": "refuse", "why": "unavailable"}
    node = fs.node(real)
    if node["kind"] != "file":
        return {"do": "refuse", "why": "not-a-file"}
    if node.get("links", 1) > 1:
        return {"do": "refuse", "why": "hard-link"}
    if is_secret(real):
        return {"do": "refuse", "why": "secret"}
    if node.get("class") in ("binary", "large"):
        return {"do": "refuse", "why": "unreadable"}
    if node.get("executable") or real.lower().endswith(EXEC_EXT):
        return {"do": "refuse", "why": "executable"}
    out = {"do": "open", "path": real, "mode": "source" if real.lower().endswith(SOURCE_EXT) else "auto"}
    if "line" in req:
        out["line"] = int(req["line"])
    return out

doc = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
for c in doc["cases"]:
    got = decide(doc, c)
    if got != c["expect"]:
        bad.append("%s: expected %s, got %s" % (c["case"], c["expect"], got))
for w in doc.get("windows_paths", []):
    got = windows_shape(w["path"].strip()) or ("secret" if is_secret(w["path"].strip()) else None)
    if got != w["why"]:
        bad.append("windows %s: expected %s, got %s" % (w["case"], w["why"], got))
print("CASES", "ok %d" % (len(doc["cases"]) + len(doc.get("windows_paths", []))) if not bad else "; ".join(bad))
whys = sorted({c["expect"]["why"] for c in doc["cases"] if c["expect"]["do"] == "refuse"}
              | {w["why"] for w in doc.get("windows_paths", []) if w["why"]})
print("WHYS", ",".join(whys))
print("OPENS", sum(1 for c in doc["cases"] if c["expect"]["do"] == "open"))
PY

F="$D/inbox-contract-5.conformance.json"; S="$D/inbox-contract-5.md"
[ -f "$F" ] && [ -f "$S" ] || { no "the contract 5 spec or its fixture is missing"; echo "── RESULT: $PASS passed, $FAIL failed ──"; exit 1; }

echo "── every case passes the reference implementation of the spec ──"
out=$($PYBIN "$T/ref.py" "$F" 2>&1)
case "$(printf '%s\n' "$out" | grep '^CASES')" in "CASES ok "*) ok "$(printf '%s\n' "$out" | grep '^CASES' | sed 's/CASES ok //') cases agree with the reference" ;; *) no "fixture and reference disagree" "$(printf '%s\n' "$out" | head -8)" ;; esac
n=$(printf '%s\n' "$out" | grep '^OPENS' | cut -d' ' -f2)
[ "${n:-0}" -ge 15 ] && ok "$n cases open a file (the fixture is not all refusals)" || no "only '${n:-0}' cases open a file"

echo "── the spec and the fixture name the same refusals ──"
FIX=$(printf '%s\n' "$out" | grep '^WHYS' | cut -d' ' -f2 | tr ',' '\n' | sort -u)
SPEC=$(grep -oE '\[`[a-z-]+`\]' "$S" | tr -d '[]`' | sort -u)
[ -n "$SPEC" ] && [ "$FIX" = "$SPEC" ] && ok "same $(printf '%s\n' "$SPEC" | grep -c .) codes: $(printf '%s ' $SPEC)" \
  || no "codes differ" "only in the spec: $(comm -23 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ') · only in the fixture: $(comm -13 <(printf '%s\n' "$SPEC") <(printf '%s\n' "$FIX") | tr '\n' ' ')"

echo "── the numbers the spec states are the ones the fixture uses ──"
k(){ $PYBIN -c "import json,sys; print(json.load(open(sys.argv[1]))['constants'][sys.argv[2]])" "$F" "$1"; }
[ "$(k max_age_ms)" = "60000" ] && grep -q 'more than \*\*60 seconds\*\* ago' "$S" && ok "60 seconds, in both" || no "the age bound differs between the spec and the fixture"
[ "$(k rate_max)" = "5" ] && [ "$(k flood_max)" = "20" ] && [ "$(k rate_window_ms)" = "60000" ] \
  && grep -q '\*\*20\*\* or more' "$S" && grep -q '\*\*5\*\* or more' "$S" && ok "5 a session and 20 in all, a minute, in both" || no "the rates differ between the spec and the fixture"
[ "$(k max_line)" = "10000000" ] && grep -q '1 to 10,000,000' "$S" && ok "the line bound, in both" || no "the line bound differs"
[ "$(k max_name)" = "64" ] && grep -q 'longer than 64' "$S" && ok "the name bound, in both" || no "the name bound differs"

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
    if c["case"] == "a file with a second hard link":
        c["expect"] = {"do": "open", "path": "/home/op/aios/vault/meeting.md", "mode": "auto"}
json.dump(d, open(sys.argv[2], "w"))
PY
case "$($PYBIN "$T/ref.py" "$T/bad.json" | grep '^CASES')" in "CASES ok "*) no "control: a fixture that opens a hard-linked file still passed" ;; *) ok "control: a fixture that opens a hard-linked file is caught" ;; esac

echo "── RESULT: $PASS passed, $FAIL failed ──"
[ "$FAIL" = 0 ] && [ "$PASS" -ge 9 ]

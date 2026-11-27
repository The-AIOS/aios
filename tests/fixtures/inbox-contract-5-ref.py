"""Reference implementation of skills/aios/orchestration-ladder/inbox-contract-5.md, § The decision,
in order, run by tests/inbox-contract-5.test.sh against every case of inbox-contract-5.conformance.json.

It is the framework's own reading of the spec, written in a second language from the surfaces' (they
are TypeScript), so a fixture that only one reading accepts is caught here before a surface runs it.

Usage: python3 inbox-contract-5-ref.py <fixture.json>
Prints `CASES ok N` (or every disagreement), `WHYS <codes>` and `OPENS <n>`.
"""
import json
import math
import posixpath
import re
import sys

MAX_HOPS = 40
MAX_PATH = 4096
SECRET_SEGMENTS = {".ssh", ".gnupg", ".aws", "agent-secrets", ".git", ".docker", ".kube", ".obsidian", ".claude"}
SECRET_NAMES = {".netrc", ".pgpass", ".npmrc", ".pypirc", ".git-credentials", ".dockercfg", ".mcp.json",
                "storage_state.json", "spotify-cache.json", ".dev.vars", "credentials", "kubeconfig",
                "auth.json", ".htpasswd", ".vault-token", ".yarnrc.yml", ".s3cfg", ".my.cnf"}
SECRET_EXT = (".pem", ".key", ".p12", ".pfx", ".p8", ".kdbx", ".ovpn", ".ppk", ".jks", ".keystore", ".tfstate", ".tfvars")
WORD_EXT = (".json", ".yaml", ".yml", ".toml", ".txt")
WORDS = {"token", "tokens", "credential", "credentials", "oauth", "secret", "secrets", "cookie", "cookies",
         "password", "passwords", "apikey"}
EXEC_EXT = (".exe", ".com", ".bat", ".cmd", ".ps1", ".msi", ".scr", ".app", ".command", ".lnk", ".url", ".webloc",
            ".desktop", ".terminal", ".jar", ".vbs", ".hta", ".reg", ".scpt", ".workflow", ".pkg", ".dmg", ".appimage",
            ".jse", ".vbe", ".wsf", ".wsh", ".cpl", ".msc", ".pif", ".scf", ".appref-ms", ".application",
            ".appinstaller", ".msix", ".appx", ".msp", ".settingcontent-ms", ".library-ms", ".searchconnector-ms",
            ".fileloc", ".inetloc", ".afploc", ".mobileconfig", ".jnlp")
DOC_EXT = (".md", ".markdown", ".txt", ".json", ".yaml", ".yml", ".toml", ".csv", ".log", ".html", ".htm",
           ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf")
SOURCE_EXT = (".html", ".htm", ".xhtml", ".xht", ".shtml", ".mht", ".mhtml")
RESERVED = re.compile(r"(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³]|conin\$|conout\$)")
BAD_CHARS = re.compile(r"[\x00-\x1f\x7f-\x9f‪-‮⁦-⁩]")


def fold(s):
    """Full Unicode case folding, the way a case-insensitive file system compares names."""
    return s.casefold()


def words_of(stem):
    stem = re.sub(r"([a-z])([A-Z])", r"\1 \2", stem)      # camelCase → camel Case
    return re.findall(r"[a-z]+|[0-9]+", fold(stem))


def is_secret(path):
    segs = [fold(s) for s in re.split(r"[\\/]+", path) if s]
    if not segs:
        return False
    if any(s in SECRET_SEGMENTS for s in segs):
        return True
    raw_b = [s for s in re.split(r"[\\/]+", path) if s][-1]
    b = segs[-1]
    if b.startswith(".env") or b.endswith(".env") or b in SECRET_NAMES:
        return True
    if b.endswith(SECRET_EXT):
        return True
    if b.endswith(".json") and (b.startswith("service-account") or "firebase-adminsdk" in b):
        return True
    if len(segs) > 1 and segs[-2] == "auth" and b.endswith(".json"):
        return True
    if b.endswith(WORD_EXT) or "." not in b.lstrip("."):
        stem = raw_b.rsplit(".", 1)[0] if "." in raw_b.lstrip(".") else raw_b
        w = words_of(stem)
        if WORDS & set(w) or any(w[i] == "api" and w[i + 1] == "key" for i in range(len(w) - 1)):
            return True
    return re.match(r"id_(rsa|dsa|ecdsa|ed25519)", b) is not None and not b.endswith(".pub")


def sanitize(name):
    # the surfaces' sessionKey: trim, lower, whitespace to dashes, keep a-z 0-9 and dashes, trim dashes
    s = re.sub(r"\s+", "-", str(name).strip().lower())
    return re.sub(r"[^a-z0-9-]", "", s).strip("-")


def windows_shape(p):
    """The path-shape checks with Windows rules; None when they pass."""
    if re.match(r"^[\\/]{2}", p):
        return "bad-path"
    if not re.match(r"^[A-Za-z]:[\\/]", p):
        return "not-absolute"
    rest = p[2:]
    if ":" in rest:
        return "bad-path"
    for seg in [s for s in re.split(r"[\\/]+", rest) if s]:
        if seg in (".", "..") or seg.endswith(".") or seg.endswith(" ") or re.search(r"~\d", seg) \
                or RESERVED.fullmatch(fold(seg.split(".")[0].rstrip(" "))):
            return "bad-path"
    return None


def win_cmp(p):
    return fold(re.sub(r"[\\/]+", "\\\\", p)).rstrip("\\")


def win_inside(path, root):
    a, b = win_cmp(path), win_cmp(root)
    return a == b or a.startswith(b + "\\")


def under(p, r):
    return p == r or p.startswith(r.rstrip("/") + "/")


def norm(p):
    return re.sub(r"/+", "/", p).rstrip("/") or "/"


class FS:
    def __init__(self, entries):
        self.e = entries

    def lstat(self, p):
        if p in self.e:
            return self.e[p]
        if any(k.startswith(p.rstrip("/") + "/") for k in self.e):
            return {"kind": "dir"}
        return None

    def realpath_trusted(self, path):
        """Full resolution, for the operator's own configured root only (done once, up front)."""
        queue = [c for c in path.split("/") if c]
        out, hops = [], 0
        while queue:
            c = queue.pop(0)
            cand = "/" + "/".join(out + [c])
            n = self.lstat(cand)
            if n is None:
                return None
            if n["kind"] == "symlink":
                hops += 1
                if hops > MAX_HOPS:
                    return None
                t = n["to"] if n["to"].startswith("/") else posixpath.join(posixpath.dirname(cand), n["to"])
                queue = [x for x in norm(posixpath.normpath(norm(t))).split("/") if x] + queue
                out = []
                continue
            out.append(c)
        return "/" + "/".join(out)


def prepare_roots(roots, home, fs):
    h = fs.realpath_trusted(home) or home
    out = []
    for r in roots:
        rr = fs.realpath_trusted(r)
        if not rr or rr == "/" or under(h, rr):
            continue   # the file-system root, the home folder or one of its ancestors is never a root
        if under(rr, h) and any(s.startswith(".") for s in rr[len(h):].split("/") if s):
            continue   # nor a folder inside a hidden folder of home
        if (fs.lstat(rr + "/vault") or {}).get("kind") != "dir" or (fs.lstat(rr + "/plugins/aios") or {}).get("kind") != "dir":
            continue   # nor one that does not look like a framework root
        out.append((norm(r), rr))
    return out


def resolve_within(p, roots, fs):
    """Segment by segment from the root that holds `p` as text. A link whose target, as text, is
    outside every resolved root stops resolution there, without touching the target."""
    start = None
    for w, rr in roots:
        for base in (w, rr):
            if under(p, base) and (start is None or len(base) > len(start[0])):
                start = (base, rr)
    if start is None:
        return None
    base, cur = start
    queue = [c for c in p[len(base):].split("/") if c]
    hops = 0
    while queue:
        c = queue.pop(0)
        cand = cur.rstrip("/") + "/" + c
        n = fs.lstat(cand)
        if n is None:
            return None
        if n["kind"] == "symlink":
            hops += 1
            if hops > MAX_HOPS:
                return None
            t = n["to"] if n["to"].startswith("/") else cur + "/" + n["to"]
            t = norm(posixpath.normpath(norm(t)))
            holder = [rr for _, rr in roots if under(t, rr)]
            if not holder:
                return None
            r0 = max(holder, key=len)
            queue = [x for x in t[len(r0):].split("/") if x] + queue
            cur = r0
            continue
        cur = cand
    return cur


def decide(doc, case, roots):
    k = doc["constants"]
    fs = FS(doc["fs"])
    req = case["request"]
    # 1. age, by the surface's own clock; a too-old request is not counted
    if case.get("present_at_start") or case.get("age_ms", 0) > k["max_age_ms"]:
        return {"do": "refuse", "why": "too-old"}
    # 2. flood, which needs no field at all
    recent = [x for x in case.get("recent", []) if x["ago_ms"] <= k["rate_window_ms"]]
    if len(recent) >= k["flood_max"]:
        return {"do": "refuse", "why": "flood"}
    # 3. name
    name = sanitize(req.get("name")) if isinstance(req.get("name"), str) else ""
    if not name or len(name) > k["max_name"]:
        return {"do": "refuse", "why": "bad-name"}
    # 4. rate for this name
    if sum(1 for x in recent if sanitize(x["name"]) == name) >= k["rate_max"]:
        return {"do": "refuse", "why": "rate-limited"}
    # 5. path shape
    p = req.get("path")
    if not isinstance(p, str) or not p.strip(" \t") or BAD_CHARS.search(p.strip(" \t")):
        return {"do": "refuse", "why": "bad-path"}
    p = p.strip(" \t")
    if p.startswith("~") or not p.startswith("/"):
        return {"do": "refuse", "why": "not-absolute"}
    if len(p) > MAX_PATH or p.endswith("/") or any(seg in (".", "..") for seg in p.split("/")):
        return {"do": "refuse", "why": "bad-path"}
    # 6. line
    if "line" in req:
        line = req["line"]
        try:
            ok = (not isinstance(line, bool) and isinstance(line, (int, float)) and math.isfinite(float(line))
                  and float(line) == int(line) and 1 <= int(line) <= k["max_line"])
        except (OverflowError, ValueError):
            ok = False
        if not ok:
            return {"do": "refuse", "why": "bad-line"}
    # 7. secret, as written
    if is_secret(p):
        return {"do": "refuse", "why": "secret"}
    # 8. root, as text
    p = norm(p)
    if not any(under(p, w) or under(p, rr) for w, rr in roots):
        return {"do": "refuse", "why": "unavailable"}
    # 9. resolve, inside the root
    real = resolve_within(p, roots, fs)
    if real is None:
        return {"do": "refuse", "why": "unavailable"}
    # 10. a regular file, with one link
    node = fs.lstat(real) or {"kind": "missing"}
    if node["kind"] != "file":
        return {"do": "refuse", "why": "not-a-file"}
    if int(node.get("links", 1)) > 1:
        return {"do": "refuse", "why": "hard-link"}
    # 11. secret, resolved (a surface also checks the name the file system stores for it)
    if is_secret(real):
        return {"do": "refuse", "why": "secret"}
    # 12. kind
    if node.get("class") in ("binary", "large"):
        return {"do": "refuse", "why": "unreadable"}
    # 13. executable
    low = fold(real)
    if low.endswith(EXEC_EXT) or (node.get("executable") and not low.endswith(DOC_EXT)):
        return {"do": "refuse", "why": "executable"}
    out = {"do": "open", "path": real, "mode": "source" if low.endswith(SOURCE_EXT) else "auto"}
    if "line" in req:
        out["line"] = int(req["line"])
    return out


def main(path):
    doc = json.load(open(path, encoding="utf-8"))
    fs = FS(doc["fs"])
    roots = prepare_roots(doc["roots"], doc["home"], fs)
    bad = []
    if len(roots) != 1:
        bad.append("the fixture's roots must prepare to exactly one, got %s" % roots)
    for c in doc["cases"]:
        got = decide(doc, c, roots)
        if got != c["expect"]:
            bad.append("%s: expected %s, got %s" % (c["case"], c["expect"], got))
    for w in doc.get("windows_paths", []):
        pw = w["path"].strip(" \t")
        got = windows_shape(pw) or ("secret" if is_secret(pw) else None)
        if got != w["why"]:
            bad.append("windows %s: expected %s, got %s" % (w["case"], w["why"], got))
    for w in doc.get("windows_roots", []):
        if win_inside(w["path"], w["root"]) != w["inside"]:
            bad.append("windows root %s" % w["case"])
    for f in doc.get("framework_roots", []):
        got = [rr for _, rr in prepare_roots(f["roots"], doc["home"], fs)]
        if got != f["usable"]:
            bad.append("framework root %s: expected %s, got %s" % (f["case"], f["usable"], got))
    n = sum(len(doc.get(x, [])) for x in ("cases", "windows_paths", "windows_roots", "framework_roots"))
    print("CASES", "ok %d" % n if not bad else "; ".join(bad))
    whys = sorted({c["expect"]["why"] for c in doc["cases"] if c["expect"]["do"] == "refuse"}
                  | {w["why"] for w in doc.get("windows_paths", []) if w["why"]})
    print("WHYS", ",".join(whys))
    print("OPENS", sum(1 for c in doc["cases"] if c["expect"]["do"] == "open"))


if __name__ == "__main__":
    main(sys.argv[1])

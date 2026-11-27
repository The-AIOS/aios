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

SECRET_SEGMENTS = {".ssh", ".gnupg", ".aws", "agent-secrets", ".git", ".docker", ".kube", ".obsidian", ".claude"}
SECRET_NAMES = {".envrc", ".netrc", ".pgpass", ".npmrc", ".pypirc", ".git-credentials", ".dockercfg", ".mcp.json",
                "storage_state.json", "spotify-cache.json", ".dev.vars", "credentials", "kubeconfig"}
SECRET_EXT = (".pem", ".key", ".p12", ".pfx", ".p8", ".kdbx", ".ovpn", ".ppk", ".jks", ".keystore", ".tfstate", ".tfvars")
DATA_EXT = (".json", ".yaml", ".yml", ".toml")
DATA_WORDS = {"token", "credential", "credentials", "oauth", "secret", "secrets", "cookie", "cookies"}
EXEC_EXT = (".exe", ".com", ".bat", ".cmd", ".ps1", ".msi", ".scr", ".app", ".command", ".lnk", ".url", ".webloc",
            ".desktop", ".terminal", ".jar", ".vbs", ".hta", ".reg", ".scpt", ".workflow", ".pkg", ".dmg", ".appimage")
DOC_EXT = (".md", ".markdown", ".txt", ".json", ".yaml", ".yml", ".toml", ".csv", ".log", ".html", ".htm",
           ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf")
SOURCE_EXT = (".html", ".htm", ".xhtml", ".xht", ".shtml", ".mht", ".mhtml")
RESERVED = re.compile(r"(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³]|conin\$|conout\$)", re.I)


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
    if len(segs) > 1 and segs[-2] == "auth" and b.endswith(".json"):
        return True
    if b.endswith(DATA_EXT) and DATA_WORDS & set(re.split(r"[^a-z0-9]+", b.rsplit(".", 1)[0])):
        return True
    return re.match(r"id_(rsa|dsa|ecdsa|ed25519)", b) is not None and not b.endswith(".pub")


def sanitize(name):
    # the surfaces' sessionKey: trim, lower, whitespace to dashes, keep a-z 0-9 and dashes, trim dashes
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
        if seg in (".", "..") or seg.endswith(".") or seg.endswith(" ") or RESERVED.fullmatch(seg.split(".")[0].rstrip(" ")):
            return "bad-path"
    return None


def win_cmp(p):
    return re.sub(r"[\\/]+", "\\\\", p).lower().rstrip("\\")


def win_inside(path, root):
    a, b = win_cmp(path), win_cmp(root)
    return a == b or a.startswith(b + "\\")


def under(p, r):
    return p == r or p.startswith(r.rstrip("/") + "/")


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
        """Full resolution, for the operator's own configured roots only (done once, up front)."""
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
                if hops > 40:
                    return None
                t = n["to"] if n["to"].startswith("/") else posixpath.normpath(posixpath.join(posixpath.dirname(cand), n["to"]))
                queue = [x for x in t.split("/") if x] + queue
                out = []
                continue
            out.append(c)
        return "/" + "/".join(out)


def prepare_roots(doc, fs):
    home = fs.realpath_trusted(doc["home"]) or doc["home"]
    out = []
    for r in doc["roots"]:
        rr = fs.realpath_trusted(r)
        if not rr or rr == "/" or under(home, rr):
            continue   # the file-system root, the home folder or one of its ancestors is never a root
        if under(rr, home) and any(s.startswith(".") for s in rr[len(home):].split("/") if s):
            continue   # nor a folder inside a hidden folder of home (~/.config, ~/.local, ...)
        out.append((r.rstrip("/") or "/", rr))
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
            if hops > 40:
                return None
            t = n["to"] if n["to"].startswith("/") else posixpath.join(cur, n["to"])
            t = posixpath.normpath(t)
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
    if not isinstance(p, str) or any(ch in p for ch in "\x00\r\n") or not p.strip(" \t"):
        return {"do": "refuse", "why": "bad-path"}
    p = p.strip(" \t")
    if p.startswith("~") or not p.startswith("/"):
        return {"do": "refuse", "why": "not-absolute"}
    if any(seg in (".", "..") for seg in p.split("/")):
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
    # 8. roots, as text
    p = re.sub(r"/+", "/", p).rstrip("/") or "/"
    if not any(under(p, w) or under(p, rr) for w, rr in roots):
        return {"do": "refuse", "why": "unavailable"}
    # 9. resolve, inside the roots
    real = resolve_within(p, roots, fs)
    if real is None:
        return {"do": "refuse", "why": "unavailable"}
    # 10. a regular file, with one link
    node = fs.lstat(real) or {"kind": "missing"}
    if node["kind"] != "file":
        return {"do": "refuse", "why": "not-a-file"}
    if node.get("links", 1) > 1:
        return {"do": "refuse", "why": "hard-link"}
    # 11. secret, resolved
    if is_secret(real):
        return {"do": "refuse", "why": "secret"}
    # 12. kind
    if node.get("class") in ("binary", "large"):
        return {"do": "refuse", "why": "unreadable"}
    # 13. executable
    low = real.lower()
    if low.endswith(EXEC_EXT) or (node.get("executable") and not low.endswith(DOC_EXT)):
        return {"do": "refuse", "why": "executable"}
    out = {"do": "open", "path": real, "mode": "source" if low.endswith(SOURCE_EXT) else "auto"}
    if "line" in req:
        out["line"] = int(req["line"])
    return out


def main(path):
    doc = json.load(open(path, encoding="utf-8"))
    roots = prepare_roots(doc, FS(doc["fs"]))
    bad = []
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
    n = len(doc["cases"]) + len(doc.get("windows_paths", [])) + len(doc.get("windows_roots", []))
    print("CASES", "ok %d" % n if not bad else "; ".join(bad))
    whys = sorted({c["expect"]["why"] for c in doc["cases"] if c["expect"]["do"] == "refuse"}
                  | {w["why"] for w in doc.get("windows_paths", []) if w["why"]})
    print("WHYS", ",".join(whys))
    print("OPENS", sum(1 for c in doc["cases"] if c["expect"]["do"] == "open"))


if __name__ == "__main__":
    main(sys.argv[1])

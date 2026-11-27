#!/usr/bin/env python3
"""The one rule for what is an agent, in the framework (#314, #418).

  A file under agents/ is an agent when it is a .md file whose frontmatter `tags` include `agent`
  and whose file name does not start with `_`.

That is the rule the AIOS App and Glass apply in their own code (they do not call this script).
tests/fixtures/agent-rule.cases.json holds the cases all three are held to. Its name is `name:`,
else the file name; `description:` may be empty. A venture keeps reference documents (laws,
glossaries, examples, templates) beside its agents: without the tag they are not agents. A
`reference/` folder and `agent: false` no longer decide that; they only tell the lint below that a
file is a document on purpose.

Modes:
  list-agents.py            one line per agent: name, then path relative to the vault
  list-agents.py --json     [{"name", "description", "path"}]
  list-agents.py --unclear  one line per file to look at, path then what to do: a file with no
                            `agent` tag that is not marked as a document (an agent written by hand
                            is missing from every list until it carries the tag); a tagged file
                            with no description; a tagged file also marked as a document.
                            With --json: [{"path", "why", "fix"}]. Exit 1 when any exist (the
                            bundled-tree CI check), 0 otherwise. /aios:housekeeping proposes the fix.
Read-only. AIOS_ROOT overrides the vault root (default: the root this file lives in).
"""
import json
import os
import re
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

# The surfaces read this file in JavaScript, so the reader below uses JavaScript's meanings on purpose:
# its white space (which includes the byte order mark and not the ASCII separators), `.` that stops at a
# carriage return or a Unicode line separator, and lines split on \n or \r\n only.
WS = " \t\n\x0b\x0c\r\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"
DOT = "[^\n\r\u2028\u2029]"
FM = re.compile(r"^---\r?\n(.*?)\r?\n---", re.S)
TAGS_OPEN = re.compile("^tags:[%s]*$" % WS)
ITEM = re.compile("^[%s]*-[%s]+(%s+)$" % (WS, WS, DOT))
KEY = re.compile("^([A-Za-z0-9_-]+):[%s]*(%s*)$" % (WS, DOT))
TRAIL = re.compile("[%s]+$" % WS)
EDGES = re.compile("^[%s]+|[%s]+$" % (WS, WS))

FIX = {
    "no-tag": "not listed as an agent. If it is one, add `agent` to `tags` in its frontmatter; if it is a document, move it under a reference/ folder or mark it `agent: false`.",
    "no-description": "listed as an agent, with no `description`. Add one: it is what the pickers and the team composer match on.",
    "tagged-document": "tagged `agent` and also marked as a document (under reference/, or `agent: false`). It is listed as an agent; remove the tag or the mark.",
}


def trim(s):
    return EDGES.sub("", s)


def unquote(s):
    """A YAML scalar's quotes and what they escape, as the surfaces read them."""
    if len(s) >= 2 and s[0] == "'" and s.endswith("'"):
        return s[1:-1].replace("''", "'")
    if len(s) >= 2 and s[0] == '"' and s.endswith('"'):
        return s[1:-1].replace('\\"', '"')
    return re.sub(r"^[\"']|[\"']$", "", s)


def frontmatter(path):
    """Top-level scalars by key, plus `tags` as a list (block or inline form)."""
    out = {"tags": []}
    try:
        with open(path, encoding="utf-8-sig", errors="replace", newline="") as fh:   # -sig: a BOM must not hide an agent
            m = FM.match(fh.read())
    except OSError:
        return out
    if not m:
        return out
    in_tags = False
    for raw in re.split(r"\r?\n", m.group(1)):
        line = TRAIL.sub("", raw)
        if TAGS_OPEN.match(line):
            in_tags = True
            continue
        if in_tags:
            item = ITEM.match(line)
            if item:
                out["tags"].append(unquote(trim(item.group(1))))
                continue
            in_tags = False   # dedented out of the tags block
        kv = KEY.match(line)
        if not kv:
            continue
        key, value = kv.group(1).lower(), unquote(trim(kv.group(2)))   # quotes first, then the list's brackets
        if key == "tags":
            out["tags"] += [t for t in (unquote(trim(x)) for x in re.sub(r"^\[|\]$", "", value).split(",")) if t]
        else:
            out[key] = value
    return out


def md_files(base):
    """(relative folder, file name) for every regular .md file under base, following links.

    A folder reached twice through different links is listed under both paths, as the surfaces list
    it. Only a link back to one of its own ancestors is not followed: that is a loop."""
    def walk(d, rel, ancestors):
        try:
            st = os.stat(d)
            names = sorted(os.listdir(d))
        except OSError:
            return
        me = (st.st_dev, st.st_ino)
        if me in ancestors:
            return
        subdirs = []
        for n in names:
            p = os.path.join(d, n)
            if os.path.isdir(p):
                subdirs.append(n)
            elif n.endswith(".md") and os.path.isfile(p):   # isfile: a broken link is not a file
                yield rel, n
        for n in subdirs:
            for row in walk(os.path.join(d, n), rel + "/" + n, ancestors | {me}):
                yield row
    return walk(base, "agents", frozenset())


def scan(root):
    """Yield (kind, relpath, fm, why) for every .md under agents/ whose name does not start with `_`.

    kind is agent, document or unclear. why is "" or a key of FIX: an agent can carry one too.
    For an agent, fm["name"] and fm["description"] are always set."""
    for rel_dir, f in md_files(os.path.join(root, "agents")):
        if f.startswith("_"):
            continue
        rel = rel_dir + "/" + f
        fm = frontmatter(os.path.join(root, rel))
        marked = "reference" in rel_dir.split("/") or fm.get("agent", "").lower() == "false"
        if "agent" in [t.lower() for t in fm["tags"]]:
            fm["name"] = fm.get("name") or f[:-3]
            fm["description"] = fm.get("description") or ""
            yield "agent", rel, fm, ("tagged-document" if marked else "" if fm["description"] else "no-description")
        elif marked or f == "README.md":
            yield "document", rel, fm, ""
        else:
            yield "unclear", rel, fm, "no-tag"


def classify(root):
    """Yield (kind, relpath, fm): what team-plan.py reads."""
    for kind, rel, fm, _why in scan(root):
        yield kind, rel, fm


def main(argv):
    root = os.environ.get("AIOS_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))  # hooks/agents/ -> root
    rows = list(scan(root))
    if "--unclear" in argv:
        unclear = [(r, why) for _k, r, _fm, why in rows if why]
        if "--json" in argv:
            print(json.dumps([{"path": r, "why": why, "fix": FIX[why]} for r, why in unclear], ensure_ascii=False))
        else:
            for r, why in unclear:
                print("%s\t%s" % (r, FIX[why]))
        return 1 if unclear else 0
    agents = [(fm["name"], fm["description"], r) for k, r, fm, _why in rows if k == "agent"]
    if "--json" in argv:
        print(json.dumps([{"name": n, "description": d, "path": p} for n, d, p in agents], ensure_ascii=False))
    else:
        for n, _d, p in agents:
            print("%s\t%s" % (n, p))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

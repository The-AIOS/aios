#!/usr/bin/env python3
"""The one rule for what is an agent, for every surface that lists them (#314).

A surface used to list `agents/**/*.md`, but a venture keeps reference documents beside its agents
(laws, glossaries, examples, templates). In one live vault 74 of 130 such files were documents, so
the AIOS App's agent check and its Ask panel disagreed about what an agent is. The rule:

  A file under agents/ is an agent when it is a .md file with `name:` and `description:` in its
  frontmatter, and it is NOT `_index.md` or `README.md`, NOT under a `reference/` folder, and NOT
  marked `agent: false`.

Modes:
  list-agents.py            one line per agent: name, then path relative to the vault
  list-agents.py --json     [{"name", "description", "path"}], for the App, Glass and hooks
  list-agents.py --unclear  files that are neither agents nor clearly documents (no frontmatter
                            agent fields, not under reference/, not marked agent: false): what
                            /aios:housekeeping proposes to move under reference/, mark, or complete.
                            Exit 1 when any exist (the bundled-tree CI check), 0 otherwise.
Read-only. AIOS_ROOT overrides the vault root (default: the root this file lives in).
"""
import json
import os
import re
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

SKIP_FILES = {"_index.md", "README.md"}
FM = re.compile(r"^---\r?\n(.*?)\r?\n---", re.S)


def frontmatter(path):
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as fh:   # -sig: a BOM must not hide an agent
            m = FM.match(fh.read(65536))   # the whole frontmatter: a long description must not hide an agent
    except OSError:
        return {}
    out = {}
    if m:
        for line in m.group(1).splitlines():
            k, sep, v = line.partition(":")
            if sep and k and not k.startswith((" ", "\t", "-")):
                out[k.strip()] = v.strip().strip("'\"")
    return out


def classify(root):
    """Yield (kind, relpath, fm) for every .md under agents/: kind is agent, document or unclear."""
    base = os.path.join(root, "agents")
    seen = set()
    for d, dirs, files in os.walk(base, followlinks=True):
        st = os.stat(d)
        if (st.st_dev, st.st_ino) in seen:   # a symlink cycle: walk each real folder once
            dirs[:] = []
            continue
        seen.add((st.st_dev, st.st_ino))
        dirs.sort()
        rel_dir = os.path.relpath(d, root).replace("\\", "/")
        in_reference = "/reference" in "/" + rel_dir + "/" and any(p == "reference" for p in rel_dir.split("/"))
        for f in sorted(files):
            if not f.endswith(".md") or f in SKIP_FILES:
                continue
            rel = rel_dir + "/" + f
            fm = frontmatter(os.path.join(d, f))
            if in_reference or fm.get("agent", "").lower() == "false":
                yield "document", rel, fm
            elif fm.get("name") and fm.get("description"):
                yield "agent", rel, fm
            else:
                yield "unclear", rel, fm


def main(argv):
    root = os.environ.get("AIOS_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))  # hooks/agents/ -> root
    rows = list(classify(root))
    if "--unclear" in argv:
        unclear = [r for k, r, _ in rows if k == "unclear"]
        for r in unclear:
            print(r)
        return 1 if unclear else 0
    agents = [(fm["name"], fm["description"], r) for k, r, fm in rows if k == "agent"]
    if "--json" in argv:
        print(json.dumps([{"name": n, "description": d, "path": p} for n, d, p in agents], ensure_ascii=False))
    else:
        for n, _d, p in agents:
            print("%s\t%s" % (n, p))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

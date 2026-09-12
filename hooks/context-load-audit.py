#!/usr/bin/env python3
"""context-load-audit — did a spawned worker actually load operator context?

WHY THIS IS A HOOK AND NOT PROSE IN A COMMAND FILE.
`CLAUDE.md` tells a worker to load context and nothing reports when it doesn't;
the failure is silent by construction — the worker still answers and still sounds
right. So /aios:housekeeping measures it. But a measurement described in prose is
re-implemented by whoever runs it, and the obvious implementation is wrong in a
specific, reproducible way (see CD-RESOLUTION below): it was written that way
once and reported three workers at zero that had in fact read the floor. A check
that under-reports is worse than no check, because its clean answer is trusted.
So the instrument ships as code, and the command calls it.

WHAT IT READS. `~/.claude/projects/*/<sessionId>.jsonl` — the transcript. Only
`tool_use` events, never prose and never `tool_result`: a transcript mentions
context paths constantly, and only a tool call is evidence a file was opened.

COMPACTION DOES NOT AFFECT IT. Compaction rewrites the model's context window;
the transcript on disk is append-only. Measured on a live session with 8
compaction events: all 10,241 tool_use records spanning seven weeks were still
present. The audit therefore sees what a session DID, not what it still
remembers — which is the question being asked.

CD-RESOLUTION, the bug this exists to not repeat. A worker frequently does
`cd "<vault>/00 - notes/context/observed" && grep '^### ' antifragile.md …`.
Matching only `context/(declared|observed)/<file>.md` misses every one of those,
because after the `cd` the paths are bare. Commands are therefore scanned for a
`cd` into the context tree, and bare context filenames in such a command count.

DEPTH. Reading the `###` titles of a file is the floor; reading the file is the
full load. They are counted separately, because a floor that silently degrades
into nothing looks identical to a floor that is firing if you only count files.

Usage:  context-load-audit.py [--min-tools N] [--cap N] [--json] [--session SID]
"""
import argparse
import glob
import json
import os
import re
import sys

# Windows consoles are cp1252: a print() carrying an em dash raises UnicodeEncodeError
# and the hook does NOT RUN -- the failure is absence, not a mangled glyph.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

CONTEXT_FILES = [
    "about_me", "personal_voice", "working_style", "about_business",
    "psychometric-profile", "role-expectations", "coding_style",
    "coding-practices", "thinker-collaborations",
    "antifragile", "patterns", "preferences", "growth", "profile",
    "ecosystem", "business", "session-insights", "vault-routine",
]
PATH_RE = re.compile(r"context/(?:declared|observed)/([a-z_\-]+)\.md")
NAME_RE = re.compile(r"\b(" + "|".join(map(re.escape, CONTEXT_FILES)) + r")(?:\.md)?\b")
CD_INTO_CONTEXT = re.compile(r"cd\s+[\"']?[^\"'&|;]*context/(declared|observed)")
CTX_MENTION = re.compile(r"context/(?:declared|observed)|notes/context")
TITLES_ONLY = re.compile(r"grep\s+[^|]*'?\^#{2,3}\s|head\s+-\d+|--?l\b")
PRIMARY_HINT = re.compile(r"^(buddai|sarah|aios-|update$|vault-sync)", re.I)


def tool_inputs(path, cap):
    """Yield (tool_name, serialized_input) for the first `cap` tool_use events."""
    n = 0
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if '"tool_use"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue

            def walk(o):
                if isinstance(o, dict):
                    if o.get("type") == "tool_use":
                        yield o.get("name", ""), json.dumps(o.get("input", {}))[:4000]
                    for v in o.values():
                        yield from walk(v)
                elif isinstance(o, list):
                    for v in o:
                        yield from walk(v)

            for item in walk(rec):
                yield item
                n += 1
                if cap and n >= cap:
                    return


def audit(path, cap):
    read_full, read_titles, tools = set(), set(), 0
    for _name, inp in tool_inputs(path, cap):
        tools += 1
        hits = {m.group(1) for m in PATH_RE.finditer(inp)}
        # CD-RESOLUTION: after a cd into the context tree, bare filenames are context files.
        if CD_INTO_CONTEXT.search(inp) or CTX_MENTION.search(inp):
            hits |= {m.group(1) for m in NAME_RE.finditer(inp)}
        if not hits:
            continue
        (read_titles if TITLES_ONLY.search(inp) else read_full).update(hits)
    return tools, read_full, read_titles - read_full


def agent_name(path):
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if '"agent-name"' in line:
                m = re.search(r'"agentName":"([^"]*)"', line)
                if m:
                    return m.group(1)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-tools", type=int, default=20,
                    help="ignore sessions below this many tool calls (probes never had work to contextualise)")
    ap.add_argument("--cap", type=int, default=120,
                    help="how many tool calls from the start to scan; 0 = whole transcript")
    ap.add_argument("--session", help="audit one sessionId prefix instead of sweeping")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    root = os.path.expanduser("~/.claude/projects")
    pattern = f"{root}/*/{a.session}*.jsonl" if a.session else f"{root}/*/*.jsonl"
    rows = []
    for f in glob.glob(pattern):
        if os.path.getsize(f) < 2000 and not a.session:
            continue
        name = agent_name(f)
        if not name:
            continue
        tools, full, titles = audit(f, a.cap)
        if tools < a.min_tools and not a.session:
            continue
        rows.append({
            "name": name, "primary": bool(PRIMARY_HINT.match(name)),
            "tools": tools, "full": sorted(full), "titles_only": sorted(titles),
            "total": len(full) + len(titles),
        })

    if a.json:
        print(json.dumps(rows, indent=2))
        return 0

    primaries = [r for r in rows if r["primary"]]
    workers = [r for r in rows if not r["primary"]]

    # CONTROL FIRST. Primaries run the full ritual; if they do not score, the instrument is
    # broken and every worker number below it is untrustworthy. Say so instead of reporting.
    # ONE rule: findings require a validated control. Both "primaries exist but none
    # scored" and "no primary found at all" mean the same thing -- the instrument is
    # unvalidated -- and in both cases a worker reading nothing is indistinguishable
    # from the detector seeing nothing. Reporting a zero without a control is the
    # failure this whole hook exists to avoid, one level up.
    scored = sum(1 for r in primaries if r["total"] > 0)
    if not primaries:
        print("ABORT: no primary session found, so the detector has no control.")
        print("       A worker reading nothing and a detector seeing nothing are the same")
        print("       output here. Not reporting findings from an unvalidated instrument.")
        return 2
    print(f"control — primary sessions: {scored}/{len(primaries)} loaded context")
    if scored == 0:
        print("  ABORT: no primary session shows a context read. The detector is broken,")
        print("         not the workers. Fix it before trusting anything below.")
        return 2

    if not workers:
        print("no spawned workers met the threshold")
        return 0

    buckets = {"0": 0, "1-2": 0, "3-6": 0, "7+": 0}
    for r in workers:
        t = r["total"]
        buckets["0" if t == 0 else "1-2" if t <= 2 else "3-6" if t <= 6 else "7+"] += 1
    print(f"\nspawned workers with >= {a.min_tools} tool calls: {len(workers)}")
    for k, v in buckets.items():
        print(f"  {k:>4} context files: {v}")

    zero = [r for r in workers if r["total"] == 0]
    if zero:
        print("\nloaded NOTHING despite doing real work:")
        for r in sorted(zero, key=lambda r: -r["tools"]):
            print(f"  {r['name'][:32]:32s} {r['tools']:4d} tool calls")
        print("\n  These are the ones to look at. Report only — decide per worker whether the")
        print("  task genuinely needed no operator context.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

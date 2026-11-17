#!/usr/bin/env python3
"""Hook G: point a session at the one agent a prompt clearly fits (#317).

The suggest-agent skill only ran when a session decided by itself to open it, and live probes
showed it never did mid-session: an invoice question got a good answer and no agent. This
UserPromptSubmit hook matches the prompt against the agents index (agents/_index.md, plus
agents/custom/_index.md) by each agent's name, its `aliases:` and the index's match keywords. On
one clear winner the session is not already wearing, it adds one line of context naming the agent
and pointing at the skill. The SKILL still decides: its rules (fits clearly, at most one, nothing
when two fit, INTENT.md's hats row) can say no, and a wrong suggestion is worse than none.

Never blocks, never prints anything else, exits 0 on every path. Silent when: the prompt is short
or a slash command, nothing matches, two agents tie, or the transcript's last wearing line already
names the winner. Reads stdin as Claude Code's hook JSON ({"prompt", "transcript_path", ...}).
"""
import json
import os
import re
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

ROOT = os.environ.get("AIOS_ROOT") or os.path.join(os.path.expanduser("~"), "aios")
ROW = re.compile(r"^\|\s*\[\[([a-z0-9-]+)\]\]\s*\|([^|]*)\|([^|]*)\|")
WEARING = re.compile(r"Wearing agent: ([a-z0-9-]+)\.")
MIN_WORDS = 4
# Keywords too generic to name one agent on their own: they still count beside a specific one.
WEAK = {"strategy", "review", "pitch", "scope", "terms", "framework", "report", "plan", "design",
        "research", "build", "offer", "deal", "content", "growth", "update", "analysis", "check",
        "launch", "ship"}


def load_agents(root):
    """{name: set of match terms} from the indexes, plus each agent file's aliases."""
    agents = {}
    for idx in ("agents/_index.md", "agents/custom/_index.md"):
        try:
            text = open(os.path.join(root, idx), encoding="utf-8").read()
        except OSError:
            continue
        for line in text.splitlines():
            m = ROW.match(line)
            if not m:
                continue
            name, _purpose, kw = m.group(1), m.group(2), m.group(3)
            terms = agents.setdefault(name, set())
            terms.add(name.replace("-", " "))
            for k in kw.split(","):
                k = k.strip().lower().strip("`*_")
                if 2 < len(k) <= 40:
                    terms.add(k)
    for base, _dirs, files in os.walk(os.path.join(root, "agents"), followlinks=True):
        for f in files:
            name = f[:-3]
            if not f.endswith(".md") or name not in agents:
                continue
            try:
                head = open(os.path.join(base, f), encoding="utf-8").read(1500)
            except OSError:
                continue
            m = re.search(r"^aliases:\s*\[([^\]]*)\]", head, re.M)
            if m:
                for a in m.group(1).split(","):
                    a = a.strip().strip("'\"").lower()
                    if a:
                        agents[name].add(a)
    return agents


def score(prompt, terms):
    """Strength of the evidence: a name, alias or multi-word phrase counts 2, a specific word 1,
    a weak word 0 alone. A term matches as whole words, with a plural s/es allowed."""
    total, strong = 0, False
    for t in terms:
        if re.search(r"(?<![a-z0-9])" + re.escape(t) + r"(?:e?s)?(?![a-z0-9])", prompt):
            if " " in t or "-" in t:
                total += 2; strong = True
            elif t in WEAK:
                total += 0.5
            else:
                total += 1; strong = True
    return total if strong else 0


def wearing(transcript_path):
    """The agent named by the transcript's last wearing line, or None."""
    try:
        with open(transcript_path, "rb") as fh:
            fh.seek(0, 2); size = fh.tell(); fh.seek(max(0, size - 400_000))
            tail = fh.read().decode("utf-8", "replace")
    except (OSError, TypeError):
        return None
    hits = WEARING.findall(tail)
    return hits[-1] if hits else None


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    # Only inside the vault, as Hook E: a session in another repo (a client's, say) must not be pointed
    # at an agent that would pull the operator's voice and context into it.
    cwd = data.get("cwd") or os.getcwd()
    root = os.path.normcase(os.path.realpath(ROOT))      # case-insensitive on Windows, as Hook E
    here = os.path.normcase(os.path.realpath(cwd))
    if here != root and not here.startswith(root + os.sep):
        return 0
    prompt = (data.get("prompt") or "").strip()
    if prompt.startswith("/") or len(prompt.split()) < MIN_WORDS:
        return 0
    low = prompt.lower()
    ranked = sorted(((score(low, terms), name) for name, terms in load_agents(ROOT).items()), reverse=True)
    if not ranked or ranked[0][0] < 1:
        return 0
    if len(ranked) > 1 and ranked[1][0] >= ranked[0][0]:
        return 0  # two agents fit about equally: suggest neither (the skill's own rule)
    name = ranked[0][1]
    if wearing(data.get("transcript_path")) == name:
        return 0
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            "This request may fit the `%s` agent (agents index). Load the `suggest-agent` skill and "
            "follow it: it decides whether to suggest or wear it (and may decide not to), and writes "
            "the fixed `Suggested agent:` / `Wearing agent:` line." % name),
    }}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)

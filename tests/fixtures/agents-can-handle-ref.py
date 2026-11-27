#!/usr/bin/env python3
"""Reference reading of the daily note's `## Agents can handle` section.

The App and Glass implement this rule in TypeScript; this repo cannot import
that, so this file states the rule once, in the language its tests run in. The
shared cases file beside it (agents-can-handle.cases.json) is what all of them
answer to: this reference, the App's parser and Glass's parser each run every
case and must produce the same suggestions.

The rule, in the order it is applied to each line of the section (from the
`## ... Agents can handle` heading to the next `## ` heading):

 1. Only list items (`- ` or `* `) are tasks. The count header and the footer
    are prose, whatever they mention.
 2. A checked item (`[x]`), a struck title (`- 🤖 ~~...`) and a line stamped
    🚀 (already handed to an agent) are skipped.
 3. The ROUTE is what follows the last ` _(→` on the line. When the line has
    one, the agent and the command are read from the route and nowhere else,
    so a wikilink or a backticked command in the task text never binds.
    A line with no ` _(→` is read whole (older notes).
 4. Agent: the wikilinks that follow `agent:`. A wikilink with no `agent:`
    before it is a link, not a target.
 5. Command: the first backticked `/command`, with an optional argument inside
    the same backticks. The slash and the backticks are both required.
 6. A line with neither is skipped. An agent wins over a command.
 7. The task is the text before the route, without the bullet and the 🤖. If
    it opens with a **bold** span, the task is that span (older notes).
 8. A task whose identity matches a line marked done anywhere in the note
    (`[x]`, or struck) is skipped.
 9. A command's argument is what follows it inside the backticks; failing
    that, a URL on the line (a markdown link's target first).

Usage:  agents-can-handle-ref.py <cases.json>     run every case, exit 1 on a miss
        agents-can-handle-ref.py --first-wikilink <cases.json>
                                                  the same with rule 3-4 replaced by
                                                  "the first wikilink on the line is
                                                  the agent" (the control: the cases
                                                  must catch it)
"""
import json
import re
import sys

A = re.ASCII
ROBOT, ROCKET = "\U0001F916", "\U0001F680"
WIKI = re.compile(r"\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]")
CMD = re.compile(r"`(/[a-z][\w:-]*)(?:[ \t]+([^`]*?))?[ \t]*`", re.I | A)
ROUTE = " _(→"
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿←-⇿⬀-⯿️]")


def identity(s):
    s = re.sub(r"^\s*[-*]\s*", "", s)
    s = re.sub(r"\[[ xX]\]", "", s)
    s = s.replace("~~", "")
    s = re.sub(r"\[\[([^\]|]+?)(?:\|([^\]]+))?\]\]", lambda m: m.group(2) or m.group(1), s)
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"[`*_#>]", "", s)
    s = re.sub(r"\b\d{1,2}:\d{2}\b", "", s, flags=A)
    s = re.sub(r"\b\d{1,2}\s?(?:am|pm)\b", "", s, flags=A | re.I)
    s = EMOJI.sub("", s)
    return re.sub(r"\s+", " ", s).strip().lower()


def done_identities(lines):
    out = []
    for line in lines:
        if re.match(r"^\s*[-*]\s*\[[xX]\]", line) or re.search(r"~~[^~]+~~", line):
            i = identity(line)
            if len(i) >= 4:
                out.append(i)
    return out


def parse(md, first_wikilink=False):
    lines = re.split(r"\r?\n", md)
    done = done_identities(lines)
    out, inside = [], False
    for line in lines:
        if re.match(r"^##\s+.*Agents can handle", line, re.I):
            inside = True
            continue
        if inside and re.match(r"^##\s", line):
            break
        if not inside or not re.match(r"^\s*[-*]\s", line):
            continue
        if re.match(r"^\s*[-*]\s*\[[xX]\]", line):
            continue
        if re.match(r"^\s*[-*]\s*(?:%s\s*)*~~" % ROBOT, line):
            continue
        if ROCKET in line:
            continue
        cut = line.rfind(ROUTE)
        route = line[cut + len(ROUTE):] if cut >= 0 else line
        if first_wikilink:
            agents = [m.strip() for m in WIKI.findall(line)]
            cmd = CMD.search(line)
        else:
            at = re.search(r"\bagent:", route, re.I | A)
            agents = [m.strip() for m in WIKI.findall(route[at.end():])] if at else []
            cmd = CMD.search(route)
        if not agents and not cmd:
            continue
        label = line[:cut] if cut >= 0 else line
        label = re.sub(r"^\s*[-*]\s*(?:%s\s*)*" % ROBOT, "", label).strip()
        bold = re.match(r"^\*\*(.+?)\*\*", label)
        task = bold.group(1).strip() if bold else label
        tid = identity(task)
        if len(tid) >= 6 and any(d == tid or tid in d for d in done):
            continue
        sug = {"task": task, "agents": agents}
        if not agents and cmd:
            sug["command"] = cmd.group(1)
            arg = (cmd.group(2) or "").strip()
            if not arg:
                link = re.search(r"\]\((https?://[^)]+)\)", line)
                bare = re.search(r"https?://\S+", line)
                arg = link.group(1) if link else (re.sub(r"[)*_.,]+$", "", bare.group(0)) if bare else "")
            if arg:
                sug["arg"] = arg
        out.append(sug)
    return out


def main(argv):
    first = "--first-wikilink" in argv
    path = [a for a in argv if not a.startswith("--")][0]
    with open(path, encoding="utf-8") as f:
        cases = json.load(f)["cases"]
    bad = 0
    for c in cases:
        got = parse("\n".join(c["note"]), first_wikilink=first)
        want = c["expect"]["suggestions"]
        if got != want or len(got) != c["expect"]["count"]:
            bad += 1
            print("MISS %s\n     want %s\n     got  %s" % (
                c["case"], json.dumps(want, ensure_ascii=False), json.dumps(got, ensure_ascii=False)))
    print("%d cases, %d missed" % (len(cases), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Find docs that re-enumerate the Google APIs an operator must enable (AI-126).

The API set is derived from connector.json's --permissions. Any doc that also
lists it is a second copy, and the copies drifted: one sent operators to enable
a Chat API nothing requested, another omitted three services entirely, and a
third disagreed with both.

Two things make this harder than grepping for a literal, and each one is a way
the drift actually hid:

  1. The worst copy was PROSE -- "the core seven (Drive, Docs, Sheets, Slides,
     Calendar, Tasks, Gmail) plus People API for contacts" -- so a search for
     `*.googleapis.com` would not have found it at all.
  2. In another the instruction and the list were on DIFFERENT lines: an
     "Enable APIs" step followed by a blockquote naming the services. A
     per-line check misses that, so this scans a small window.

The discriminator is enable-language. A line that names services without it is
a value statement ("enables Calendar, Tasks, Drive ...") or diagnostic advice
("`list_spreadsheets` goes through the Drive API, so it passes even when Sheets
and Docs are disabled") -- both legitimate, neither a list to maintain. Note
that `disabled` deliberately does not match: that sentence describes a symptom,
it does not hand anyone a checklist.
"""
import glob
import re
import sys

NAMES = ["Drive", "Docs", "Sheets", "Slides", "Calendar", "Tasks", "Gmail",
         "People", "Forms", "Chat", "Contacts", "Apps Script", "Custom Search"]
TARGETS = ["SETUP.md", "README.md", "CHEATSHEET.md", "TOOLS.md"]
WINDOW = 3

# An INSTRUCTION puts its verb next to its object: "Enable the matching Google
# API", "needs the matching nine APIs enabled". Prose that merely happens to use
# both words does not -- "the Tasks source is enabled but never queried [...] get
# the ID from the Tasks API" has 150 characters between them and is a note about
# a different thing entirely. Requiring proximity, in either order, is what keeps
# this guard off correct text; a guard that fires on correct text gets switched
# off, which is worse than not having it.
INSTRUCTION_RE = re.compile(
    r"[Ee]nabl\w*.{0,40}?\bAPIs?\b" r"|" r"\bAPIs?\b.{0,40}?[Ee]nabl\w*")


def names_in(text):
    return sum(1 for s in NAMES if re.search(r"\b%s\b" % s, text))


hits = []
for f in TARGETS + sorted(glob.glob("mcps/google-workspace-mcp/*.md")):
    try:
        lines = open(f, encoding="utf-8").read().split("\n")
    except OSError:
        continue
    for i in range(len(lines)):
        chunk = " ".join(lines[i:i + WINDOW])   # one line, so proximity spans the window
        if INSTRUCTION_RE.search(chunk) and names_in(chunk) >= 3:
            hits.append("%s:%d" % (f, i + 1))
            break  # one report per file is enough to fail the build

print(" ".join(hits))
sys.exit(0)

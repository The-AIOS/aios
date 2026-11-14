#!/usr/bin/env bash
# suggest-agent (#299): the model suggests the one agent that fits, in one fixed line the AIOS App
# parses, and acts only on a yes. Checks: every bundled agent has a row in agents/_index.md (an
# agent missing there is one the skill can never suggest); the skill's example line matches the
# pattern it publishes, and malformed lines do not; the skill keeps its rules; CLAUDE.md routes hat
# changes through it. Usage: bash tests/suggest-agent.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
python3 - <<'PY'
import glob, os, re, sys
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("suggest-agent")
S = "skills/aios/suggest-agent/SKILL.md"
skill = open(S, encoding="utf-8").read() if os.path.isfile(S) else ""
check("the skill ships at " + S, bool(skill))

# 1. Every bundled agent is findable in the index (a wikilinked row or a `name` — bullet).
idx = open("agents/_index.md", encoding="utf-8").read()
missing = []
for p in glob.glob("agents/aios/**/*.md", recursive=True):
    n = os.path.basename(p)[:-3]
    if n.startswith("_") or n == "README":
        continue
    if not (re.search(r"\[\[" + re.escape(n) + r"(\||\]\])", idx) or re.search(r"^- `" + re.escape(n) + r"` —", idx, re.M)):
        missing.append(n)
check("every bundled agent has a row in agents/_index.md" + (" (missing: %s)" % ", ".join(missing) if missing else ""), not missing)

# 2. The line: the example in the skill matches the pattern the skill publishes for surfaces.
pat = re.search(r"```\n(\^Suggested agent: .*\$)\n```", skill)
check("the skill publishes the parse pattern", pat is not None)
rx = re.compile(pat.group(1)) if pat else None
ex = re.search(r"```\n(Suggested agent: [^\n]+)\n```", skill)
check("the skill shows one example line", ex is not None)
good = ["Suggested agent: accountant (invoices and bookkeeping). Wear it here, or open it as its own session?",
        "Suggested agent: security-engineer (auth review). Wear it here, or open it as its own session?"]
bad = ["**Suggested agent: accountant (invoices). Wear it here, or open it as its own session?**",
       "Suggested agent: `accountant` (invoices). Wear it here, or open it as its own session?",
       "Suggested agent: Accountant (invoices). Wear it here, or open it as its own session?",
       "Suggested agents: accountant, lawyer (contracts). Wear it here, or open it as its own session?",
       "Suggested agent: accountant. Wear it here, or open it as its own session?"]
check("the example line matches the published pattern", bool(rx and ex and rx.match(ex.group(1))))
check("well-formed lines match", bool(rx) and all(rx.match(g) for g in good))
check("bold, backticks, capitals, two agents or no reason do not match", bool(rx) and not any(rx.match(b) for b in bad))
m = rx.match(good[1]) if rx else None
check("the pattern captures the agent name", bool(m) and m.group(1) == "security-engineer")

# 2b. The wearing line: written whenever a hat goes on; the App's current-hat chip reads the last one.
wp = re.search(r"```\n(\^Wearing agent: .*\$)\n```", skill)
check("the skill publishes the wearing-line pattern", wp is not None)
wrx = re.compile(wp.group(1)) if wp else None
wex = re.search(r"```\n(Wearing agent: [^\n]+)\n```", skill)
check("the wearing example matches its pattern", bool(wrx and wex and wrx.match(wex.group(1))))
check("wearing lines: well-formed match, malformed do not", bool(wrx) and wrx.match("Wearing agent: deck-builder.")
      and not any(wrx.match(b) for b in ["**Wearing agent: accountant.**", "Wearing agent: accountant", "Wearing agent: Accountant.", "Now wearing agent: accountant."]))
check("a yes to here writes the wearing line", "write the wearing line" in skill)

# 3. The rules that make a suggestion safe.
check("suggests at most one, and nothing when none fits", "at most one" in skill.lower() and "worse than none" in skill)
check("never opens or loads without a yes", re.search(r"never (opens|loads)", skill, re.I) is not None and "yes" in skill)
check("reads the index every time, so new agents need no edit", "every time" in skill and "agents/_index.md" in skill)
check("opening goes through the spawn inbox, never spawn", "spawn inbox" in skill and "never by calling `spawn`" in skill)

# 4. CLAUDE.md routes hat changes through the same line.
claude = open("CLAUDE.md", encoding="utf-8").read()
ident = claude.split("## Identity & Greeting", 1)[-1].split("\n## ", 1)[0]
check("CLAUDE.md § Identity sends hat changes through suggest-agent", "suggest-agent" in ident)
check("CLAUDE.md's greeting writes the wearing line", "wearing line" in ident)
check("the skills index lists it", "`suggest-agent`" in open("skills/_index.md", encoding="utf-8").read())
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY

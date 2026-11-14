#!/usr/bin/env bash
# Session hats (#307): a session name finds its agent (its "hat") by five rungs, in order, and the
# pieces that feed them stay in step: agent aliases are unique, the project template carries the
# Hats row, the examples the docs give actually resolve, and the CHANGELOG offers the row to
# existing vaults. Usage: bash tests/session-hats.test.sh [repo-root]. Written for bash 3.2.
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

print("session-hats")
claude = open("CLAUDE.md", encoding="utf-8").read()

# 1. Identity step 2 lists the five rungs, in this order, inside § Identity & Greeting.
ident = claude.split("## Identity & Greeting", 1)[-1].split("\n## ", 1)[0]
rungs = ["**Exact:**", "**In the name:**", "**Project:**", "**Fuzzy:**", "**None:**"]
pos = [ident.find(r) for r in rungs]
check("Identity has all five rungs", all(p >= 0 for p in pos))
check("the rungs are in order: exact, in the name, project, fuzzy, none", all(p >= 0 for p in pos) and pos == sorted(pos))
check("the project rung reads the note's Hats row and aliases", "`Hats`" in ident and "`aliases:`" in ident)
check("the project rung tries the whole name before its first word", "the name (else its first word)" in ident)
check("the session says which hat, and changes hat with /aios:agent", "which hat" in ident and "/aios:agent {name}" in ident)
check("Spawning Sessions asks for role-first names", "**Name it role-first:**" in claude and "{hat-or-kind}-{subject}" in claude)
check("the Current State field list names Hats", re.search(r"Current State table contains\*\* \(\d+ fields\): `Hats`", claude) is not None)

# 2. Agents: names and their aliases (kind words).
names, owner = set(), {}
dupes = []
for p in glob.glob("agents/**/*.md", recursive=True):
    if os.path.basename(p).startswith("_"): continue
    head = open(p, encoding="utf-8").read().split("\n---", 1)[0]
    m = re.search(r"^name:\s*'?([a-z0-9-]+)", head, re.M)
    if not m: continue
    names.add(m.group(1))
    a = re.search(r"^aliases:\s*\[([^\]]*)\]", head, re.M)
    for w in (a.group(1).split(",") if a else []):
        w = w.strip().strip("'\"")
        if not w: continue
        if w in owner: dupes.append(w)
        owner[w] = m.group(1)
check("at least one agent declares aliases", len(owner) > 0)
check("every alias belongs to one agent only", not dupes)
check("no alias shadows another agent's name", not (set(owner) & names))

def resolve(n):
    """Rungs 1-2 only: the deterministic part."""
    if n in names: return n
    for k in range(n.count("-"), 0, -1):          # longest leading part first
        lead = "-".join(n.split("-")[:k])
        if lead in names: return lead
        if lead in owner: return owner[lead]
    parts = n.split("-")
    for k in range(1, len(parts)):                 # then the end
        tail = "-".join(parts[k:])
        if tail in names: return tail
        if tail in owner: return owner[tail]
    return None

# 3. The examples the docs give resolve to the agent they claim.
examples = {"accountant-acme": "accountant", "acme-consultant": "consultant",
            "deck-launch": "deck-builder", "security-engineer-app": "security-engineer",
            "review-auth": "code-reviewer"}
for n, want in examples.items():
    check("example %s -> %s" % (n, want), resolve(n) == want)
check("the start wins over the end", resolve("accountant-consultant") == "accountant")
check("a name with no agent in it falls through", resolve("acme-site") is None)
docs = claude + open("agents/_index.md", encoding="utf-8").read() + \
       open("skills/aios/orchestration-ladder/SKILL.md", encoding="utf-8").read()
for n in ("accountant-acme", "acme-consultant", "deck-launch"):
    check("the docs use example %s" % n, n in docs)

# 4. The project template carries the Hats row and aliases; the agent template carries aliases.
tpl = open("templates/aios/project-template.md", encoding="utf-8").read()
check("project template has a Hats row in Current State", re.search(r"^\| Hats \|", tpl, re.M) is not None)
check("project template frontmatter has aliases:", re.search(r"^aliases:", tpl.split("\n---", 1)[0], re.M) is not None)
check("agent template offers aliases:", "aliases:" in open("templates/aios/agent-template.md", encoding="utf-8").read())

# 5. Existing vaults are offered the row by the CHANGELOG, by state.
cl = open("CHANGELOG.md", encoding="utf-8").read()
check("the CHANGELOG offers Hats rows to existing project notes", "no `Hats` row" in cl and "begins with `active`" in cl and "the whole name, then its first word" in cl)

print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY

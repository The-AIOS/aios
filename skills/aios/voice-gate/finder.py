#!/usr/bin/env python3
"""voice-gate candidate finder: the same pattern pass on every run, so runs can be compared.

It points at places a draft MIGHT carry an AI-writing habit. It is never the score: the skill's
Step 2 read decides which candidates are real, and finds the ones a pattern cannot. What this
fixes is comparability: one set of patterns, versioned, so two densities taken with the same
finder version differ only because of the writing or the read (#271).

Usage:  python3 finder.py <file> [<file> ...] [--json]
Prints the finder version first, then one line per candidate, then a summary per file.
Never counted: front matter, fenced code, inline code spans, blockquotes and text in quotation
marks (the skill: quoted material is never evidence). Words are counted over the prose that is
left once front matter and code are removed.
"""
import hashlib
import json
import re
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

VERSION = "1"

# (id, category, regex). Case-insensitive. Edit a pattern -> bump VERSION; the pattern hash
# printed beside it changes on its own, so an unbumped edit is still visible.
PATTERNS = [
    ("negation-pivot", "structural",
     r"\b(?:it'?s|it is|this is|that'?s|that is|was|is)\s+(?:not|never)\s+(?:just\s+|only\s+|about\s+)?[^.;:!?\n]{1,60}?(?:[,;]|\s[—–-]{1,2})\s*(?:it'?s|it is|but|this is|that'?s)\b"),
    ("negation-pivot", "structural",
     r"\b(?:was|is)\s+never\s+[^.!?\n]{1,60}[.!?]\s+(?:it'?s|it is|it was)\b"),
    ("objection-unraised", "structural", r"\b(?:i'?m not saying|to be clear,|let me be clear)"),
    ("announced-transition", "rhetorical",
     r"\b(?:let'?s dive in|let'?s dive into|here'?s what you need to know|without further ado|let'?s break (?:it|this) down)"),
    ("fake-candid-opener", "rhetorical", r"(?:^|(?<=[.!?]\s))(?:honestly\?|look,|here'?s the thing)"),
    ("manufactured-depth", "rhetorical", r"\b(?:at its core|the real question is|what really matters)"),
    ("formulaic-aphorism", "rhetorical", r"\bis the (?:language|currency|architecture|grammar) of\b"),
    ("inflated-significance", "rhetorical", r"\b(?:a testament to|stands as a testament|pivotal moment|a turning point)"),
    ("vague-attribution", "rhetorical",
     r"\b(?:experts (?:believe|say|agree)|industry reports (?:suggest|show)|studies (?:show|suggest)|research shows)"),
    ("register-word", "lexical",
     r"\b(?:delve|delves|delving|tapestry|testament|pivotal|underscore|underscores|seamless|seamlessly|robust|vibrant|intricate|foster|fosters|unlock|unlocks|leverage|leverages|landscape|crucial|navigate|navigating)\b"),
    ("verb-avoidance", "lexical", r"\b(?:serves as|stands as|boasts)\b"),
    ("assistant-residue", "residue",
     r"\b(?:i hope this helps|let me know if you(?:'d like| want| need)|great question|happy to help|certainly!)"),
]
COMPILED = [(i, c, re.compile(p, re.I | re.M)) for i, c, p in PATTERNS]
PATTERN_HASH = hashlib.sha256("\n".join(i + "\t" + p for i, _, p in PATTERNS).encode()).hexdigest()[:8]


def blank(m):
    """Replace a match with spaces, keeping newlines, so positions and paragraphs survive."""
    return re.sub(r"[^\n]", " ", m.group(0))


def prose_of(text):
    """(prose_for_words, prose_for_matching) with the same length and line structure."""
    t = text.replace("\r\n", "\n")
    t = re.sub(r"\A---\n.*?\n---\n", blank, t, flags=re.S)                 # front matter
    t = re.sub(r"^(```|~~~).*?^\1[^\n]*$", blank, t, flags=re.S | re.M)     # fenced code
    t = re.sub(r"`[^`\n]+`", blank, t)                                      # inline code
    t = re.sub(r"\]\([^)\s]*\)", lambda m: "]" + " " * (len(m.group(0)) - 1), t)  # link targets
    words = t
    m = re.sub(r"^>.*$", blank, t, flags=re.M)                              # blockquotes
    m = re.sub(r"“[^”\n]*”", blank, m)                        # “curly quotes”
    m = re.sub(r"(?<![\w])\"[^\"\n]*\"", blank, m)                          # "straight quotes"
    return words, m


def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    words_text, match_text = prose_of(text)
    n_words = len(re.findall(r"[A-Za-zÀ-ɏ]+(?:'[A-Za-z]+)?", words_text))
    starts = [0] + [m.end() for m in re.finditer(r"\n\s*\n", match_text)]
    hits, seen = [], set()
    for pid, cat, rx in COMPILED:
        for m in rx.finditer(match_text):
            if (m.start(), pid) in seen:
                continue
            seen.add((m.start(), pid))
            line = match_text.count("\n", 0, m.start()) + 1
            col = m.start() - (match_text.rfind("\n", 0, m.start()) + 1) + 1
            para = sum(1 for s in starts if s <= m.start())
            snippet = " ".join(text.replace("\r\n", "\n")[m.start():m.end()].split())[:80]
            hits.append({"line": line, "col": col, "paragraph": para, "pattern": pid,
                         "category": cat, "text": snippet})
    hits.sort(key=lambda h: (h["line"], h["col"], h["pattern"]))
    per_para = {}
    for h in hits:
        per_para[h["paragraph"]] = per_para.get(h["paragraph"], 0) + 1
    bursts = sorted(p for p, n in per_para.items() if n >= 2)
    density = round(len(hits) * 1000.0 / n_words, 2) if n_words else 0.0
    return {"file": path, "words": n_words, "candidates": len(hits),
            "per_1000_words": density, "burst_paragraphs": bursts, "hits": hits}


def main(argv):
    files = [a for a in argv if not a.startswith("--")]
    as_json = "--json" in argv
    if not files:
        sys.stderr.write("usage: finder.py <file> [<file> ...] [--json]\n")
        return 2
    header = "voice-gate finder v%s (patterns %s)" % (VERSION, PATTERN_HASH)
    results = [scan(f) for f in files]
    if as_json:
        print(json.dumps({"finder": header, "results": results}, ensure_ascii=False, indent=1))
        return 0
    print(header)
    for r in results:
        for h in r["hits"]:
            print("%s:%d:%d  p%d  %-22s %s" % (r["file"], h["line"], h["col"], h["paragraph"], h["pattern"], h["text"]))
        print("%s: %d candidates in %d words (%.2f per 1,000); paragraphs with 2+: %s"
              % (r["file"], r["candidates"], r["words"], r["per_1000_words"],
                 ", ".join("p%d" % p for p in r["burst_paragraphs"]) or "none"))
    print("Candidates only: the read decides which are real and finds the ones no pattern can.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""issue-scrub.py — strip the vault out of a report before it leaves the machine.

WHY. An operator's report about the framework is written inside their vault, by a session that
has read their vault. So the draft of a public GitHub issue routinely carries things that were
never meant for it: a home path with the operator's login in it, a path into their notes, a
client's name, a teammate's email, a Slack channel id, a line quoted from a private context file.
Each one reads as harmless detail to the session that wrote it. Once filed, an issue is public and
effectively permanent. A judgment pass ("check it for anything personal") misses exactly the items
the writer stopped seeing, so this is a script with a test (tests/issue-scrub.test.sh), not a
reminder. It is the de-personalization rule CONTRIBUTING enforces at review, moved to the moment
of writing.

WHAT IT REMOVES (each replaced by a placeholder, never silently dropped):
  - home paths       /Users/<login>/..., /home/<login>/..., C:\\Users\\<login>\\...  -> ~/...
  - vault paths      anything under "00 - notes", "01 - calendar", "02 - assets", "03 - export",
                     "04 - backups"                                  -> <vault path redacted>
  - vault links      [[wikilinks]] that do not name a framework file -> <vault link redacted>
  - vault quotes     a run of 10+ words copied from USER.md, INTENT.md or context/ (declared,
                     observed, ventures)                             -> <vault content redacted>
  - names            read from the vault itself (below)             -> a role: "the operator",
                     "the primary session", "a company", "a client", "a contact"
  - emails, Slack/Drive/Docs links, Slack ids, ASINs, phone numbers, token-shaped strings
                                                                     -> <... redacted>
Only framework files (plugins/, hooks/, agents/, skills/, templates/, CLAUDE.md, SETUP.md, ...)
survive as quotable paths, because only they mean the same thing on every operator's machine.

WHERE NAMES COME FROM (all local, read-only, nothing is sent anywhere):
  USER.md "## Identity" first column (session names) and "## Companies" first column;
  context/declared/about_me.md "aliases:" and its "My name is ..." line; context/ventures/ folder
  names; projects/ notes named advisory-* (clients) and space-* (collaborating orgs); headings of
  context/observed/ecosystem.md; `git config user.name` / `user.email`; the OS login. Rows marked
  as template examples (italic cells, {{placeholders}}) are skipped. --term / --terms-file add
  names the vault does not hold.
The report line always says how many names it loaded. A scrub that loaded zero names looks
identical to one that found nothing to remove, so the count is printed rather than implied.

USAGE
  uv run hooks/security/issue-scrub.py [FILE] [--root DIR] [--term NAME ...] [--terms-file F]
                              [--out FILE] [--json] [--show-removed] [--check]
  FILE (or stdin) is the draft. The scrubbed text goes to stdout (or --out). One report line goes
  to stderr: "issue-scrub: redacted: 3 paths, 1 name, 0 ids ... (names loaded: 14)". --json makes
  that report a JSON object. --show-removed lists each removed string on stderr (local terminal
  only; never paste that list anywhere). --check prints nothing to stdout and only reports.
  --root is the framework root holding USER.md and vault/ (default: $AIOS_ROOT, else the folder
  above this script, so it self-locates on any machine).

EXIT CODES
  0  scrubbed (whether or not anything was removed) · or --check found nothing to remove
  1  --check only: something would be removed (the text is not safe to send as-is)
  2  usage error, or the input file could not be read
  3  REFUSED, nothing written: a loaded name is still readable once markup is ignored, or the
     scrub did not converge. Fail closed -- a pattern scrubber cannot know every way a page can
     render a word, so the last check reads the output the coarsest way a person could.
  4  the scrubber itself failed (an unexpected error, printed in one line); nothing written.
     Distinct from 1 so a caller never reads a crash as "something would be removed".
A name source that exists but could not be read (permissions, a git that will not run) is named
on the report line ("could not read: ..."), because a scrub that silently skipped one loads fewer
names and looks the same as a complete one.
Stdlib only. Runs on macOS, Linux and Windows.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import unicodedata

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))

# Words that may appear as a venture, session or folder name but are also ordinary framework or
# English vocabulary. Redacting them would wreck technical text, which the operator then stops
# trusting. A real name that collides with one of these is a known gap the --show-removed diff
# and the operator's read of the final body cover.
STOP = {
    "aios", "claude", "code", "vault", "glass", "app", "the", "and", "for", "with", "main",
    "agent", "agents", "session", "sessions", "operator", "user", "users", "admin", "root",
    "home", "notes", "today", "test", "tests", "demo", "example", "personal", "custom",
    "buddy", "ops", "dev", "work", "default", "none", "null", "true", "false", "github",
    "google", "slack", "drive", "docs", "macos", "linux", "windows", "hooks", "skills",
    "plugins", "templates", "commands", "issue", "issues", "report", "framework", "canonical",
}

VAULT_DIR = r"0[0-4] - (?:notes|calendar|assets|export|backups)"
FRAMEWORK_DIRS = ("agents", "skills", "templates", "plugins", "hooks", "mcps")
PATH_STOP = set(" \t\n`'\"<>|()[]{}")
FILE_EXT = re.compile(r"\.(?:md|markdown|json|jsonl|txt|csv|pdf|png|jpe?g|gif|canvas|base|ya?ml|html)\b")

# Token shapes. Kept in step with hooks/git/secret-scan.sh, plus generic key=value secrets.
SECRET_RES = [
    re.compile(p) for p in (
        r"sk-ant-[A-Za-z0-9_-]{20,}", r"AKIA[0-9A-Z]{16}", r"gh[posur]_[A-Za-z0-9]{36}",
        r"github_pat_[A-Za-z0-9_]{60,}", r"xox[baprs]-[A-Za-z0-9-]{10,}", r"AIza[0-9A-Za-z_-]{35}",
        r"glpat-[A-Za-z0-9_-]{20,}", r"GOCSPX-[A-Za-z0-9_-]{20,}",
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}",
    )
]
KV_SECRET = re.compile(r"(?i)\b((?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|password|passwd)"
                       r"\s*[:=]\s*)(['\"]?)[^\s'\"<>]{6,}\2")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
LINK_RES = [
    (re.compile(r"https?://(?:docs|drive|sheets|slides)\.google\.com/\S+"), "<drive link redacted>"),
    (re.compile(r"https?://[A-Za-z0-9-]+\.slack\.com/\S+"), "<slack link redacted>"),
]
# A Slack id is C/D/G/U + 8+ upper-alnum WITH a digit; "CHANGELOG" has none, so it survives.
SLACK_ID = re.compile(r"\b[CDGU](?=[A-Z0-9]*\d)[A-Z0-9]{8,11}\b")
ASIN = re.compile(r"\bB0(?=[A-Z0-9]*[A-Z])[A-Z0-9]{8}\b")
PHONE = re.compile(r"(?<![\w.:/-])(?:\+\d{1,3}[\s.-]?\(?\d{1,4}\)?(?:[\s.-]?\d{2,4}){2,4}"
                   r"|\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4})(?![\w.:/-])")
# A long opaque id that mixes upper, lower AND digits (a Drive file id, an API key of unknown
# shape). Pure hex (git SHAs, hashes) and UUIDs are technical and survive.
OPAQUE = re.compile(r"(?<![\w/-])(?=[A-Za-z0-9_-]*[A-Z])(?=[A-Za-z0-9_-]*[a-z])(?=[A-Za-z0-9_-]*\d)"
                    r"[A-Za-z0-9_-]{28,}(?![\w-])")
HOME_PATHS = [
    re.compile(r"/Users/[^/\s`'\"<>]+"), re.compile(r"/home/[^/\s`'\"<>]+"),
    re.compile(r"[A-Za-z]:\\\\?Users\\\\?[^\\\s`'\"<>]+"),
]
WIKILINK = re.compile(r"!?\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]")
WORD = re.compile(r"[A-Za-z0-9\u00C0-\u024F']+")
SHINGLE = 10


UNREADABLE = []  # name sources that exist but could not be read; named on the report line


def read_text(path, label=None):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        if label and os.path.exists(path):
            UNREADABLE.append(label)
        return ""


def list_dir(path, label):
    try:
        return os.listdir(path) if os.path.isdir(path) else []
    except OSError:
        UNREADABLE.append(label)
        return []


def section(text, heading):
    """Body of the first '## heading...' section, up to the next '## '."""
    m = re.search(r"^## " + re.escape(heading) + r".*$", text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"^## ", rest, re.M)
    return rest[: n.start()] if n else rest


def table_first_column(body):
    out = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("|") or re.match(r"^\|[\s:|-]+\|?$", line):
            continue
        cell = line.strip("|").split("|")[0].strip()
        if not cell or cell.startswith("*") or "{{" in cell:
            continue  # header-less example rows are italic; placeholders are not names
        out.append(cell.strip("`* "))
    return out[1:] if out and out[0].lower() in ("name", "company", "identity") else out


def kebab_words(slug):
    return slug.replace("-", " ").replace("_", " ").strip()


def public_names(root):
    """The framework's own PUBLIC org name, so a cross-repo reference (`<org>/aios#8`) is not turned
    into `a company/aios#8` (a vault lists the framework's org as a company). Narrow on purpose:
    only org names, only from CONTRIBUTING.md -- a Tier-1 file identical in every vault. Never from
    .aios-update, which an operator or a fork can point at a private org; and never repo names,
    which are generic words (`site`, `org`) that could equal a private name."""
    text = read_text(os.path.join(root, "CONTRIBUTING.md"))
    return {_pkey(org) for org in re.findall(r"github\.com/([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+", text)}


def _pkey(name):
    # "The-AIOS", "the_aios" and "The AIOS" (a folder name split into words) are one name.
    return re.sub(r"[\s_-]+", "", name.lower())


def load_terms(root, extra):
    """Return {term: placeholder} from the operator's own files. Missing files are fine."""
    terms = {}
    public = public_names(root)

    def add(term, role, explicit=False):
        term = (term or "").strip().strip("`*\"' ")
        # The length floor and stoplist filter noise out of names MINED from vault tables. A name
        # the operator passed by hand (--term / --terms-file) is a decision, never filtered.
        if not term or (not explicit and ("{{" in term or len(term) < 3 or term.lower() in STOP
                                          or _pkey(term) in public)):
            return
        terms.setdefault(term, role)

    vault = os.path.join(root, "vault", "00 - notes")
    user = read_text(os.path.join(root, "USER.md"), "USER.md")
    for name in table_first_column(section(user, "Identity")):
        add(name, "the primary session")
    for name in table_first_column(section(user, "Companies")):
        add(name, "a company")
        add(kebab_words(name), "a company")

    about = read_text(os.path.join(vault, "context", "declared", "about_me.md"), "about_me.md")
    fm = re.match(r"^---\n(.*?)\n---", about, re.S)
    if fm:
        al = re.search(r"^aliases:\s*\n((?:\s+-\s+.*\n?)+)", fm.group(1) + "\n", re.M)
        for item in re.findall(r"-\s+(.+)", al.group(1) if al else ""):
            add(item, "the operator")
    m = re.search(r"My name is ([^.\n]+)", about)
    if m:
        full = m.group(1).strip()
        add(full, "the operator")
        for part in full.split():
            add(part, "the operator")

    ventures = os.path.join(vault, "context", "ventures")
    for d in list_dir(ventures, "context/ventures/"):
        if os.path.isdir(os.path.join(ventures, d)) and not d.startswith((".", "_")):
            add(d, "a company")
            add(kebab_words(d), "a company")

    projects = os.path.join(vault, "projects")
    for f in list_dir(projects, "projects/"):
        base, ext = os.path.splitext(f)
        for prefix, role in (("advisory-", "a client"), ("space-", "a company")):
            if ext == ".md" and base.startswith(prefix):
                slug = base[len(prefix):]
                add(slug, role)
                add(kebab_words(slug), role)
                add(base, role)

    eco = read_text(os.path.join(vault, "context", "observed", "ecosystem.md"), "ecosystem.md")
    for h in re.findall(r"^#{2,4}\s+(.+)$", eco, re.M):
        h = re.sub(r"[\[\]*_`]", "", h).split("(")[0].split("—")[0].split(" - ")[0].strip()
        add(h, "a contact")

    for key, role in (("user.name", "the operator"), ("user.email", "the operator")):
        try:
            v = subprocess.run(["git", "config", "--get", key], cwd=root, capture_output=True,
                               text=True, encoding="utf-8", timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError, ValueError):
            v = ""
            if "git config" not in UNREADABLE:
                UNREADABLE.append("git config")
        add(v, role)
    try:
        import getpass
        add(getpass.getuser(), "the operator")
    except Exception:
        UNREADABLE.append("the OS login")

    for t in extra:
        add(t, "<name redacted>", explicit=True)
    return terms


def norm(text):
    """The rendered form: entities decoded, NFKC, format (invisible) characters removed. Applied to
    the draft AND to every name and quote it is matched against -- normalising only one side is a
    bypass of its own (a name stored decomposed or fullwidth would never match the normalised text)."""
    # To a FIXED POINT: one form can decode into another (`&amp;#101;` -> `&#101;` -> `e`; a
    # fullwidth `＆` becomes `&` only after NFKC and can then start an entity). A single pass
    # leaves text that GitHub renders one step further than this matched.
    for _ in range(8):
        nxt = unicodedata.normalize("NFKC", html.unescape(text))
        nxt = "".join(ch for ch in nxt if unicodedata.category(ch) != "Cf")
        if nxt == text:
            break
        text = nxt
    return text


def load_shingles(root):
    """10-word runs from the operator's private context files, for verbatim-quote detection."""
    files = [os.path.join(root, "USER.md"), os.path.join(root, "INTENT.md")]
    ctx = os.path.join(root, "vault", "00 - notes", "context")
    for sub in ("declared", "observed", "ventures"):
        for dp, _dn, fn in os.walk(os.path.join(ctx, sub)):
            files += [os.path.join(dp, f) for f in fn if f.endswith(".md") and f != "_index.md"]
    shingles = set()
    for f in files:
        try:
            if os.path.getsize(f) > 2_000_000:
                continue
        except OSError:
            continue
        words = [w.lower() for w in WORD.findall(norm(read_text(f)))]
        for i in range(len(words) - SHINGLE + 1):
            shingles.add(" ".join(words[i:i + SHINGLE]))
    return shingles


def framework_names(root):
    names = set()
    for d in FRAMEWORK_DIRS:
        for dp, dn, fn in os.walk(os.path.join(root, d)):
            dn[:] = [x for x in dn if x not in ("custom", "node_modules", ".git", "__pycache__")]
            names.update(os.path.splitext(f)[0] for f in fn)
            names.update(dn)
    return names


# Letters from other scripts that render like Latin ones. A name spelled with a Cyrillic `е` looks
# identical on the page and matches nothing, so the fail-closed reading folds them back to Latin.
CONFUSABLES = str.maketrans({
    "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o", "р": "p", "с": "c", "т": "t",
    "у": "y", "х": "x", "ѕ": "s", "і": "i", "ј": "j", "ԁ": "d", "ӏ": "l", "һ": "h", "ԛ": "q", "ԝ": "w",
    "α": "a", "β": "b", "ε": "e", "η": "n", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "τ": "t",
    "υ": "u", "χ": "x", "ɡ": "g", "ı": "i", "ℓ": "l",
})


class Scrubber:
    def __init__(self, terms, shingles, fw_names):
        self.counts = {k: 0 for k in ("hidden", "paths", "vault", "links", "quotes", "names", "emails", "ids", "secrets")}
        self.removed = []
        terms = {norm(t): r for t, r in terms.items() if norm(t).strip()}
        self.terms = terms
        self.shingles = shingles
        self.fw = fw_names
        ordered = sorted(terms, key=len, reverse=True)
        self.term_re = re.compile(
            r"(?<![\w@-])(" + "|".join(self._spread(t) for t in ordered) + r")(?![\w@-])", re.I
        ) if ordered else None
        self.lower = {t.lower(): r for t, r in terms.items()}

    @staticmethod
    def _spread(term):
        # Markdown emphasis inside a word still renders as the word: `Jo**hn**` shows "John" on
        # GitHub. Allow up to three emphasis/code marks between any two characters of a name.
        # Inline HTML renders the same way (`Jo<b></b>hn`, `Jo<!-- -->hn`), so a short tag counts too.
        # An empty markdown link (`Zede[](x)kiah`) renders as nothing, so it counts as a mark too.
        return r"(?:[*_~`]|<[^<>\n]{0,40}>|\[\]\([^()\n]{0,80}\)){0,3}".join(re.escape(ch) for ch in term)

    def canon(self, text):
        """Make the text read the way GitHub will render it, BEFORE matching. Otherwise a name split
        by a zero-width character, written as HTML entities (`J&#111;hn`) or in compatibility forms
        (fullwidth letters) passes every pattern here and still renders as the name."""
        before = text
        hidden = sum(1 for ch in unicodedata.normalize("NFKC", html.unescape(text)) if unicodedata.category(ch) == "Cf")
        text = norm(text)
        if text != before:
            self.counts["hidden"] += max(1, hidden)
            self.removed.append(("hidden", "entities / invisible or compatibility characters normalised"))
        return text

    def _hit(self, kind, original, placeholder):
        self.counts[kind] += 1
        self.removed.append((kind, original))
        return placeholder

    def sub(self, rx, text, kind, placeholder):
        return rx.sub(lambda m: self._hit(kind, m.group(0), placeholder), text)

    def vault_paths(self, text):
        out, i = [], 0
        for m in re.finditer(VAULT_DIR, text):
            if m.start() < i:
                continue
            s = m.start()
            while s > 0 and text[s - 1] not in PATH_STOP:  # extend left over the path prefix
                s -= 1
            line_end = text.find("\n", m.end())
            line_end = len(text) if line_end < 0 else line_end
            tail = text[m.end():line_end]
            ext = FILE_EXT.search(tail)
            stop = next((k for k, c in enumerate(tail) if c in "`'\"<>|()[]"), len(tail))
            if ext and ext.end() <= stop:
                e = m.end() + ext.end()  # file names may contain spaces: end at the extension
            else:
                ws = next((k for k, c in enumerate(tail) if c in PATH_STOP), len(tail))
                e = m.end() + ws
            out.append(text[i:s])
            out.append(self._hit("vault", text[s:e], "<vault path redacted>"))
            i = e
        out.append(text[i:])
        return "".join(out)

    def links(self, text):
        def repl(m):
            target = os.path.basename(m.group(1).strip())
            if target in self.fw:
                return m.group(0)
            return self._hit("links", m.group(0), "<vault link redacted>")
        return WIKILINK.sub(repl, text)

    def quotes(self, text):
        if not self.shingles:
            return text
        # Words are matched across line breaks (whitespace normalised): a quoted passage that wraps,
        # or is re-flowed into a blockquote, is the same passage. Every line it touches is redacted.
        lines = text.split("\n")
        seq = [(w.lower(), n) for n, line in enumerate(lines) for w in WORD.findall(line)]
        hit = set()
        for i in range(len(seq) - SHINGLE + 1):
            if " ".join(w for w, _ in seq[i:i + SHINGLE]) in self.shingles:
                hit.update(n for _, n in seq[i:i + SHINGLE])
        for n in sorted(hit):
            line = lines[n]
            lead = re.match(r"^\s*(?:[-*>]\s*)*", line).group(0)
            lines[n] = lead + self._hit("quotes", line, "<vault content redacted>")
        return "\n".join(lines)

    def names(self, text):
        if not self.term_re:
            return text
        def repl(m):
            bare = re.sub(r"<[^<>\n]{0,40}>|\[\]\([^()\n]{0,80}\)|[*_~`]", "", m.group(0)).lower()
            return self._hit("names", m.group(0), self.lower.get(bare, "<name redacted>"))
        return self.term_re.sub(repl, text)

    def run(self, text):
        # Scrub until a further pass finds nothing: a redaction can join two fragments into a new
        # match, and the output must be safe to scrub again with the same result (idempotent).
        self.converged = False
        for _ in range(4):
            before = len(self.removed)
            out = self._once(text)
            if out == text and len(self.removed) == before:
                self.converged = True
                return out
            text = out
        return text  # not converged: main() refuses rather than ship it

    @staticmethod
    def skeleton(text):
        """What a reader sees, reduced to letters, digits and word breaks: tags, link targets and
        every mark removed. Coarser than any rendering, so a name that survives here may survive
        there; a name absent here cannot be on the page."""
        text = norm(text)
        text = re.sub(r"<!--[\s\S]*?-->", "", text)           # comments, whatever they contain
        text = re.sub(r"<[^<>]*>", "", text)                 # inline HTML, even across lines
        # Characters that render as nothing without being Unicode "format" characters: combining
        # marks left on their own after NFKC (e.g. the combining grapheme joiner), Hangul fillers,
        # the braille blank. Removed here only -- the shipped text keeps them -- so a name they
        # split is still caught.
        # Accents are folded too (NFD, then marks dropped): a reader still recognises "Zédekiah".
        text = unicodedata.normalize("NFD", text.lower()).translate(CONFUSABLES)
        text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn"
                       and ch not in "\u115f\u1160\u3164\uffa0\u2800")
        text = re.sub(r"\]\([^()]*\)", "]", text)            # link targets
        text = re.sub(r"[*_~`\[\]]", "", text)                 # markup: invisible when rendered
        # Every other mark is visible and separates words (`kiah's` reads as "kiah s"), so it
        # becomes a break -- dropping it would glue a suffix on and hide the name from the match.
        text = "".join(ch if (ch.isalnum() or ch.isspace()) else " " for ch in text)
        return " ".join(text.lower().split())

    def residual(self, clean):
        """Fail closed: names whose letters still appear, as a word, in the scrubbed output."""
        sk = " " + self.skeleton(clean) + " "
        left = []
        for t in self.terms:
            st = self.skeleton(t)
            # No length floor: the main pass already replaced every plain-text occurrence, so a
            # whole-word hit here is a disguised one, however short the name.
            if st and (" " + st + " ") in sk:
                left.append(t)
        return left

    def _once(self, text):
        text = self.canon(text)
        for rx in SECRET_RES:
            text = self.sub(rx, text, "secrets", "<secret redacted>")
        text = KV_SECRET.sub(lambda m: m.group(1) + self._hit("secrets", m.group(0), "<secret redacted>"), text)
        for rx, ph in LINK_RES:
            text = self.sub(rx, text, "ids", ph)
        text = self.quotes(text)          # before paths/names rewrite the words it matches on
        text = self.sub(EMAIL, text, "emails", "<email redacted>")
        for rx in HOME_PATHS:
            text = rx.sub(lambda m: self._hit("paths", m.group(0), "~"), text)
        text = self.vault_paths(text)
        text = self.links(text)
        text = self.names(text)
        text = self.sub(SLACK_ID, text, "ids", "<slack id redacted>")
        text = self.sub(ASIN, text, "ids", "<id redacted>")
        text = self.sub(OPAQUE, text, "ids", "<id redacted>")
        text = self.sub(PHONE, text, "ids", "<phone redacted>")
        return text


def summary(counts, n_terms, n_shingles, unreadable=()):
    parts = [f"{counts['hidden']} normalised", f"{counts['paths']} paths", f"{counts['vault']} vault paths", f"{counts['links']} vault links",
             f"{counts['quotes']} vault quotes", f"{counts['names']} names", f"{counts['emails']} emails",
             f"{counts['ids']} ids", f"{counts['secrets']} secrets"]
    ctx = f"names loaded: {n_terms}" + ("" if n_shingles else "; no private context files found for quote check")
    if unreadable:
        ctx += "; could not read: " + ", ".join(unreadable)
    return "issue-scrub: redacted: " + ", ".join(parts) + f" ({ctx})"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Scrub vault content out of an issue draft.")
    ap.add_argument("file", nargs="?")
    ap.add_argument("--root", default=os.environ.get("AIOS_ROOT") or os.path.dirname(os.path.dirname(HERE)))
    ap.add_argument("--term", action="append", default=[])
    ap.add_argument("--terms-file")
    ap.add_argument("--out")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--show-removed", action="store_true")
    ap.add_argument("--check", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else 2

    try:
        if a.file:
            with open(a.file, encoding="utf-8", errors="replace") as f:
                text = f.read()
        else:
            text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        extra = list(a.term)
        if a.terms_file:
            with open(a.terms_file, encoding="utf-8", errors="replace") as f:
                extra += [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    except OSError as e:
        print(f"issue-scrub: cannot read input: {e}", file=sys.stderr)
        return 2

    terms = load_terms(a.root, extra)
    shingles = load_shingles(a.root)
    s = Scrubber(terms, shingles, framework_names(a.root))
    clean = s.run(text)
    left = s.residual(clean)

    if a.json:
        print(json.dumps({"redacted": s.counts, "names_loaded": len(terms),
                          "quote_check": bool(shingles), "unreadable": UNREADABLE}), file=sys.stderr)
    else:
        print(summary(s.counts, len(terms), len(shingles), UNREADABLE), file=sys.stderr)
    if a.show_removed:
        for kind, orig in s.removed:
            print(f"  removed [{kind}] {orig!r}", file=sys.stderr)

    if left or not s.converged:
        why = ("%d loaded name(s) still readable in the output once markup is ignored" % len(left)
               if left else "the scrub did not converge")
        print(f"issue-scrub: REFUSED -- {why}. Nothing was written: rewrite the draft so the name is "
              "plain text (it will then be replaced), or remove it.", file=sys.stderr)
        if a.out and os.path.exists(a.out):
            os.remove(a.out)  # never leave an earlier scrub's file to be mistaken for this one
        return 3
    if a.check:
        return 1 if s.removed else 0
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="") as f:
            f.write(clean)
    else:
        sys.stdout.write(clean)
    return 0


def _main_guarded():
    try:
        return main()
    except Exception as e:  # never exit 1 on a crash: 1 means "would redact" under --check
        print(f"issue-scrub: failed ({type(e).__name__}: {e}). Nothing was written.", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(_main_guarded())

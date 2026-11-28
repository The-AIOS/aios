"""Evaluate the formulas of an .xlsx workbook built by build_model.py, in pure Python.

Why this exists: openpyxl writes formulas but never calculates them, and a machine
without Excel or LibreOffice has no engine. This evaluator reads the FORMULA STRINGS
stored in the file (not a re-implementation of the model's logic) and computes them,
so the checks and the test drive measure the workbook a founder will open.

It supports the subset build_model.py emits: cell and range references (with or
without a sheet name), + - * / ^, comparisons, & (text join), and the functions
SUM MIN MAX ABS IF IFERROR AND OR NOT INDEX LEFT ROUND ROUNDUP DATE YEAR MONTH AVERAGE.
Anything else raises, so an unsupported formula fails loudly instead of reading 0.

Its agreement with a real spreadsheet engine is checked once per build against
Google Sheets (see SKILL.md, "Verify"), the positive control for this file.
"""
from __future__ import annotations

import datetime as _dt
import math
import re
import sys

import openpyxl
from openpyxl.utils import column_index_from_string, get_column_letter

sys.setrecursionlimit(200000)

_EPOCH = _dt.date(1899, 12, 30)

_TOKEN = re.compile(
    r"""
    (?P<str>"(?:[^"]|"")*")
  | (?P<ref>(?:(?:'(?:[^']|'')+'|[A-Za-z_][A-Za-z0-9_\.]*)!)?\$?[A-Z]{1,3}\$?\d+(?::\$?[A-Z]{1,3}\$?\d+)?)
  | (?P<num>\d+(?:\.\d+)?(?:[eE][+-]?\d+)?%?)
  | (?P<func>[A-Z][A-Z0-9\.]*(?=\())
  | (?P<bool>TRUE|FALSE)(?![A-Za-z0-9_])
  | (?P<name>[A-Za-z_][A-Za-z0-9_\.]*)
  | (?P<op><=|>=|<>|[-+*/^&=<>(),])
  | (?P<ws>\s+)
    """,
    re.VERBOSE,
)

_FUNCS = {"SUM", "MIN", "MAX", "ABS", "IF", "IFERROR", "AND", "OR", "NOT", "INDEX", "LEFT",
          "ROUND", "ROUNDUP", "DATE", "YEAR", "MONTH", "AVERAGE"}


class Range:
    def __init__(self, cells):
        self.cells = cells  # list of rows, each a list of (sheet, coord)


def _flat(args):
    for a in args:
        if isinstance(a, list):
            yield from _flat(a)
        else:
            yield a


def _nums(args):
    return [v for v in _flat(args) if isinstance(v, (int, float)) and not isinstance(v, bool)]


class Workbook:
    def __init__(self, path):
        self.wb = openpyxl.load_workbook(path, data_only=False)
        self.raw = {}
        for ws in self.wb.worksheets:
            for row in ws.iter_rows():
                for c in row:
                    v = c.value
                    if v is None:
                        continue
                    # Google Sheets' .xlsx export stores some single-cell formulas as
                    # array formulas; openpyxl hands those back as objects with .text
                    if hasattr(v, "text") and not isinstance(v, str):
                        v = v.text if str(v.text).startswith("=") else "=" + str(v.text)
                    self.raw[(ws.title, c.coordinate)] = v
        self.code = {}
        self.cache = {}
        self.overrides = {}
        # workbook names (every input has one): name -> "Sheet!$B$12" or a range
        self.names = {}
        for nm, dn in self.wb.defined_names.items():
            self.names[nm.lower()] = dn.attr_text

    # ----- public -----
    def set(self, sheet, coord, value):
        self.overrides[(sheet, coord)] = value
        self.cache = {}

    def reset(self):
        self.overrides = {}
        self.cache = {}

    def value(self, sheet, coord):
        key = (sheet, coord.replace("$", ""))
        if key in self.cache:
            return self.cache[key]
        if key in self.overrides:
            v = self.overrides[key]
        else:
            raw = self.raw.get(key)
            if isinstance(raw, str) and raw.startswith("="):
                v = self._eval_formula(key, raw)
            elif isinstance(raw, _dt.datetime):
                v = (raw.date() - _EPOCH).days
            elif isinstance(raw, _dt.date):
                v = (raw - _EPOCH).days
            else:
                v = raw
        self.cache[key] = v
        return v

    # ----- formula compiling -----
    def _eval_formula(self, key, raw):
        fn = self.code.get(key)
        if fn is None:
            src = self._translate(raw[1:], key[0])
            # eval is safe here: `src` is assembled only from tokens _translate emits
            # (numbers, repr()-quoted strings, whitelisted S._f_* functions, S._cell /
            # S._range calls with repr()-quoted arguments, and arithmetic operators).
            # Any other token raises before this line. Builtins are removed as well.
            try:
                fn = eval("lambda S: " + src, {"__builtins__": {}})
            except SyntaxError as e:
                raise ValueError(f"cannot compile {key}: {raw} -> {src}") from e
            self.code[key] = fn
        try:
            return fn(self)
        except ZeroDivisionError:
            return _Err("#DIV/0!")
        except RecursionError:
            raise
        except TypeError as e:
            return _Err(f"#VALUE! ({e})")

    def _translate(self, f, sheet):
        out = []
        pos = 0
        lazy = []  # one entry per open "(": True when it belongs to IF/IFERROR
        pending_lazy = False
        while pos < len(f):
            m = _TOKEN.match(f, pos)
            if not m:
                raise ValueError(f"unsupported syntax in {sheet}: ={f} at {f[pos:]}")
            pos = m.end()
            kind = m.lastgroup
            tok = m.group(kind)
            if kind == "ws":
                continue
            if kind == "str":
                out.append(repr(tok[1:-1].replace('""', '"')))
            elif kind == "num":
                out.append(f"({float(tok[:-1])}/100)" if tok.endswith("%") else tok)
            elif kind == "bool":
                out.append("True" if tok == "TRUE" else "False")
            elif kind == "func":
                if tok not in _FUNCS:
                    raise ValueError(f"unsupported function {tok} in {sheet}: ={f}")
                out.append(f"S._f_{tok}")
                pending_lazy = tok in ("IF", "IFERROR")
            elif kind == "ref":
                out.append(self._ref(tok, sheet))
            elif kind == "name":
                target = self.names.get(tok.lower())
                if target is None:
                    raise ValueError(f"unknown name {tok} in {sheet}: ={f}")
                out.append(self._ref(target, sheet))
            elif kind == "op":
                if tok == "&":
                    raise ValueError(f"text join (&) is outside the supported subset in {sheet}: ={f}")
                if tok == "(":
                    lazy.append(pending_lazy)
                    out.append("(lambda: " if pending_lazy else "(")
                    pending_lazy = False
                    continue
                if tok == ")":
                    lazy.pop()
                elif tok == "," and lazy and lazy[-1]:
                    out.append(", lambda: ")
                    continue
                out.append({"^": "**", "=": "==", "<>": "!="}.get(tok, tok))
        src = " ".join(out)
        # function calls receive thunks for IF/IFERROR laziness
        return src

    def _ref(self, tok, sheet):
        if "!" in tok:
            sh, addr = tok.rsplit("!", 1)
            if sh.startswith("'"):
                sh = sh[1:-1].replace("''", "'")
        else:
            sh, addr = sheet, tok
        addr = addr.replace("$", "")
        if ":" in addr:
            a, b = addr.split(":")
            return f"S._range({sh!r}, {a!r}, {b!r})"
        return f"S._cell({sh!r}, {addr!r})"

    # ----- dependency graph (for the impact map) -----
    def precedents(self, sheet, raw):
        """Every cell a formula reads: cell refs, ranges (expanded) and names."""
        out, pos, f = [], 0, str(raw)[1:]
        while pos < len(f):
            m = _TOKEN.match(f, pos)
            if not m:
                break
            pos = m.end()
            kind, tok = m.lastgroup, m.group(m.lastgroup)
            if kind == "name" and tok.lower() in self.names:
                kind, tok = "ref", self.names[tok.lower()]
            if kind != "ref":
                continue
            if "!" in tok:
                sh, addr = tok.rsplit("!", 1)
                sh = sh[1:-1].replace("''", "'") if sh.startswith("'") else sh
            else:
                sh, addr = sheet, tok
            addr = addr.replace("$", "")
            if ":" in addr:
                a, b = addr.split(":")
                ca, ra = _split(a)
                cb, rb = _split(b)
                out += [(sh, f"{get_column_letter(c)}{r}") for r in range(ra, rb + 1) for c in range(ca, cb + 1)]
            else:
                out.append((sh, addr))
        return out

    def dependents_graph(self):
        g = {}
        for (sh, coord), raw in self.raw.items():
            if isinstance(raw, str) and raw.startswith("="):
                for p in self.precedents(sh, raw):
                    g.setdefault(p, set()).add((sh, coord))
        return g

    # ----- runtime -----
    def _cell(self, sh, addr):
        v = self.value(sh, addr)
        if isinstance(v, _Err):
            raise _Raise(v)
        return 0 if v is None else v

    def _range(self, sh, a, b):
        ca, ra = _split(a)
        cb, rb = _split(b)
        rows = []
        for r in range(ra, rb + 1):
            row = []
            for c in range(ca, cb + 1):
                row.append(self._cell(sh, f"{get_column_letter(c)}{r}"))
            rows.append(row)
        return rows

    def _f_SUM(self, *a):
        return sum(_nums(a))

    def _f_AVERAGE(self, *a):
        n = _nums(a)
        return sum(n) / len(n)

    def _f_MIN(self, *a):
        n = _nums(a)
        return min(n) if n else 0

    def _f_MAX(self, *a):
        n = _nums(a)
        return max(n) if n else 0

    def _f_ABS(self, x):
        return abs(x)

    def _f_LEFT(self, t, n=1):
        return str(t)[: int(n)]

    # IF and IFERROR receive their arguments as thunks (see _translate), so only the
    # branch taken is evaluated, exactly as in Excel and Google Sheets.
    def _f_IF(self, c, a=lambda: False, b=lambda: False):
        return a() if c() else b()

    def _f_IFERROR(self, a, b):
        try:
            v = a()
        except (_Raise, ZeroDivisionError):
            return b()
        return b() if isinstance(v, _Err) else v

    def _f_AND(self, *a):
        return all(_flat(a))

    def _f_OR(self, *a):
        return any(_flat(a))

    def _f_NOT(self, a):
        return not a

    def _f_INDEX(self, rng, i, j=None):
        rows = rng
        i = int(i)
        if j is None:
            if len(rows) == 1:
                return rows[0][i - 1]
            return rows[i - 1][0]
        return rows[i - 1][int(j) - 1]

    def _f_ROUND(self, x, d=0):
        q = 10 ** int(d)
        return math.floor(abs(x) * q + 0.5) / q * (1 if x >= 0 else -1)

    def _f_ROUNDUP(self, x, d=0):
        q = 10 ** int(d)
        return math.ceil(abs(x) * q - 1e-9) / q * (1 if x >= 0 else -1)

    def _f_DATE(self, y, m, d):
        y, m = int(y) + (int(m) - 1) // 12, (int(m) - 1) % 12 + 1
        return (_dt.date(y, m, 1) - _EPOCH).days + int(d) - 1

    def _f_YEAR(self, s):
        return (_EPOCH + _dt.timedelta(days=int(s))).year

    def _f_MONTH(self, s):
        return (_EPOCH + _dt.timedelta(days=int(s))).month


class _Err:
    def __init__(self, code):
        self.code = code

    def __repr__(self):
        return self.code

    def __bool__(self):
        return False


class _Raise(Exception):
    def __init__(self, err):
        self.err = err


def _split(addr):
    m = re.match(r"([A-Z]+)(\d+)", addr)
    return column_index_from_string(m.group(1)), int(m.group(2))


# A reference to a cell holding an error raises _Raise; the whole formula then takes
# that error, unless an IFERROR around it catches it (as in a spreadsheet).
_orig = Workbook._eval_formula


def _eval_guarded(self, key, raw):
    try:
        return _orig(self, key, raw)
    except _Raise as r:
        return r.err


Workbook._eval_formula = _eval_guarded

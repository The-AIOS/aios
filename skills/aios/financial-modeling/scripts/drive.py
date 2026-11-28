"""Evaluate a built model: checks, metrics, the test drive, and waterfall rows.

Used by build_model.py (right after building) and monthly_update.py, and run on its
own as a read-only report:

    UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python drive.py model.xlsx

Every number here comes from evaluating the workbook's own formulas (xleval.py).
"""
from __future__ import annotations

import sys

from openpyxl.utils import get_column_letter

from xleval import Workbook, _Err

FIRST_COL, MONTHS = 3, 60
CALC_SHEETS = ["Acquisition", "Customers", "Team", "Monthly P&L", "Monthly Balance Sheet", "Monthly Cash Flow", "Funding by month", "Funding", "Dashboard",
               "Annual P&L", "Annual Cash Flow", "Annual Balance Sheet", "Unit Economics", "Checks"]


def mcol(m):
    return get_column_letter(FIRST_COL + m - 1)


class Ev:
    def __init__(self, path):
        self.w = Workbook(path)
        self.rows, self.inputs = {}, {}
        ws = self.w.wb["_rows"]
        for rid, sh, loc, kind in ws.iter_rows(min_row=2, values_only=True):
            if kind == "row":
                self.rows[rid] = (sh, int(loc))
            else:
                self.inputs[rid] = (sh, loc)

    def v(self, rid, m):
        sh, row = self.rows[rid]
        return self.w.value(sh, f"{mcol(m)}{row}")

    def series(self, rid):
        return [self.v(rid, m) for m in range(1, MONTHS + 1)]

    def input_cells(self, iid):
        sh, loc = self.inputs[iid]
        if ":" in str(loc):
            row, n = map(int, str(loc).split(":"))
            return [(sh, f"{get_column_letter(2 + j)}{row}") for j in range(n)]
        return [(sh, loc)]

    def get_input(self, iid):
        return [self.w.value(sh, c) for sh, c in self.input_cells(iid)]

    def set_input(self, iid, values):
        for (sh, c), v in zip(self.input_cells(iid), values):
            self.w.set(sh, c, v)

    def segments(self):
        return sorted({rid.split(".")[0] for rid, (sh, _) in self.rows.items() if sh == "Customers" and rid.endswith(".end")})

    def metrics(self):
        cash = self.series("cf.end")
        return {"cash60": cash[-1], "low": min(cash), "low_month": cash.index(min(cash)) + 1, "fv60": self.v("fund.fv", MONTHS)}

    # ------------------------------------------------------------ checks
    def errors(self):
        out = []
        for (sh, coord), raw in self.w.raw.items():
            if isinstance(raw, str) and raw.startswith("="):
                val = self.w.value(sh, coord)
                if isinstance(val, _Err):
                    out.append(f"{sh}!{coord}: {val}")
        return out

    def hardcoded(self):
        """Numbers typed into calculation tabs that are not gray history."""
        bad = []
        for name in CALC_SHEETS:
            ws = self.w.wb[name]
            first_row = 8 if name not in ("Annual P&L", "Annual Cash Flow", "Annual Balance Sheet", "Unit Economics", "Checks") else 7
            for row in ws.iter_rows(min_row=first_row, min_col=FIRST_COL):
                for c in row:
                    if isinstance(c.value, (int, float)) and not isinstance(c.value, bool):
                        fill = (c.fill.fgColor.rgb or "") if c.fill and c.fill.fill_type else ""
                        # gray = history; yellow or orange = an input kept on this tab on purpose
                        if not str(fill).endswith(("D9D9D9", "FFF2CC", "F8CBAD")):
                            bad.append(f"{name}!{c.coordinate}={c.value}")
        return bad

    def checks(self):
        ws = self.w.wb["Checks"]
        out = []
        for r in range(4, ws.max_row + 1):
            label = ws.cell(r, 1).value
            if label and ws.cell(r, 2).value and label != "Check":
                out.append((label, self.w.value("Checks", f"B{r}")))
        return out

    # ------------------------------------------------------------ test drive
    def levers(self):
        ids = [i for i in self.inputs if not i.startswith(("round.", "role.", "crole.", "pe.", "fx."))]
        lv = []
        for seg in self.segments():
            price = next((i for i in ids if i.startswith(seg + ".") and i.endswith(".price")), None)
            if price:
                lv.append((f"{self._label(price)} +33%", price, lambda v: [x * 4 / 3 for x in v]))
        for i in ids:
            if i.endswith(".spend"):
                lv.append((f"{self._label(i)}: double it (every year)", i, lambda v: [x * 2 for x in v]))
        for i in ids:
            if i.endswith(".conv"):
                lv.append((f"{self._label(i)} +50% (e.g. 2% to 3%)", i, lambda v: [x * 1.5 for x in v]))
        for i in ids:
            if i.endswith(".count") and not i.startswith("role."):
                lv.append((f"{self._label(i)}: double them (every year)", i, lambda v: [x * 2 for x in v]))
        for i in ids:
            if i.endswith(".yield"):
                lv.append((f"{self._label(i)} +25%", i, lambda v: [x * 1.25 for x in v]))
        for i in ids:
            if i.endswith(".churn"):
                lv.append((f"{self._label(i)} +33%", i, lambda v: [x * 4 / 3 for x in v]))
        for i in ids:
            if i.endswith(".price") and i not in [x[1] for x in lv]:
                lv.append((f"{self._label(i)} +33%", i, lambda v: [x * 4 / 3 for x in v]))
        for k in [i[:-5] for i in self.inputs if i.endswith(".pess")]:
            pv, ov = self.get_input(k + ".pess")[0], self.get_input(k + ".opt")[0]
            lv.append((f"Decisive: {self._label(k)} at its pessimistic value ({pv:g})", k, lambda v, pv=pv: [pv]))
            lv.append((f"Decisive: {self._label(k)} at its optimistic value ({ov:g})", k, lambda v, ov=ov: [ov]))
        if "ar_days" in self.inputs:
            lv.append(("Customers pay 30 days slower (receivables +30 days)", "ar_days", lambda v: [x + 30 for x in v]))
        if "ap_days" in self.inputs and (self.get_input("ap_days")[0] or 0) > 0:
            lv.append(("You pay suppliers 30 days faster (payables −30 days, floor 0)", "ap_days", lambda v: [max(0, x - 30) for x in v]))
        return lv

    def _label(self, iid):
        # the label sits in column A of the input's own tab (Assumptions, or any tab a model keeps inputs on)
        sh, loc = self.inputs[iid]
        row = int(str(loc).split(":")[0]) if ":" in str(loc) else int("".join(ch for ch in str(loc) if ch.isdigit()))
        return str(self.w.raw.get((sh, f"A{row}"), iid)).strip()

    def test_drive(self):
        self.w.reset()
        base = self.metrics()
        rows = []
        for label, iid, fn in self.levers():
            old = self.get_input(iid)
            self.set_input(iid, fn(old))
            m = self.metrics()
            self.w.reset()
            rows.append((label, base, m))
        extra = self.breakeven_churn(base)
        return base, rows, extra

    def breakeven_churn(self, base):
        # the main recurring segment: the one whose recurring line earns the most in year 5
        best, seg, price = -1, None, None
        for rid in self.rows:
            if rid.startswith("rec."):
                lk = rid[4:]
                rev = sum(self.v(lk + ".rev", m) for m in range(49, 61))
                if rev > best:
                    best, seg, price = rev, lk.split(".")[0], lk + ".price"
        if not seg or price not in self.inputs:
            return None
        churn_id = f"{seg}.churn"
        if not price or churn_id not in self.inputs:
            return None
        p0, c0 = self.get_input(price), self.get_input(churn_id)[0]
        lo, hi = c0, min(0.95, c0 * 10 + 0.05)
        self.set_input(price, [x * 4 / 3 for x in p0])

        def cash_at(c):
            self.set_input(churn_id, [c])
            return self.metrics()["cash60"]

        if cash_at(hi) > base["cash60"]:
            self.w.reset()
            return (self._label(price), self._label(churn_id), c0, None)
        for _ in range(40):
            mid = (lo + hi) / 2
            if cash_at(mid) > base["cash60"]:
                lo = mid
            else:
                hi = mid
        self.w.reset()
        return (self._label(price), self._label(churn_id), c0, (lo + hi) / 2)

    # ------------------------------------------------------------ waterfalls
    def waterfall_values(self):
        out = {f"cust.{s}": [self.v(f"{s}.end", m) for m in range(1, 13)] for s in self.segments()}
        out["revenue"] = [self.v("pl.rev", m) for m in range(1, 13)]
        out["cash"] = [self.v("cf.end", m) for m in range(1, 13)]
        return out


def impact_map(ev):
    """For each input: the tabs it changes directly, then downstream (from the formula
    graph, never from a list someone keeps). And for each tab: which tabs feed it and
    which it feeds."""
    from collections import deque
    g = ev.w.dependents_graph()
    per_input = {}
    for iid in ev.inputs:
        start = ev.input_cells(iid)
        # direct = the first tabs other than Assumptions a change lands on (looking
        # through Assumptions-internal links such as the scenario switch's "In use" cell)
        direct, seen_a, frontier = [], set(start), list(start)
        while frontier:
            nxt = []
            for c in frontier:
                for d in g.get(c, ()):
                    if d[0] == "Assumptions":
                        if d not in seen_a:
                            seen_a.add(d)
                            nxt.append(d)
                    elif d[0] not in direct:
                        direct.append(d[0])
            frontier = nxt
        seen, q, later = set(start), deque(start), []
        while q:
            c = q.popleft()
            for d in g.get(c, ()):
                if d not in seen:
                    seen.add(d)
                    q.append(d)
                    if d[0] not in direct and d[0] not in later and d[0] != "Assumptions":
                        later.append(d[0])
        per_input[iid] = (direct, later)
    feeds, fed_by = {}, {}
    for (psh, _), deps in g.items():
        for (dsh, _) in deps:
            if psh != dsh:
                feeds.setdefault(psh, set()).add(dsh)
                fed_by.setdefault(dsh, set()).add(psh)
    return per_input, feeds, fed_by


def write_impact(wb, ev, per_input, feeds, fed_by):
    from openpyxl.styles import Font
    ws = wb["Assumptions"]
    order = [n for n in wb.sheetnames]
    srt = lambda xs: sorted(xs, key=lambda x: order.index(x) if x in order else 999)
    for iid, (direct, later) in per_input.items():
        for sh, c in ev.input_cells(iid)[:1]:
            if sh != "Assumptions":
                continue
            row = int("".join(ch for ch in c if ch.isdigit()))
            txt = ", ".join(srt(direct)) or "nothing yet"
            if later:
                txt += "  →  then " + ", ".join(srt(later))
            ws.cell(row, 11, txt).font = Font(italic=True, color="595959")
    for name in wb.sheetnames:
        if name in ("README", "Assumptions", "Checks", "Test Drive", "Waterfalls", "_rows"):
            continue
        if name == "Charts":
            wb[name]["A4"] = "Draws from: Monthly P&L, Monthly Cash Flow, Funding by month (charts read rows directly, not through formulas)."
            wb[name]["A4"].font = Font(italic=True, color="595959", size=9)
            continue
        fb = ", ".join(srt(fed_by.get(name, ())))
        fd = ", ".join(srt(feeds.get(name, ())))
        wb[name]["A4"] = f"Fed by: {fb or 'Assumptions only'}.   Feeds: {fd or 'nothing (a summary)'}."
        wb[name]["A4"].font = Font(italic=True, color="595959", size=9)


def write_test_drive(ws, base, rows, extra, money_fmt, stamp):
    from openpyxl.styles import Font, PatternFill
    head = PatternFill("solid", fgColor="1F3864")
    for r in range(5, ws.max_row + 2):
        for c in range(1, 8):
            ws.cell(r, c).value = None
    hdr = ["Lever (one change, everything else held)", "Year-5 cash, base", "Year-5 cash, after", "Change", "Change %", "Lowest cash, after", "What it says"]
    for i, h in enumerate(hdr):
        c = ws.cell(5, 1 + i, h)
        c.fill, c.font = head, Font(color="FFFFFF", bold=True)
    r = 6
    for label, b, m in rows:
        d = m["cash60"] - b["cash60"]
        pct = d / abs(b["cash60"]) if b["cash60"] else 0
        thin = m["low"] < max(0.5 * b["low"], 0) or m["low"] < 25000
        if b["low"] < 0:
            dl = m["low"] - b["low"]
            gap = "fixes the cash gap" if m["low"] >= 0 else ("narrows the cash gap" if dl > 0 else ("widens the cash gap" if dl < 0 else "leaves the cash gap as is"))
            size = "big" if abs(pct) >= 0.2 else ("modest" if abs(d) >= max(25000, 0.02 * abs(b["cash60"])) else "small")
            read = f"The base case already dips below zero. This change {gap} (lowest {m['low']:,.0f} vs {b['low']:,.0f}); its effect on year-5 cash is {size} ({'+' if d >= 0 else ''}{pct:.0%})."
        elif m["low"] < 0 and d > 0:
            read = f"Cash goes negative (month {m['low_month']}): the company dies before the upside. Needs more funding, a slower ramp, or both."
        elif m["low"] < 0:
            read = f"Cash goes negative (month {m['low_month']}): this change alone would kill the company. Manage it, or fund the buffer."
        elif abs(d) < max(25000, 0.02 * abs(b["cash60"])):
            read = "Moves almost nothing: a candidate to say no to (zero time, zero money)."
        elif d > 0 and thin:
            read = f"A lever, but cash gets dangerously thin (lowest {m['low']:,.0f}, month {m['low_month']}). Ramp it, or raise first."
        elif d > 0 and pct >= 0.2:
            read = "A big lever: test it for real, with a numeric pass/fail."
        elif d > 0:
            read = "A modest lever."
        elif thin:
            read = f"Hurts, and cash gets dangerously thin (lowest {m['low']:,.0f}, month {m['low_month']})."
        else:
            read = "Hurts: protect against it."
        vals = [label, b["cash60"], m["cash60"], d, pct, m["low"], read]
        for i, v in enumerate(vals):
            c = ws.cell(r, 1 + i, v)
            if i in (1, 2, 3, 5):
                c.number_format = money_fmt
            if i == 4:
                c.number_format = "0%"
        r += 1
    r += 1
    if extra:
        plabel, clabel, c0, be = extra
        ws.cell(r, 1, "Break-even test (the hairpin turn)").font = Font(bold=True)
        r += 1
        if be is None:
            ws.cell(r, 1, f"With {plabel} +33%, year-5 cash beats the base case at any churn tested: price is not the constraint here.")
        else:
            ws.cell(r, 1, f"With {plabel} +33%, {clabel} can rise from {c0:.2%} to {be:.2%} before year-5 cash falls below the base case. Test the higher price on a new cohort: churn below {be:.2%} is a win, above is a loss.")
        r += 1
    ws.cell(r + 1, 1, f"Run {stamp}. Each run replaces this table.").font = Font(italic=True, color="595959")


def write_waterfall_row(ws, start_row, label, values, fmt, budget=None, actual_months=0):
    """Append one row of pasted VALUES under a waterfall block (first empty row)."""
    from openpyxl.styles import Font, PatternFill
    r = start_row
    while ws.cell(r, 1).value not in (None, ""):
        r += 1
    ws.cell(r, 1, label)
    for m, v in enumerate(values, 1):
        c = ws.cell(r, 1 + m, v)
        c.number_format = fmt
        if m <= actual_months:
            c.font = Font(bold=True, color="C00000" if (budget and v < budget[m - 1]) else "000000")
            c.fill = PatternFill("solid", fgColor="D9D9D9")
    return r


def main():
    ev = Ev(sys.argv[1])
    errs = ev.errors()
    print("formula errors:", len(errs))
    for e in errs[:20]:
        print("  ", e)
    hc = ev.hardcoded()
    print("hard-coded numbers in calculation tabs (not gray history):", len(hc))
    for h in hc[:20]:
        print("  ", h)
    for label, val in ev.checks():
        print(f"check: {label}: {val}")
    for y in range(1, 6):
        rev = sum(ev.v("pl.rev", m) for m in range(12 * y - 11, 12 * y + 1))
        ebitda = sum(ev.v("pl.ebitda", m) for m in range(12 * y - 11, 12 * y + 1))
        cust = "  ".join(f"{s} {ev.v(f'{s}.end', 12 * y):,.0f}" for s in ev.segments())
        print(f"year {y}: revenue {rev:,.0f}  EBITDA {ebitda:,.0f}  cash {ev.v('cf.end', 12 * y):,.0f}  active customers: {cust}  people {ev.v('team.heads', 12 * y):,.1f}")
    m = ev.metrics()
    print(f"lowest cash {m['low']:,.0f} (month {m['low_month']}); founders' share at m60 {ev.v('fund.share', MONTHS):.1%}; founders' value {m['fv60']:,.0f}")
    for rid, (sh, row) in ev.rows.items():
        if rid.startswith("ue.") and rid.endswith(".cac"):
            vals = [ev.w.value(sh, f"{c}{row}") for c in "ABCDE"]
            f = lambda v, spec: format(v, spec) if isinstance(v, (int, float)) else str(v)
            print(f"unit economics: {vals[0]}: CAC {f(vals[1], ',.2f')}  payback {f(vals[2], '.1f')} mo  LTV/CAC {f(vals[3], '.2f')}  {vals[4]}")
        if rid.startswith("ue.") and rid.endswith(".ltv"):
            print(f"unit economics: {rid}: LTV {ev.w.value(sh, f'B{row}'):,.2f}")


if __name__ == "__main__":
    main()

"""The monthly update: reconcile a closed month, then record it as history.

Reconcile first (nothing is saved; repeat until the model reproduces the month):

    UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python monthly_update.py model.xlsx --month 3 --compare \\
        --set clinics.churn=0.018 --actual clinics.google.new=11 --actual pl.rev=24100

Then record (writes a NEW file; the old one is the previous version, never overwritten):

    UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python monthly_update.py model.xlsx --month 3 --out model-m03.xlsx \\
        --set clinics.churn=0.018 --actual clinics.google.new=11 --actual clinics.sub.rev=21500 ...

--set    an assumption id (see the hidden _rows tab, kind=input) = new value. Yearly
         inputs take five comma-separated values (or one value for all five years).
--actual a row id (kind=row) = the actual number for that month. Recording types it
         over the formula and grays the cell: history never recalculates.

Recording also grays the month's header, appends one row to each waterfall (actual
months to the left, red when below budget; the new forecast to the right) and reruns
the test drive with the corrected assumptions.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys

import openpyxl
from openpyxl.styles import Font, PatternFill

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_model import FIRST_COL, MONTHS, add_charts, mcol  # noqa: E402
from drive import Ev, write_test_drive, write_waterfall_row  # noqa: E402

GRAY = PatternFill("solid", fgColor="D9D9D9")


def parse_kv(items):
    out = {}
    for it in items or []:
        k, v = it.split("=", 1)
        out[k.strip()] = [float(x) for x in v.split(",")]
    return out


def apply_sets(wb, ev, sets):
    for iid, vals in sets.items():
        cells = ev.input_cells(iid)
        if len(vals) == 1 and len(cells) > 1:
            vals = vals * len(cells)
        if len(vals) != len(cells):
            sys.exit(f"{iid} takes {len(cells)} values, got {len(vals)}")
        for (sh, c), v in zip(cells, vals):
            wb[sh][c].value = v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--month", type=int, required=True)
    ap.add_argument("--set", action="append")
    ap.add_argument("--actual", action="append")
    ap.add_argument("--compare", action="store_true", help="print model vs actual for the month; save nothing")
    ap.add_argument("--out")
    a = ap.parse_args()
    k = a.month
    sets, acts = parse_kv(a.set), parse_kv(a.actual)

    ev = Ev(a.model)
    wb = openpyxl.load_workbook(a.model)
    apply_sets(wb, ev, sets)

    if a.compare:
        for iid, vals in sets.items():
            cells = ev.input_cells(iid)
            vals = vals * len(cells) if len(vals) == 1 and len(cells) > 1 else vals
            for (sh, c), v in zip(cells, vals):
                ev.w.set(sh, c, v)
        print(f"month {k}: model vs actual (with the --set changes applied)")
        worst = 0
        for rid, (actual,) in acts.items():
            model = ev.v(rid, k)
            diff = (model - actual) / actual if actual else 0
            worst = max(worst, abs(diff))
            print(f"  {rid:40s} model {model:14,.1f}   actual {actual:14,.1f}   {diff:+.1%}")
        print(f"largest gap {worst:.1%}. Fix assumptions until the gaps are small, then record with --out.")
        return

    if not a.out or os.path.abspath(a.out) == os.path.abspath(a.model):
        sys.exit("recording needs --out with a NEW file name: duplicate first, keep the old version")

    # budget rows, read before anything changes
    wsw = wb["Waterfalls"]
    budget = {}
    for rid, (sh, row) in ev.rows.items():
        if rid.startswith("wf."):
            budget[rid[3:]] = (row, [wsw.cell(row, 1 + m).value for m in range(1, 13)])

    for rid, (val,) in acts.items():
        # an actual is typed at its SOURCE row: new customers per channel live on the
        # Acquisition tab (the Customers row only references it), so both tabs agree
        if rid.endswith(".newc"):
            rid = rid[:-1]
        sh, row = ev.rows[rid]
        c = wb[sh].cell(row, FIRST_COL + k - 1)
        c.value, c.fill = val, GRAY
    for sh in ["Acquisition", "Customers", "Team", "Monthly P&L", "Monthly Balance Sheet", "Monthly Cash Flow", "Funding by month"]:
        h = wb[sh].cell(5, FIRST_COL + k - 1)
        h.fill, h.font = GRAY, Font(bold=True)

    currency = str(wb["Assumptions"][f"G{ev.inputs['starting_cash'][1][1:]}"].value or "")  # its unit column holds the currency code
    add_charts(wb, ev.rows, currency)  # openpyxl dropped the charts on load; redraw them
    if "Dashboard" in wb.sheetnames:
        add_charts(wb, ev.rows, currency, sheet="Dashboard", anchors=("H5", "H22", None))
    wb.save(a.out)

    ev2 = Ev(a.out)
    money = wb["Monthly P&L"].cell(ev.rows["pl.rev"][1], FIRST_COL).number_format
    vals = ev2.waterfall_values()
    stamp = dt.date.today().isoformat()
    for key, (start, bud) in budget.items():
        write_waterfall_row(wsw, start, f"After month {k} update ({stamp})", vals[key], "#,##0" if key.startswith("cust.") else money, budget=bud, actual_months=k)
    base, rows, extra = ev2.test_drive()
    write_test_drive(wb["Test Drive"], base, rows, extra, money, stamp)
    wb.save(a.out)
    m = ev2.metrics()
    print(f"recorded month {k} -> {a.out}")
    print(f"forecast now: year-5 cash {m['cash60']:,.0f}; lowest cash {m['low']:,.0f} (month {m['low_month']}); founders' value {m['fv60']:,.0f}")
    for label, v in ev2.checks():
        if label not in ("Check",):
            print(f"check: {label}: {v}")


if __name__ == "__main__":
    main()

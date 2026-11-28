"""Regression tests for the financial-modeling generator.

    cd skills/aios/financial-modeling
    UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python tests/test_models.py

Builds every example spec and asserts behaviour from the evaluated workbook, without
trusting the workbook's own Checks tab (which these tests also prove can fail).

Born from a stranger dry run: a two-segment model summed one segment's new customers
from another segment's channels and dropped seasonality, while every check stayed
green. These tests would have failed on that build.
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts"))

import openpyxl  # noqa: E402

import build_model  # noqa: E402
from drive import Ev  # noqa: E402

EX = os.path.join(HERE, "..", "examples")
FAILS = []


def check(cond, msg):
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILS.append(msg)


def build(spec_path, out):
    sys.argv = ["build_model.py", spec_path, out]
    build_model.main()
    return json.load(open(spec_path))


def month_index(spec, year, month):
    y0, m0 = map(int, spec["company"]["start_month"].split("-"))
    return (year - y0) * 12 + (month - m0) + 1


def test_example(spec_path, tmp):
    name = os.path.basename(spec_path)
    print(f"\n{name}")
    out = os.path.join(tmp, name.replace(".json", ".xlsx"))
    spec = build(spec_path, out)
    ev = Ev(out)

    check(not ev.errors(), "no formula errors")
    check(not ev.hardcoded(), "no typed numbers in calculation tabs")
    check(all(not str(v).startswith("ERROR") for _, v in ev.checks()), "no check reports ERROR")

    # 1. each segment's new customers = the sum of ITS OWN channels (the late-binding bug)
    for seg in spec["segments"]:
        sk = seg["key"]
        worst = max(abs(ev.v(f"{sk}.new", m) - sum(ev.v(f"{sk}.{c['key']}.new", m) for c in seg["channels"])) for m in range(1, 61))
        check(worst < 1e-6, f"{sk}: new customers come from its own channels (max gap {worst:.6f})")

    # 2. seasonality lands where it is set, and nowhere else
    for seg in spec["segments"]:
        sk = seg["key"]
        sea = seg.get("seasonality")
        y = int(spec["company"]["start_month"][:4])
        m_nov, m_dec = month_index(spec, y, 11), month_index(spec, y, 12)
        if not (1 <= m_nov < m_dec <= 12):  # need Nov and Dec inside year 1 (flat spend)
            continue
        for ch in seg["channels"]:
            if ch["type"] == "organic":
                continue
            nov, dec = ev.v(f"{sk}.{ch['key']}.new", m_nov), ev.v(f"{sk}.{ch['key']}.new", m_dec)
            if not nov:
                continue  # channel not running yet in year 1
            want = (sea[11] / sea[10]) if sea else 1.0
            got = dec / nov if nov else 0
            check(abs(got - want) < 1e-9, f"{sk}.{ch['key']}: December vs November new customers = {want:.2f}x (got {got:.4f}x)")

    # 3. unit economics against an independent hand computation from the spec
    team = spec["team"]
    for seg in spec["segments"]:
        sk = seg["key"]
        pct = sum(v["pct_of_revenue"] for v in seg.get("variable_costs", []) if "pct_of_revenue" in v)
        con = sum(l["qty"] * l["price"] * (l["margin"] - pct) for l in seg["revenue_lines"] if l["basis"] == "active")
        con -= sum(v["per_active_customer"] for v in seg.get("variable_costs", []) if "per_active_customer" in v)
        con -= sum(r["monthly_salary"] * (1 + team["benefits_load"]) / r["customers_per_person"] for r in team.get("customer_driven_roles", []) if r["segment"] == sk)
        one = sum(l["qty"] * l["price"] * (l["margin"] - pct) for l in seg["revenue_lines"] if l["basis"] == "new")
        one -= sum(v["per_new_customer"] for v in seg.get("variable_costs", []) if "per_new_customer" in v)
        ltv = con * min(120, 1 / seg["monthly_churn"]) + one
        sh, row = ev.rows[f"ue.{sk}.ltv"]
        got = ev.w.value(sh, f"B{row}")
        check(abs(got - ltv) < 0.01, f"{sk}: LTV {got:,.2f} matches hand computation {ltv:,.2f}")
        for ch in seg["channels"]:
            if ch["type"] == "organic":
                continue
            cac = ch["cost_per_click"] / ch["conversion"] if ch["type"] == "paid" else ch["cost_per_unit"] / ch["yield_per_unit"]
            sh, row = ev.rows[f"ue.{sk}.{ch['key']}.cac"]
            got = ev.w.value(sh, f"B{row}")
            check(abs(got - cac) < 0.01, f"{sk}.{ch['key']}: CAC {got:,.2f} matches {cac:,.2f}")
            pay = ev.w.value(sh, f"C{row}")
            want = 0 if cac <= one else (999 if con <= 0 else (cac - one) / con)
            check(isinstance(pay, (int, float)) and abs(pay - want) < 0.01, f"{sk}.{ch['key']}: payback {pay} matches {want:.2f} months (no error, even with no recurring revenue)")

    # 4. the guards can fail: break the workbook two ways and watch the Checks tab turn red
    seg = spec["segments"][0]
    for label, mutate in [
        ("segment check catches new customers taken from the wrong rows",
         lambda wb, e: _set_formula(wb, e, f"{seg['key']}.new", 5, "=0")),
        ("balance-sheet check catches a cash flow that forgets a balance-sheet movement",
         lambda wb, e: _set_formula(wb, e, "cf.ar", 7, "=0")),
    ]:
        bad = os.path.join(tmp, "mutant-" + name.replace(".json", ".xlsx"))
        shutil.copy(out, bad)
        wb = openpyxl.load_workbook(bad)
        mutate(wb, ev)
        wb.save(bad)
        evb = Ev(bad)
        check(any(str(v).startswith("ERROR") for _, v in evb.checks()), label)
        check(str(evb.w.value("Checks", "B4")).startswith("ERRORS"), f"{label}: Overall says ERRORS")
    # 6. every input has a workbook name, and calculation tabs read inputs only through names
    wbf = openpyxl.load_workbook(out)
    names = {n.lower() for n in wbf.defined_names}
    missing = [i for i in ev.inputs if build_model.Model.name_of(i) not in names]
    check(not missing, f"every input has a name ({len(missing)} missing)")
    direct = [f"{ws.title}!{c.coordinate}" for ws in wbf.worksheets if ws.title not in ("Assumptions", "_rows", "README")
              for row in ws.iter_rows() for c in row if isinstance(c.value, str) and c.value.startswith("=") and "Assumptions'!" in c.value]
    check(not direct, f"no formula reads Assumptions by address ({direct[:2]})")

    # 7. the scenario switch moves the model the right way
    if "scenario" in ev.inputs:
        res = {}
        for sc in ("Pessimistic", "Base", "Optimistic"):
            ev.w.reset()
            ev.w.set(*ev.inputs["scenario"], sc)
            res[sc] = ev.metrics()["cash60"]
        ev.w.reset()
        check(res["Pessimistic"] < res["Base"] < res["Optimistic"], f"scenario switch: pessimistic < base < optimistic year-5 cash ({res['Pessimistic']:,.0f} < {res['Base']:,.0f} < {res['Optimistic']:,.0f})")

    # 8. the Dashboard agrees with the engine
    d = ev.w.wb["Dashboard"]
    rows = {d.cell(r, 1).value: r for r in range(1, d.max_row + 1) if d.cell(r, 1).value}
    check(abs(ev.w.value("Dashboard", f"F{rows['Cash at year end']}") - ev.v("cf.end", 60)) < 0.01, "Dashboard year-5 cash = Monthly Cash Flow month 60")
    eb = [ev.v("pl.ebitda", m) for m in range(1, 61)]
    want = next((m for m in range(1, 61) if all(x > 0 for x in eb[m - 1:])), "not within five years")
    got = ev.w.value("Dashboard", f"B{rows['Break-even month (profitable from then on)']}")
    check(got == want, f"Dashboard break-even month {got} = first month EBITDA stays positive ({want})")
    mo = spec["funding"]["rounds"][0]["month"]
    win = range(mo, min(61, mo + 18))
    burn = max(0, sum(ev.v("pl.costs", m) for m in win) - sum(ev.v("pl.rev", m) for m in win))
    fz = ev.w.wb["Funding"]
    r_b = next(r for r in range(1, fz.max_row + 1) if str(fz.cell(r, 1).value or "").startswith("Burn the round has to cover"))  # round 1's
    check(abs(ev.w.value("Funding", f"B{r_b}") - burn) < 0.01, f"Funding: burn the first round covers = spending − revenue in its 18 months ({burn:,.0f})")

    # 11. ownership, round pricing, and a round of zero
    r_t = next(r for r in range(1, fz.max_row + 1) if fz.cell(r, 1).value == "Total (must be 100%)")
    tots = [ev.w.value("Funding", f"{chr(66 + k)}{r_t}") for k in range(len(spec["funding"]["rounds"]) + 1)]
    check(all(abs(t - 1) < 1e-9 for t in tots), f"who owns what adds to 100% at the start and after every round ({[round(t, 6) for t in tots]})")
    rounds = spec["funding"]["rounds"]
    pr = next((n for n, rd in enumerate(rounds, 1) if rd["type"] == "priced"), None)
    if pr:
        mo = rounds[pr - 1]["month"]
        ev.w.reset()
        ev.w.set(*ev.inputs[f"round.{pr}.price"], 0)          # price it at the revenue multiple
        recurring = sum(ev.v(f"pl.rev.{sg['key']}.{l['key']}", mo - 1) for sg in spec["segments"] for l in sg["revenue_lines"] if l["basis"] == "active")
        base_rev = recurring if recurring else ev.v("pl.rev", mo - 1)
        want = max(1, spec["funding"].get("valuation_multiple", 5) * base_rev * 12)
        got = ev.v(f"round.{pr}.pre", mo)
        check(abs(got - want) < 0.01, f"an unpriced round is valued at multiple × last month's recurring revenue × 12, no cash added ({got:,.0f} vs {want:,.0f})")
        ev.w.reset()
        before = ev.v("fund.share", mo - 1) if mo > 1 else ev.w.value(*ev.input_cells("founders_share0")[0])
        ev.w.set(*ev.inputs[f"round.{pr}.amount"], 0)          # a placeholder round of 0
        check(abs(ev.v("fund.share", mo) - before) < 1e-12, "a priced round of 0 dilutes nobody (its option pool waits for money)")
        ev.w.reset()

    # 9. hires by month: nobody before the start month
    for role in spec["team"]["roles"]:
        if "start_month" in role:
            sm = role["start_month"]
            check(ev.v(f"role.{role['key']}.n", sm - 1) == 0 and ev.v(f"role.{role['key']}.n", sm) == role.get("count", 1), f"role {role['key']} starts in month {sm}, not before")

    # 10. the impact map comes from the formula graph
    ws_a = wbf["Assumptions"]
    sh, cell = ev.inputs[f"{spec['segments'][0]['key']}.churn"]
    txt = str(ws_a.cell(int(cell[1:]), 11).value)
    check("Customers" in txt and "Monthly Cash Flow" in txt, f"impact map: churn moves Customers and, downstream, cash ({txt[:60]}...)")

    # 12. the Google Sheets lock script lists exactly the tabs the workbook locks
    gs = out[:-5] + "-lock-calc-tabs.gs"
    if os.path.exists(gs):
        import re as _re
        listed = json.loads(_re.search(r"const LOCKED_TABS = (\[.*?\]);", open(gs).read()).group(1))
        locked = [w.title for w in wbf.worksheets if w.protection.sheet]
        check(listed == locked and "Assumptions" not in listed, f"lock script covers the {len(locked)} calculated tabs and leaves Assumptions editable")
    else:
        check(False, "build wrote the Google Sheets lock script")

    # 5. the monthly update records a month without breaking any check
    seg = spec["segments"][0]
    ch = seg["channels"][0]
    m1 = os.path.join(tmp, "m01-" + name.replace(".json", ".xlsx"))
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(HERE, "..", "scripts", "monthly_update.py"), out, "--month", "1", "--out", m1,
                        "--actual", f"{seg['key']}.{ch['key']}.newc=3", "--actual", f"{seg['key']}.lost=0"], capture_output=True, text=True)
    check(r.returncode == 0, f"monthly update runs ({r.stderr.strip()[-120:]})")
    if r.returncode == 0:
        evm = Ev(m1)
        check(not evm.errors() and all(not str(v).startswith("ERROR") for _, v in evm.checks()), "after a monthly update: no formula errors and no check reads ERROR")
        check(abs(evm.v(f"{seg['key']}.new", 1) - (3 + sum(evm.v(f"{seg['key']}.{c['key']}.new", 1) for c in seg["channels"][1:]))) < 1e-9,
              "the recorded actual lands at its source and flows into the segment's new customers")
    return ev


def _set_formula(wb, ev, rid, m, formula):
    sh, row = ev.rows[rid]
    wb[sh].cell(row, build_model.FIRST_COL + m - 1).value = formula


def main():
    tmp = tempfile.mkdtemp(prefix="fm-test-")
    specs = sorted(os.path.join(EX, f) for f in os.listdir(EX) if f.endswith(".json"))
    check(len(specs) >= 2, f"at least two example businesses ({len(specs)} found)")
    shapes = set()
    for sp in specs:
        test_example(sp, tmp)
        spec = json.load(open(sp))
        shapes.add((len(spec["segments"]), tuple(sorted({c["type"] for s in spec["segments"] for c in s["channels"]}))))
    check(any(n > 1 for n, _ in shapes), "at least one example has more than one segment")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{'ALL PASS' if not FAILS else str(len(FAILS)) + ' FAILED'}")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()

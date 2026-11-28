"""Build a founder's financial model (.xlsx, live formulas) from a business spec (JSON).

    UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python build_model.py spec.json out.xlsx

The workbook follows the structure of a bottom-up venture model: one Assumptions tab
holds every input (bold blue on yellow); every other tab is formulas fed by it, monthly
for five years and rolled up to annual; three statements; unit economics per channel;
funding and founder value; charts; waterfalls; a test-drive log; live checks.

The spec describes the business, not the spreadsheet: customer segments, the channels
that bring each segment's customers (paid, organic, or an activity such as sales reps,
events or partners), the revenue lines each customer produces (recurring, per order,
one-time), the team, other costs, working capital and the funding rounds. See
../SKILL.md and ../examples/ for the schema.

After building it evaluates the formulas, writes the Waterfalls budget rows, runs the
test drive, writes the impact map and the Google Sheets lock script. drive.py is the
read-only report and check.
"""
from __future__ import annotations

import datetime as dt
import json
import sys

import openpyxl
from openpyxl.chart import LineChart, Reference
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.properties import PageSetupProperties

# ---------------------------------------------------------------- styles
BLUE = Font(name="Calibri", color="0000FF", bold=True)
BLACK = Font(name="Calibri", color="000000")
BOLD = Font(name="Calibri", bold=True)
WHITE_BOLD = Font(name="Calibri", color="FFFFFF", bold=True)
TITLE = Font(name="Calibri", size=16, bold=True, color="1F3864")
ITALIC = Font(name="Calibri", italic=True, color="595959")
F_INPUT = PatternFill("solid", fgColor="FFF2CC")
F_KEY = PatternFill("solid", fgColor="F8CBAD")
F_HIST = PatternFill("solid", fgColor="D9D9D9")
F_HEAD = PatternFill("solid", fgColor="1F3864")
F_SECTION = PatternFill("solid", fgColor="D9E1F2")
F_LOCK = PatternFill("solid", fgColor="EDEDED")
F_TOTAL = PatternFill("solid", fgColor="F2F2F2")
TOP = Border(top=Side(style="thin", color="7F7F7F"))
WRAP = Alignment(wrap_text=True, vertical="top")

MONTHS = 60
FIRST_COL = 3  # column C holds month 1 / year 1
UOF = [("sm", "Sales and marketing"), ("team", "Team (planned roles)"), ("direct", "Direct costs"), ("other", "Other operating costs")]


def mcol(m):
    return get_column_letter(FIRST_COL + m - 1)


def q(sheet):
    return "'" + sheet.replace("'", "''") + "'"


class Model:
    def __init__(self, spec, known=None):
        # Two passes: pass 1 (known=None) lays out every tab and registers each row's
        # number without writing monthly formulas; pass 2 writes every formula at once,
        # resolving rows defined later (beginning <- last month's ending) from pass 1.
        # Formulas are built while the loop variables are live, so no lambda can
        # capture a later segment's rows (the late-binding bug of a deferred write).
        self.known = known or {}
        self.dry = known is None
        self.s = spec
        self.wb = openpyxl.Workbook()
        self.wb.remove(self.wb.active)
        self.rows = {}  # id -> (sheet, row)
        self.inputs = {}  # id -> (sheet, cell or (row, ncols))
        self.cur = {}
        c = spec["company"]
        self.sym = {"USD": "$", "MXN": "$", "EUR": "€", "GBP": "£", "COP": "$", "BRL": "R$"}.get(c.get("currency", "USD"), "")
        self.cur_code = c.get("currency", "USD")
        self.money = f'"{self.sym}"#,##0;[Red]-"{self.sym}"#,##0' if self.sym else "#,##0;[Red]-#,##0"
        cents = self.cur_code in ("USD", "EUR", "GBP", "CAD", "AUD", "CHF")
        self.money2 = (f'"{self.sym}"#,##0.00;[Red]-"{self.sym}"#,##0.00' if cents else self.money) if self.sym else ("#,##0.00" if cents else "#,##0")
        self.key = set(spec.get("key_assumptions", []))

    # ------------------------------------------------------------ helpers
    def sheet(self, name, kind, title, purpose):
        ws = self.wb.create_sheet(name)
        ws.sheet_properties.tabColor = {"input": "FFC000", "summary": "1F3864", "calc": "A6A6A6", "log": "70AD47", "readme": "C00000"}[kind]
        ws["A1"] = title
        ws["A1"].font = TITLE
        ws["A2"] = purpose
        ws["A2"].font = ITALIC
        if kind == "input":
            ws["A3"] = "EDIT HERE: change only the bold blue cells on yellow. Every other tab recalculates from this one. Orange = the assumptions that decide this business."
            ws["A3"].fill = F_INPUT
        elif kind in ("calc", "summary"):
            ws["A3"] = "DO NOT EDIT: every number on this tab is a formula fed by Assumptions. Gray columns are history (actual months), typed in during the monthly update."
            ws["A3"].fill = F_LOCK
        elif kind == "readme":
            ws["A3"] = "START HERE: what this model is, how to read it, and how to keep it alive. The model itself starts on the Assumptions tab."
            ws["A3"].fill = F_SECTION
        else:
            ws["A3"] = "LOG: values written by the agent (or by you) as a record. Nothing else reads this tab."
            ws["A3"].fill = F_LOCK
        ws["A3"].font = BOLD
        if kind in ("calc", "summary"):
            # Locked without a password: a typo can't overwrite a formula, and the
            # monthly update unlocks it on purpose (Review > Unprotect sheet).
            ws.protection.sheet = True
        ws.sheet_view.zoomScale = 100
        self.cur[name] = 5
        return ws

    def ref(self, rid, m=None, frm=None, absolute=False):
        sh, row = self.rows[rid] if rid in self.rows else self.known[rid]
        col = mcol(m) if m is not None else "B"
        cell = f"${col}${row}" if absolute else f"{col}{row}"
        return cell if sh == frm else f"{q(sh)}!{cell}"

    @staticmethod
    def name_of(iid):
        # Every input gets a workbook name, so formulas read =clinics_churn instead of
        # Assumptions!$B$12. Names always contain "_" so none can look like a cell (A1).
        import re
        n = re.sub(r"[^A-Za-z0-9]+", "_", iid).strip("_").lower()
        return n if "_" in n else "in_" + n

    def rrange(self, rid, frm=None):
        """A row's 60 months as ONE range: 'Sheet'!$C$9:$BJ$9 (never 'Sheet'!C9:'Sheet'!BJ9)."""
        sh, row = self.rows[rid] if rid in self.rows else self.known[rid]
        r = f"${mcol(1)}${row}:${mcol(MONTHS)}${row}"
        return r if sh == frm else f"{q(sh)}!{r}"

    def iref(self, iid, frm=None, absolute=True):
        return self.name_of(iid)

    def irange(self, iid, frm=None):
        return self.name_of(iid)

    def define_names(self):
        from openpyxl.workbook.defined_name import DefinedName
        targets = {}
        for iid, (sh, cell) in self.inputs.items():
            if isinstance(cell, tuple):
                row, n = cell
                targets[iid] = f"{q(sh)}!$B${row}:${get_column_letter(1 + n)}${row}"
            else:
                targets[iid] = f"{q(sh)}!${cell[0]}${cell[1:]}"
        targets.update(self.name_override)
        for iid, target in targets.items():
            self.wb.defined_names[self.name_of(iid)] = DefinedName(self.name_of(iid), attr_text=target)

    # ------------------------------------------------------------ assumptions
    def build_assumptions(self):
        s = self.s
        ws = self.sheet("Assumptions", "input", f"{s['company']['name']}: Assumptions",
                        "Every input of the model lives here, and only here. Never type a number into a formula on another tab: add an assumption, then reference it.")
        ws.column_dimensions["A"].width = 70
        for c in "BCDEF":
            ws.column_dimensions[c].width = 18
        ws.column_dimensions["G"].width = 18
        ws.column_dimensions["H"].width = 17
        ws.column_dimensions["I"].width = 30
        ws.column_dimensions["J"].width = 90
        ws.column_dimensions["K"].width = 60
        r = 5
        for i, h in enumerate(["Assumption", "Value / Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "Unit", "Status", "Source",
                               "What it means and how the model uses it", "Moves (tabs it changes: directly, then downstream)"]):
            cell = ws.cell(r, 1 + i, h)
            cell.fill, cell.font = F_HEAD, WHITE_BOLD
        ws.freeze_panes = "B6"
        self.ws_a = ws
        from openpyxl.worksheet.datavalidation import DataValidation
        self.dv_status = DataValidation(type="list", formula1='"measured,quoted,benchmark,estimate,assumption,decided"', allow_blank=True)
        ws.add_data_validation(self.dv_status)
        statuses = s.get("input_status", {})
        # scenario switch: reserved at the top, filled once the decisive inputs' rows are known
        self.key_singles = [k for k in s.get("key_assumptions", [])]
        self.scen_top = r + 1
        self._arow = r + 1 + (len(self.key_singles) + 4 if self.key_singles else 0)
        self.name_override = {}

        def status_cells(rr, iid):
            st = statuses.get(iid, {})
            if isinstance(st, (list, tuple)):
                st = {"status": st[0], "source": st[1] if len(st) > 1 else ""}
            c = ws.cell(rr, 8, st.get("status", ""))  # blank = not stated yet; never imply a status
            self.dv_status.add(c)
            ws.cell(rr, 9, st.get("source", ""))

        def section(t):
            rr = self._arow
            ws.cell(rr, 1, t).font = BOLD
            for c in range(1, 12):
                ws.cell(rr, c).fill = F_SECTION
            self._arow += 1

        def single(iid, label, value, unit, expl, fmt=None):
            rr = self._arow
            ws.cell(rr, 1, label)
            c = ws.cell(rr, 2, value)
            c.font, c.fill = BLUE, (F_KEY if iid in self.key else F_INPUT)
            if fmt:
                c.number_format = fmt
            ws.cell(rr, 7, unit)
            status_cells(rr, iid)
            ws.cell(rr, 10, ("DECISIVE. " if iid in self.key else "") + expl)
            self.inputs[iid] = ("Assumptions", f"B{rr}")
            self._arow += 1

        def yearly(iid, label, values, unit, expl, fmt=None):
            rr = self._arow
            ws.cell(rr, 1, label)
            for j, v in enumerate(values):
                c = ws.cell(rr, 2 + j, v)
                c.font, c.fill = BLUE, (F_KEY if iid in self.key else F_INPUT)
                if fmt:
                    c.number_format = fmt
            ws.cell(rr, 7, unit)
            status_cells(rr, iid)
            ws.cell(rr, 10, ("DECISIVE. " if iid in self.key else "") + expl)
            self.inputs[iid] = ("Assumptions", (rr, 5))
            self._arow += 1

        self.single, self.yearly, self.section = single, yearly, section
        co = s["company"]
        section("Company and timeline")
        y, mth = map(int, co["start_month"].split("-"))
        single("start", "First month of the model", dt.date(y, mth, 1), "date", "Month 1 of the five-year (60-month) timeline. Change it and every tab's dates move.", "mmm yyyy")
        single("starting_cash", "Cash in the bank at the start", co.get("starting_cash", 0), self.cur_code, "Money already in the company before month 1 (founders' own money). Booked as paid-in capital.", self.money)
        single("multiple", "Revenue multiple for valuation", s["funding"].get("valuation_multiple", 5), "x annual revenue", "Used for company value and founders' value, and to price any round whose pre-money is left at 0: multiple × the previous month's RECURRING revenue × 12 (no cash added).", "0.0")

        for seg in s["segments"]:
            sk = seg["key"]
            section(f"Segment: {seg['name']}" + (f"  (one {seg['unit']} = one customer)" if seg.get("unit") and seg["unit"] != "customer" else ""))
            single(f"{sk}.start_customers", f"{seg['name']}: customers at the start", seg.get("starting_customers", 0), seg.get("unit", "customers"), "Active customers on day one (0 for a new business).", "#,##0")
            single(f"{sk}.churn", f"{seg['name']}: churn per MONTH", seg["monthly_churn"], "% per month", "Share of active customers lost each month. Always per month: 4% a month is a 25-month average life (1 ÷ churn); 4% a year would be a very different business.", "0.0%")
            for ch in seg["channels"]:
                ck = f"{sk}.{ch['key']}"
                t = ch["type"]
                if t == "paid":
                    yearly(f"{ck}.spend", f"{ch['name']}: spend per month", ch["spend_by_year"], f"{self.cur_code}/month", "Monthly budget for this channel in each year. Ramp it year by year; a flat budget for five years rarely makes sense. This is usually the biggest lever.", self.money)
                    single(f"{ck}.cpc", f"{ch['name']}: cost per click or lead", ch["cost_per_click"], self.cur_code, "What one visitor or lead from this channel costs. Spend ÷ this = visitors.", self.money2)
                    single(f"{ck}.conv", f"{ch['name']}: conversion to customer", ch["conversion"], "%", "Share of those visitors who become paying customers. Every point here is free money: it costs nothing extra.", "0.00%")
                elif t == "organic":
                    single(f"{ck}.visits", f"{ch['name']}: visitors in month 1", ch["start_visits"], "visitors/month", "Free traffic (search, word of mouth, referrals) in the first month.", "#,##0")
                    single(f"{ck}.growth", f"{ch['name']}: monthly growth of free traffic", ch["monthly_growth"], "% per month", "How fast free traffic compounds. Keep it modest; it is the easiest number to flatter.", "0.0%")
                    single(f"{ck}.conv", f"{ch['name']}: conversion to customer", ch["conversion"], "%", "Share of free visitors who become customers.", "0.00%")
                elif t == "activity":
                    us = ch.get("unit_singular", "unit")
                    yearly(f"{ck}.count", f"{ch['name']}: number of {ch.get('unit_label', 'units')}", ch["count_by_year"], "in a month", ch.get("count_help", "How many run in a month, by year: reps on staff, events held, partners live."), "#,##0.0")
                    single(f"{ck}.yield", f"{ch['name']}: new customers per {us}", ch["yield_per_unit"], "customers", ch.get("yield_help", f"New customers one {us} brings in, each month it runs. The result, not the activity behind it (closes per rep, not calls per rep)."), "#,##0.00")
                    single(f"{ck}.cost", f"{ch['name']}: cost per {us}", ch["cost_per_unit"], self.cur_code, ch.get("cost_help", f"Fully loaded cost of one {us} for a month (a rep's salary plus taxes and benefits; an event's venue, samples and staff)."), self.money)
            for ln in seg["revenue_lines"]:
                lk = f"{sk}.{ln['key']}"
                basis = "each ACTIVE customer per month" if ln["basis"] == "active" else "each NEW customer, once"
                single(f"{lk}.qty", f"{ln['name']}: {ln.get('qty_label', 'units per customer')}", ln["qty"], ln.get("qty_unit", "per customer"), f"How many units {basis} buys (1 for a plain subscription; orders per month for repeat purchases; an attach rate such as 0.3 for an add-on).", "#,##0.00")
                single(f"{lk}.price", f"{ln['name']}: price per unit", ln["price"], self.cur_code, "Price of one unit. A price change moves contribution per unit; the cash effect is that change × units sold.", self.money2)
                single(f"{lk}.margin", f"{ln['name']}: gross margin", ln["margin"], "%", "Share of the price left after the direct cost of delivering it. Revenue × (1 − margin) = direct cost.", "0.0%")
            for vc in seg.get("variable_costs", []):
                if "per_new_customer" in vc:
                    single(f"{sk}.vc.{vc['key']}", f"{vc['name']} per new customer", vc["per_new_customer"], self.cur_code, "A one-time direct cost each time a customer joins (a background check, a welcome kit, onboarding hardware).", self.money2)
                elif "pct_of_revenue" in vc:
                    single(f"{sk}.vc.{vc['key']}", f"{vc['name']} (share of this segment's revenue)", vc["pct_of_revenue"], "% of revenue", "A direct cost that is a share of every sale in this segment (a partner's or affiliate's commission, card fees, a platform's cut).", "0.0%")
                else:
                    single(f"{sk}.vc.{vc['key']}", f"{vc['name']} per active customer per month", vc["per_active_customer"], f"{self.cur_code}/month", "A direct cost that grows with active customers (hosting, packaging).", self.money2)
            sea = seg.get("seasonality")
            if sea:
                scope = "new customers and reorders" if seg.get("seasonality_applies_to") == "new_and_orders" else "new customers"
                section(f"{seg['name']}: seasonality of {scope} (1.00 = a normal month)")
                for k, name in enumerate(["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]):
                    single(f"{sk}.season.{k + 1}", f"  {name}", sea[k], "x", f"Multiplies {scope} in this calendar month. Learned from real data, never guessed twice.", "0.00")
                a, b = self.inputs[f"{sk}.season.1"][1][1:], self.inputs[f"{sk}.season.12"][1][1:]
                self.name_override[f"{sk}.season"] = f"{q('Assumptions')}!$B${a}:$B${b}"

        section("Team (people by year, or a start and end month)")
        team = s["team"]
        for role in team["roles"]:
            rk = role["key"]
            if "start_month" in role:
                single(f"role.{rk}.n", f"{role['name']}: people", role.get("count", 1), "people", "How many people hold this role while it is active.", "#,##0.0")
                single(f"role.{rk}.start", f"{role['name']}: first month", role["start_month"], "month #", "The month (1 to 60) the hire starts. Hiring timing moves runway more than almost anything else. Salaries are in year-1 money: a hire in year 2 is paid salary × (1 + raise).", "0")
                single(f"role.{rk}.end", f"{role['name']}: last month", role.get("end_month", 60), "month #", "The last month in the role (60 = through the plan).", "0")
            else:
                yearly(f"role.{rk}.count", f"{role['name']}: people", role["count_by_year"], "people", "Headcount in each year of the plan.", "#,##0.0")
        section("Team (monthly salary per person)")
        for role in team["roles"]:
            single(f"role.{role['key']}.salary", f"{role['name']}: monthly salary", role["monthly_salary"], f"{self.cur_code}/month", "Gross monthly salary per person, before taxes and benefits.", self.money)
        for cr in team.get("customer_driven_roles", []):
            single(f"crole.{cr['key']}.salary", f"{cr['name']}: monthly salary", cr["monthly_salary"], f"{self.cur_code}/month", "Salary of a role that grows with customers. Booked as a direct cost: twice the customers needs twice the people.", self.money)
            single(f"crole.{cr['key']}.ratio", f"{cr['name']}: customers per person", cr["customers_per_person"], "customers", "One more person is hired for each block of this many active customers.", "#,##0")
        single("benefits", "Taxes and benefits on salaries", team.get("benefits_load", 0.25), "% of salary", "Employer taxes, insurance and benefits, added on top of every salary (not on the loaded cost of activity units, which already include it).", "0.0%")
        single("raise", "Yearly salary raise", team.get("annual_raise", 0), "% per year", "Every salary grows by this each new year of the plan (year 2 = salary × (1 + raise)).", "0.0%")
        section("Other operating costs")
        for k, (name, val) in enumerate(team.get("per_employee_monthly", {}).items()):
            single(f"pe.{k}", f"{name} per employee per month", val, f"{self.cur_code}/month", "Scales with total headcount.", self.money)
        for k, (name, val) in enumerate(team.get("fixed_monthly", {}).items()):
            single(f"fx.{k}", f"{name} per month", val, f"{self.cur_code}/month", "A fixed monthly cost.", self.money)
        section("Working capital and tax")
        wc = s.get("working_capital", {})
        single("ar_days", "Days customers take to pay (receivables)", wc.get("ar_days", 0), "days", "0 for card payments. Every extra day lends your customers money: the income statement doesn't move, the cash does.", "0")
        single("ap_days", "Days you take to pay suppliers (payables)", wc.get("ap_days", 0), "days", "Applies to non-payroll costs. Paying faster than this drains cash; payroll is always paid in the month.", "0")
        single("inv_days", "Days of inventory on hand", wc.get("inventory_days", 0), "days", "Stock held, in days of direct product cost. 0 for software and services.", "0")
        single("tax", "Income tax rate", s.get("tax", {}).get("rate", 0), "%", "Applied to profit only after earlier losses are used up (a simple loss carry-forward).", "0.0%")
        ob = co.get("opening_balances", {})
        section("Opening balances (a business that already exists; 0 for a new one)")
        single("open_ar", "Receivables customers already owe you", ob.get("receivables", 0), self.cur_code, "Invoices already issued and not yet collected on day one. Without this, an existing business shows a false cash drain in month 1.", self.money)
        single("open_inv", "Inventory already on hand", ob.get("inventory", 0), self.cur_code, "Stock already bought, valued at cost.", self.money)
        single("open_ap", "Payables you already owe suppliers", ob.get("payables", 0), self.cur_code, "Supplier bills already received and not yet paid.", self.money)
        section("Funding rounds")
        single("min_cash", "Minimum cash to keep in the bank", s["funding"].get("minimum_cash", 0), self.cur_code, "The floor you never want to cross (about three months of costs is common). The Checks tab warns when cash falls below it; the Funding tab says when.", self.money)
        single("founders_share0", "Founders' ownership at the start", s["funding"].get("founders_initial_share", 1.0), "%", "Founders' fully diluted share before the first round below.", "0.0%")
        for k, rd in enumerate(s["funding"]["rounds"]):
            n = k + 1
            ws.cell(self._arow, 1, f"Round {n}: {rd['name']}").font = BOLD
            self._arow += 1
            ws.cell(self._arow, 1, "  Instrument")
            ws.cell(self._arow, 2, "SAFE (post-money cap)" if rd["type"] == "safe" else "Priced round")
            ws.cell(self._arow, 10, "Set in the model's spec (type: safe or priced); change it there and rebuild. A post-money SAFE takes amount ÷ cap of the company when signed. A priced round takes amount ÷ (pre-money + amount), plus the option pool it creates.")
            self._arow += 1
            single(f"round.{n}.month", "  Month it closes", rd["month"], "month #", "Month number on the timeline (1 to 60) when the money lands in the bank.", "0")
            single(f"round.{n}.amount", "  Amount raised", rd["amount"], self.cur_code, "Cash in. Never revenue: it reaches the bank through the cash flow statement only.", self.money)
            single(f"round.{n}.price", "  Post-money cap (SAFE) or pre-money (priced; 0 = use revenue multiple)", rd.get("cap", rd.get("pre_money", 0)), self.cur_code, "Ask this first. The same amount at a different price is a different deal.", self.money)
            single(f"round.{n}.pool", "  Option pool created (priced rounds)", rd.get("option_pool", 0), "% post-money", "New options set aside for the team at this round; they dilute existing holders.", "0.0%")
            uof = rd.get("use_of_funds")
            if uof:
                for ck, cname in UOF:
                    single(f"round.{n}.uof.{ck}", f"  Planned use of funds: {cname}", uof.get(ck, 0), "% of the round", "The founder's plan for this round's money. The Funding tab sets it against what the model actually spends in the 18 months after the close.", "0%")
        self.n_rounds = len(s["funding"]["rounds"])
        self.loans = s["funding"].get("loans", [])
        if self.loans:
            section("Loans (repaid in one payment)")
        for k, ln in enumerate(self.loans):
            n = k + 1
            ws.cell(self._arow, 1, f"Loan {n}: {ln['name']}").font = BOLD
            self._arow += 1
            single(f"loan.{n}.month_in", "  Month the money arrives (0 = already received)", ln.get("month_in", 0), "month #", "0 means the money is already in 'Cash in the bank at the start'. Otherwise the month (1 to 60) it lands.", "0")
            single(f"loan.{n}.amount", "  Amount", ln["amount"], self.cur_code, "Borrowed money: a liability, never revenue and never equity.", self.money)
            single(f"loan.{n}.month_out", "  Month it is repaid (in one payment)", ln["month_repaid"], "month #", "The month the whole amount goes back. Set beyond 60 if it is repaid after the plan.", "0")
            single(f"loan.{n}.rate", "  Interest rate per year", ln.get("annual_rate", 0), "% per year", "Interest is charged monthly on the amount outstanding and booked below operating profit.", "0.0%")
        self.build_scenarios()

    def build_scenarios(self):
        """Pessimistic / Base / Optimistic for the decisive single inputs, switched in one cell.
        The input's name points at the 'In use' cell, so every formula follows the switch;
        the base value stays in its own row below, where the monthly update edits it."""
        keys = [k for k in self.key_singles if k in self.inputs and not isinstance(self.inputs[k][1], tuple)]
        if not keys:
            return
        from openpyxl.worksheet.datavalidation import DataValidation
        ws, r = self.ws_a, self.scen_top
        ws.cell(r, 1, "Scenario: the decisive inputs, switched in one cell").font = BOLD
        for c in range(1, 12):
            ws.cell(r, c).fill = F_SECTION
        r += 1
        ws.cell(r, 1, "Scenario in use (Pessimistic, Base or Optimistic)")
        sel = ws.cell(r, 2, "Base")
        sel.font, sel.fill = BLUE, F_KEY
        dv = DataValidation(type="list", formula1='"Pessimistic,Base,Optimistic"', allow_blank=False)
        ws.add_data_validation(dv)
        dv.add(sel)
        ws.cell(r, 10, "Pick a scenario and the whole model recalculates with the decisive inputs set to that column. Show the downside live, then switch back to Base.")
        self.inputs["scenario"] = ("Assumptions", f"B{r}")
        r += 1
        for i, h in enumerate(["Decisive input", "In use", "Pessimistic", "Optimistic", "Base (its row below)"]):
            c = ws.cell(r, 1 + i, h)
            c.fill, c.font = F_HEAD, WHITE_BOLD
        r += 1
        worse_if_higher = ("churn", "cpc", "cost", "ar_days", "inv_days")
        scen = self.s.get("scenarios", {})
        for k in keys:
            base_cell = self.inputs[k][1]
            row = int(base_cell[1:])
            fmt = ws.cell(row, 2).number_format
            base_v = ws.cell(row, 2).value
            up_bad = k.split(".")[-1] in worse_if_higher
            pess, opt = scen.get(k, [base_v * (1.25 if up_bad else 0.75), base_v * (0.75 if up_bad else 1.25)])
            ws.cell(r, 1, ws.cell(row, 1).value)
            use = ws.cell(r, 2, f'=IF({self.name_of("scenario")}="Pessimistic",C{r},IF({self.name_of("scenario")}="Optimistic",D{r},E{r}))')
            use.font, use.number_format = BOLD, fmt
            for col, v in ((3, pess), (4, opt)):
                c = ws.cell(r, col, v)
                c.font, c.fill, c.number_format = BLUE, F_INPUT, fmt
            b = ws.cell(r, 5, f"={base_cell}")
            b.number_format = fmt
            ws.cell(r, 10, "In use = the column the switch picks. Pessimistic and optimistic default to 25% worse and better; set them to what you can defend.")
            self.name_override[k] = f"{q('Assumptions')}!$B${r}"
            self.inputs[f"{k}.pess"] = ("Assumptions", f"C{r}")
            self.inputs[f"{k}.opt"] = ("Assumptions", f"D{r}")
            r += 1

    # ------------------------------------------------------------ monthly sheets
    def monthly(self, name, title, purpose, kind="calc"):
        ws = self.sheet(name, kind, title, purpose)
        ws.column_dimensions["A"].width = 44
        ws.column_dimensions["B"].width = 58
        for m in range(1, MONTHS + 1):
            ws.column_dimensions[mcol(m)].width = 14
        r = 5
        ws.cell(r, 1, "Line item").font = WHITE_BOLD
        ws.cell(r, 2, "How it's calculated").font = WHITE_BOLD
        for c in range(1, FIRST_COL + MONTHS):
            ws.cell(r, c).fill = F_HEAD
        for m in range(1, MONTHS + 1):
            c = ws.cell(r, FIRST_COL + m - 1, f"=DATE(YEAR({self.iref('start', name)}),MONTH({self.iref('start', name)})+{m - 1},1)")
            c.number_format, c.font = "mmm yy", WHITE_BOLD
        ws.cell(6, 1, "Month #").font = ITALIC
        ws.cell(7, 1, "Year #").font = ITALIC
        for m in range(1, MONTHS + 1):
            ws.cell(6, FIRST_COL + m - 1, m).font = ITALIC
            ws.cell(7, FIRST_COL + m - 1, f"=ROUNDUP({mcol(m)}6/12,0)").font = ITALIC
        self.rows[f"{name}.month"] = (name, 6)
        self.rows[f"{name}.year"] = (name, 7)
        ws.freeze_panes = ws.cell(8, FIRST_COL)
        self.cur[name] = 8
        return ws

    def section_row(self, ws, text):
        r = self.cur[ws.title]
        ws.cell(r, 1, text).font = BOLD
        for c in range(1, FIRST_COL + MONTHS):
            ws.cell(r, c).fill = F_SECTION
        self.cur[ws.title] = r + 1

    def mrow(self, ws, rid, label, expl, fn, fmt=None, total=False):
        r = self.cur[ws.title]
        ws.cell(r, 1, label).font = BOLD if total else BLACK
        ws.cell(r, 2, expl).font = ITALIC
        self.rows[rid] = (ws.title, r)
        for m in range(1, MONTHS + 1):
            c = ws.cell(r, FIRST_COL + m - 1, None if self.dry else fn(m))
            c.number_format = fmt or self.money
            if total:
                c.font, c.border, c.fill = BOLD, TOP, F_TOTAL
        if total:
            ws.cell(r, 1).fill = F_TOTAL
            ws.cell(r, 2).fill = F_TOTAL
        self.cur[ws.title] = r + 1
        return r

    def blank(self, ws):
        self.cur[ws.title] += 1

    def yidx(self, iid, sheet, m):
        return f"INDEX({self.irange(iid, sheet)},{mcol(m)}$7)"

    # ------------------------------------------------------------ acquisition
    def build_acquisition(self):
        N = "Acquisition"
        ws = self.monthly(N, "Acquisition: where new customers come from", "Each channel's lever (spend, free traffic, or an activity such as reps, events or partners) times its conversion gives new customers. This is where the model earns its keep.")
        for seg in self.s["segments"]:
            sk = seg["key"]
            self.section_row(ws, f"Segment: {seg['name']}")
            if seg.get("seasonality"):
                rng = self.name_of(sk + ".season")
                self.mrow(ws, f"{sk}.season", "Seasonality factor", "Calendar month's factor from Assumptions; multiplies new customers from every channel.",
                          lambda m: f"=INDEX({rng},MONTH({mcol(m)}$5))", "0.00")
                sea = lambda m: f"*{self.ref(sk + '.season', m, N)}"
            else:
                sea = lambda m: ""
            for ch in seg["channels"]:
                ck = f"{sk}.{ch['key']}"
                t = ch["type"]
                if t == "paid":
                    self.mrow(ws, f"{ck}.spend", f"{ch['name']}: spend", "This year's monthly budget from Assumptions.", lambda m, ck=ck: f"={self.yidx(ck + '.spend', N, m)}")
                    self.mrow(ws, f"{ck}.visits", f"{ch['name']}: visitors", "Spend ÷ cost per click or lead.", lambda m, ck=ck: f"={self.ref(ck + '.spend', m, N)}/{self.iref(ck + '.cpc', N)}", "#,##0")
                    self.mrow(ws, f"{ck}.new", f"{ch['name']}: new customers", "Visitors × conversion × seasonality.", lambda m, ck=ck: f"={self.ref(ck + '.visits', m, N)}*{self.iref(ck + '.conv', N)}{sea(m)}", "#,##0.0")
                elif t == "organic":
                    self.mrow(ws, f"{ck}.visits", f"{ch['name']}: visitors", "Month-1 free visitors compounding at the monthly growth rate.", lambda m, ck=ck: f"={self.iref(ck + '.visits', N)}*(1+{self.iref(ck + '.growth', N)})^({mcol(m)}$6-1)", "#,##0")
                    self.mrow(ws, f"{ck}.new", f"{ch['name']}: new customers", "Free visitors × conversion × seasonality. No acquisition cost.", lambda m, ck=ck: f"={self.ref(ck + '.visits', m, N)}*{self.iref(ck + '.conv', N)}{sea(m)}", "#,##0.0")
                else:
                    self.mrow(ws, f"{ck}.count", f"{ch['name']}: {ch.get('unit_label', 'units')}", "This year's count from Assumptions.", lambda m, ck=ck: f"={self.yidx(ck + '.count', N, m)}", "#,##0.0")
                    self.mrow(ws, f"{ck}.new", f"{ch['name']}: new customers", "Units × new customers per unit × seasonality.", lambda m, ck=ck: f"={self.ref(ck + '.count', m, N)}*{self.iref(ck + '.yield', N)}{sea(m)}", "#,##0.0")
                    self.mrow(ws, f"{ck}.cost", f"{ch['name']}: cost", "Units × loaded monthly cost per unit. Booked in sales and marketing.", lambda m, ck=ck: f"={self.ref(ck + '.count', m, N)}*{self.iref(ck + '.cost', N)}")
            self.blank(ws)

    # ------------------------------------------------------------ customers and revenue
    def build_customers(self):
        N = "Customers"
        ws = self.monthly(N, "Customers and revenue", "Customers at the end of a month = beginning + new − lost. Revenue = the customers who buy × units each × price. Built for one month, then dragged across: that is the whole trick of a recurring model.")
        for seg in self.s["segments"]:
            sk = seg["key"]
            self.section_row(ws, f"Segment: {seg['name']}")
            self.mrow(ws, f"{sk}.begin", "Customers at start of month", "Last month's ending customers (month 1: customers at the start, from Assumptions).",
                      lambda m, sk=sk: f"={self.iref(sk + '.start_customers', N)}" if m == 1 else f"={self.ref(sk + '.end', m - 1, N)}", "#,##0.0")
            for ch in seg["channels"]:
                ck = f"{sk}.{ch['key']}"
                self.mrow(ws, f"{ck}.newc", f"  New from {ch['name']}", "From the Acquisition tab.", lambda m, ck=ck: f"={self.ref(ck + '.new', m, N)}", "#,##0.0")
            first = self.rows[f"{sk}.{seg['channels'][0]['key']}.newc"][1]
            last = self.rows[f"{sk}.{seg['channels'][-1]['key']}.newc"][1]
            self.mrow(ws, f"{sk}.new", "New customers", "Sum of new customers from every channel.", lambda m: f"=SUM({mcol(m)}{first}:{mcol(m)}{last})", "#,##0.0")
            self.mrow(ws, f"{sk}.lost", "Customers lost (churn)", "Customers at start × monthly churn.", lambda m, sk=sk: f"={self.ref(sk + '.begin', m, N)}*{self.iref(sk + '.churn', N)}", "#,##0.0")
            self.mrow(ws, f"{sk}.end", "Customers at end of month", "Start + new − lost. Revenue below is billed on this number.",
                      lambda m, sk=sk: f"={self.ref(sk + '.begin', m, N)}+{self.ref(sk + '.new', m, N)}-{self.ref(sk + '.lost', m, N)}", "#,##0.0", total=True)
            for ln in seg["revenue_lines"]:
                lk = f"{sk}.{ln['key']}"
                base = f"{sk}.end" if ln["basis"] == "active" else f"{sk}.new"
                bt = "active customers" if ln["basis"] == "active" else "new customers"
                seas = seg.get("seasonality") and seg.get("seasonality_applies_to") == "new_and_orders" and ln["basis"] == "active"
                self.mrow(ws, f"{lk}.units", f"{ln['name']}: units sold", f"{bt.capitalize()} × units per customer" + (" × seasonality (reorders move with the calendar)." if seas else "."),
                          lambda m, lk=lk, base=base, seas=seas, sk=sk: f"={self.ref(base, m, N)}*{self.iref(lk + '.qty', N)}" + (f"*{self.ref(sk + '.season', m, N)}" if seas else ""), "#,##0.0")
                self.mrow(ws, f"{lk}.rev", f"{ln['name']}: revenue", "Units × price.", lambda m, lk=lk: f"={self.ref(lk + '.units', m, N)}*{self.iref(lk + '.price', N)}")
                if ln["basis"] == "active":
                    self.rows[f"rec.{lk}"] = self.rows[f"{lk}.rev"]  # marks a recurring line for the scripts
                self.mrow(ws, f"{lk}.cogs", f"{ln['name']}: direct cost", "Revenue × (1 − gross margin).", lambda m, lk=lk: f"={self.ref(lk + '.rev', m, N)}*(1-{self.iref(lk + '.margin', N)})")
            self.blank(ws)

    # ------------------------------------------------------------ team
    def build_team(self):
        N = "Team"
        ws = self.monthly(N, "Team", "Headcount and payroll. Plan roles by year; roles that grow with customers are computed from the customer count.")
        team = self.s["team"]
        self.section_row(ws, "Planned roles (people)")
        for role in team["roles"]:
            rk = role["key"]
            if "start_month" in role:
                self.mrow(ws, f"role.{rk}.n", role["name"], "People from the first to the last month set on Assumptions.",
                          lambda m, rk=rk: f"=IF(AND({mcol(m)}$6>={self.iref('role.' + rk + '.start')},{mcol(m)}$6<={self.iref('role.' + rk + '.end')}),{self.iref('role.' + rk + '.n')},0)", "#,##0.0")
            else:
                self.mrow(ws, f"role.{rk}.n", role["name"], "This year's headcount from Assumptions.", lambda m, rk=rk: f"={self.yidx('role.' + rk + '.count', N, m)}", "#,##0.0")
        self.section_row(ws, "Roles that grow with customers (people)")
        for cr in team.get("customer_driven_roles", []):
            self.mrow(ws, f"crole.{cr['key']}.n", cr["name"], "Active customers ÷ customers per person, rounded up.",
                      lambda m, cr=cr: f"=ROUNDUP({self.ref(cr['segment'] + '.end', m, N)}/{self.iref('crole.' + cr['key'] + '.ratio', N)},0)", "#,##0")
        heads = [f"role.{r['key']}.n" for r in team["roles"]] + [f"crole.{c['key']}.n" for c in team.get("customer_driven_roles", [])]
        act = [f"{seg['key']}.{ch['key']}.count" for seg in self.s["segments"] for ch in seg["channels"] if ch["type"] == "activity" and ch.get("is_headcount")]
        self.mrow(ws, "team.heads", "Total people", "All planned roles + customer-driven roles + activity units that are people (such as sales reps).",
                  lambda m: "=" + "+".join([self.ref(h, m, N) for h in heads] + [self.ref(a, m, N) for a in act] or ["0"]), "#,##0.0", total=True)
        self.section_row(ws, "Payroll")
        sal = []
        for role in team["roles"]:
            rid = f"role.{role['key']}.pay"
            sal.append(rid)
            self.mrow(ws, rid, f"{role['name']}: salaries", "People × monthly salary × (1 + yearly raise) for each year after the first.",
                      lambda m, role=role: f"={self.ref('role.' + role['key'] + '.n', m, N)}*{self.iref('role.' + role['key'] + '.salary', N)}*(1+{self.iref('raise')})^({mcol(m)}$7-1)")
        self.mrow(ws, "team.core_loaded", "Planned roles, loaded", "Salaries × (1 + taxes and benefits). Booked in operating expenses.",
                  lambda m: f"=({'+'.join(self.ref(x, m, N) for x in sal) or '0'})*(1+{self.iref('benefits', N)})", total=True)
        cs = []
        for cr in team.get("customer_driven_roles", []):
            rid = f"crole.{cr['key']}.pay"
            cs.append(rid)
            self.mrow(ws, rid, f"{cr['name']}: salaries", "People × monthly salary × (1 + yearly raise) for each year after the first.",
                      lambda m, cr=cr: f"={self.ref('crole.' + cr['key'] + '.n', m, N)}*{self.iref('crole.' + cr['key'] + '.salary', N)}*(1+{self.iref('raise')})^({mcol(m)}$7-1)")
        self.mrow(ws, "team.cust_loaded", "Customer-driven roles, loaded", "Salaries × (1 + taxes and benefits). Booked as a direct cost.",
                  lambda m: f"=({'+'.join(self.ref(x, m, N) for x in cs) or '0'})*(1+{self.iref('benefits', N)})", total=True)

    # ------------------------------------------------------------ P&L
    def build_pl(self):
        N = "Monthly P&L"
        ws = self.monthly(N, "Monthly income statement (P&L)", "Revenue and costs when they are earned and incurred, independent of when cash moves. Ties the work done to the result it produces.")
        s = self.s
        self.section_row(ws, "Revenue")
        rev = []
        for seg in s["segments"]:
            for ln in seg["revenue_lines"]:
                lk = f"{seg['key']}.{ln['key']}"
                rev.append(f"pl.rev.{lk}")
                self.mrow(ws, f"pl.rev.{lk}", f"{seg['name']}: {ln['name']}", "From the Customers tab.", lambda m, lk=lk: f"={self.ref(lk + '.rev', m, N)}")
        self.mrow(ws, "pl.rev", "Total revenue", "Sum of every revenue line.", lambda m: "=" + "+".join(self.ref(x, m, N) for x in rev), total=True)
        self.section_row(ws, "Direct costs (cost of what was sold)")
        dc = []
        for seg in s["segments"]:
            for ln in seg["revenue_lines"]:
                lk = f"{seg['key']}.{ln['key']}"
                dc.append(f"pl.cogs.{lk}")
                self.mrow(ws, f"pl.cogs.{lk}", f"{seg['name']}: {ln['name']}", "Revenue × (1 − gross margin), from the Customers tab.", lambda m, lk=lk: f"={self.ref(lk + '.cogs', m, N)}")
            for vc in seg.get("variable_costs", []):
                rid = f"pl.vc.{seg['key']}.{vc['key']}"
                dc.append(rid)
                if "per_new_customer" in vc:
                    self.mrow(ws, rid, f"{seg['name']}: {vc['name']}", "New customers × cost per new customer.",
                              lambda m, seg=seg, vc=vc: f"={self.ref(seg['key'] + '.new', m, N)}*{self.iref(seg['key'] + '.vc.' + vc['key'], N)}")
                elif "pct_of_revenue" in vc:
                    segrev = lambda m, seg=seg: "(" + "+".join(self.ref(f"{seg['key']}.{l['key']}.rev", m, N) for l in seg["revenue_lines"]) + ")"
                    self.mrow(ws, rid, f"{seg['name']}: {vc['name']}", "This segment's revenue × the share.",
                              lambda m, seg=seg, vc=vc, segrev=segrev: f"={segrev(m)}*{self.iref(seg['key'] + '.vc.' + vc['key'], N)}")
                else:
                    self.mrow(ws, rid, f"{seg['name']}: {vc['name']}", "Active customers × cost per customer.",
                              lambda m, seg=seg, vc=vc: f"={self.ref(seg['key'] + '.end', m, N)}*{self.iref(seg['key'] + '.vc.' + vc['key'], N)}")
        if s["team"].get("customer_driven_roles"):
            dc.append("pl.custstaff")
            self.mrow(ws, "pl.custstaff", "Customer-driven staff", "Loaded payroll of roles that grow with customers, from the Team tab.", lambda m: f"={self.ref('team.cust_loaded', m, N)}")
        self.mrow(ws, "pl.dc", "Total direct costs", "Sum of direct costs.", lambda m: "=" + "+".join(self.ref(x, m, N) for x in dc), total=True)
        self.mrow(ws, "pl.gp", "Gross profit", "Revenue − direct costs.", lambda m: f"={self.ref('pl.rev', m, N)}-{self.ref('pl.dc', m, N)}", total=True)
        self.mrow(ws, "pl.gm", "Gross margin", "Gross profit ÷ revenue.", lambda m: f"=IF({self.ref('pl.rev', m, N)}=0,0,{self.ref('pl.gp', m, N)}/{self.ref('pl.rev', m, N)})", "0.0%")
        self.section_row(ws, "Sales and marketing (money spent to win customers)")
        sm, self.payroll_sm = [], []
        for seg in s["segments"]:
            for ch in seg["channels"]:
                ck = f"{seg['key']}.{ch['key']}"
                if ch["type"] == "paid":
                    sm.append(f"pl.sm.{ck}")
                    self.mrow(ws, f"pl.sm.{ck}", f"{seg['name']}: {ch['name']}", "Channel spend, from the Acquisition tab.", lambda m, ck=ck: f"={self.ref(ck + '.spend', m, N)}")
                elif ch["type"] == "activity":
                    sm.append(f"pl.sm.{ck}")
                    if ch.get("is_headcount"):
                        self.payroll_sm.append(f"pl.sm.{ck}")
                    self.mrow(ws, f"pl.sm.{ck}", f"{seg['name']}: {ch['name']}", "Units × loaded cost per unit, from the Acquisition tab.", lambda m, ck=ck: f"={self.ref(ck + '.cost', m, N)}")
        self.mrow(ws, "pl.sm", "Total sales and marketing", "Sum of acquisition spend and costs.", lambda m: "=" + ("+".join(self.ref(x, m, N) for x in sm) or "0"), total=True)
        self.mrow(ws, "pl.gpsm", "Gross profit after sales and marketing", "Gross profit − sales and marketing.", lambda m: f"={self.ref('pl.gp', m, N)}-{self.ref('pl.sm', m, N)}", total=True)
        self.section_row(ws, "Operating expenses (everything else)")
        ox = ["pl.team"]
        self.mrow(ws, "pl.team", "Team (planned roles, loaded)", "From the Team tab.", lambda m: f"={self.ref('team.core_loaded', m, N)}")
        for k, name in enumerate(s["team"].get("per_employee_monthly", {})):
            ox.append(f"pl.pe.{k}")
            self.mrow(ws, f"pl.pe.{k}", name, "Total people × cost per employee.", lambda m, k=k: f"={self.ref('team.heads', m, N)}*{self.iref('pe.' + str(k), N)}")
        for k, name in enumerate(s["team"].get("fixed_monthly", {})):
            ox.append(f"pl.fx.{k}")
            self.mrow(ws, f"pl.fx.{k}", name, "Fixed monthly cost.", lambda m, k=k: f"={self.iref('fx.' + str(k), N)}")
        self.mrow(ws, "pl.opex", "Total operating expenses", "Sum of operating expenses.", lambda m: "=" + "+".join(self.ref(x, m, N) for x in ox), total=True)
        self.mrow(ws, "pl.costs", "Total expenses", "Direct costs + sales and marketing + operating expenses.", lambda m: f"={self.ref('pl.dc', m, N)}+{self.ref('pl.sm', m, N)}+{self.ref('pl.opex', m, N)}", total=True)
        self.mrow(ws, "pl.ebitda", "EBITDA (operating profit)", "Revenue − total expenses.", lambda m: f"={self.ref('pl.rev', m, N)}-{self.ref('pl.costs', m, N)}", total=True)
        self.mrow(ws, "pl.int", "Interest on loans", "From the Funding tab.", lambda m: f"={self.ref('fund.interest', m, N)}")
        self.mrow(ws, "pl.ebt", "Profit before tax", "EBITDA − interest.", lambda m: f"={self.ref('pl.ebitda', m, N)}-{self.ref('pl.int', m, N)}", total=True)
        self.mrow(ws, "pl.cum", "Cumulative profit before tax", "Running total, used for the tax loss carry-forward.",
                  lambda m: f"={self.ref('pl.ebt', m, N)}" if m == 1 else f"={self.ref('pl.cum', m - 1, N)}+{self.ref('pl.ebt', m, N)}")
        self.mrow(ws, "pl.taxcum", "Cumulative income tax", "Tax rate × cumulative profit once earlier losses are used up (never below zero).",
                  lambda m: f"=MAX(0,{self.ref('pl.cum', m, N)})*{self.iref('tax', N)}")
        self.mrow(ws, "pl.tax", "Income tax", "This month's increase in cumulative tax.",
                  lambda m: f"={self.ref('pl.taxcum', m, N)}" if m == 1 else f"=MAX(0,{self.ref('pl.taxcum', m, N)}-{self.ref('pl.taxpaid', m - 1, N)})")
        self.mrow(ws, "pl.taxpaid", "Income tax paid to date", "Running total of income tax.",
                  lambda m: f"={self.ref('pl.tax', m, N)}" if m == 1 else f"={self.ref('pl.taxpaid', m - 1, N)}+{self.ref('pl.tax', m, N)}")
        self.mrow(ws, "pl.ni", "Net income", "Profit before tax − income tax. (No depreciation in this model: add it only if it moves a decision.)",
                  lambda m: f"={self.ref('pl.ebt', m, N)}-{self.ref('pl.tax', m, N)}", total=True)
        self.mrow(ws, "pl.payroll", "Of which payroll (helper)", "All loaded payroll in the P&L. Used for payables: payroll is paid in the month, never on supplier terms.",
                  lambda m: "=" + "+".join([self.ref("pl.team", m, N)] + ([self.ref("pl.custstaff", m, N)] if s["team"].get("customer_driven_roles") else []) + [self.ref(x, m, N) for x in self.payroll_sm]))
        recs = [f"pl.rev.{seg['key']}.{ln['key']}" for seg in s["segments"] for ln in seg["revenue_lines"] if ln["basis"] == "active"]
        self.mrow(ws, "pl.valrev", "Revenue the valuation multiplies (helper)", "Recurring revenue (subscriptions, repeat orders, retainers); total revenue only if the business has no recurring line. One-time fees are not worth a recurring multiple.",
                  lambda m: "=" + ("+".join(self.ref(x, m, N) for x in recs) if recs else self.ref("pl.rev", m, N)))
        self.mrow(ws, "pl.pos", "Profitable from here on? (helper)", "1 when EBITDA is positive this month and every month after it. The first 1 is the break-even month.",
                  lambda m: f"=IF({self.ref('pl.ebitda', m, N)}>0,1,0)" if m == MONTHS else f"=IF(AND({self.ref('pl.ebitda', m, N)}>0,{self.ref('pl.pos', m + 1, N)}=1),1,0)", "0")
        self.mrow(ws, "pl.bem", "Break-even month number (helper)", "This month's number where 'profitable from here on' is 1, else 999. Their minimum is the break-even month.",
                  lambda m: f"=IF({self.ref('pl.pos', m, N)}=1,{mcol(m)}$6,999)", "0")
        self.mrow(ws, "pl.goods", "Of which product direct cost (helper)", "Direct cost of revenue lines. Used for inventory.",
                  lambda m: "=" + "+".join(self.ref(f"pl.cogs.{seg['key']}.{ln['key']}", m, N) for seg in s["segments"] for ln in seg["revenue_lines"]))

    # ------------------------------------------------------------ funding
    def build_funding(self):
        N = "Funding by month"
        ws = self.monthly(N, "Funding by month", "The month-by-month engine behind the Funding tab: cash raised, ownership sold, loans, founders' ownership and value. Feeds the cash flow (financing), the balance sheet (capital, loans) and the P&L (interest).")
        amts, dils = [], []
        for n in range(1, self.n_rounds + 1):
            self.section_row(ws, f"Round {n}: {self.s['funding']['rounds'][n - 1]['name']}")
            mo, am, pr, pool = (self.iref(f"round.{n}.{x}", N) for x in ("month", "amount", "price", "pool"))
            self.mrow(ws, f"round.{n}.in", "Cash raised this month", "Amount, in the month the round closes.", lambda m, mo=mo, am=am: f"=IF({mcol(m)}$6={mo},{am},0)")
            is_safe = self.s["funding"]["rounds"][n - 1]["type"] == "safe"
            if not is_safe:
                self.mrow(ws, f"round.{n}.pre", "Pre-money used", "The pre-money from Assumptions, or (if it is 0) multiple × last month's recurring revenue × 12. Cash in the bank is not added: the new money buys into the business, not into its bank account.",
                          lambda m, pr=pr: f"=IF({pr}>0,{pr},MAX(1,{self.iref('multiple', N)}*{self.ref('pl.valrev', m - 1, N) if m > 1 else '0'}*12))")
            self.mrow(ws, f"round.{n}.dil", "Ownership sold this month", "SAFE: amount ÷ post-money cap. Priced: amount ÷ (pre-money + amount) + option pool created.",
                      lambda m, n=n, mo=mo, am=am, pr=pr, pool=pool, is_safe=is_safe: (f"=IF({mcol(m)}$6={mo},{am}/MAX({pr},1),0)" if is_safe
                                                                                   else f"=IF(AND({mcol(m)}$6={mo},{am}>0),{am}/({self.ref(f'round.{n}.pre', m, N)}+{am})+{pool},0)"), "0.0%")
            amts.append(f"round.{n}.in")
            dils.append(f"round.{n}.dil")
            self.mrow(ws, f"round.{n}.cashafter", "Cash from the close on (helper)", "Ending cash in months from the close onward; a huge number before it, so the minimum is the lowest cash the round has to carry.",
                      lambda m, mo=mo: f"=IF({mcol(m)}$6>={mo},{self.ref('cf.end', m, N)},1E+99)")
            self.mrow(ws, f"round.{n}.lowmonth", "Month of that lowest cash (helper)", "This month's number where cash equals the lowest after the close, else 999.",
                      lambda m, n=n: f"=IF({self.ref(f'round.{n}.cashafter', m, N)}=MIN({self.ref(f'round.{n}.cashafter', 1, N, True)}:{self.ref(f'round.{n}.cashafter', MONTHS, N, True)}),{mcol(m)}$6,999)", "0")
            self.mrow(ws, f"round.{n}.belowmin", "Month cash falls below the minimum, after the close (helper)", "This month's number when cash is below the minimum from the close on, else 999.",
                      lambda m, mo=mo: f"=IF(AND({mcol(m)}$6>={mo},{self.ref('cf.end', m, N)}<{self.iref('min_cash')}),{mcol(m)}$6,999)", "0")
            self.mrow(ws, f"round.{n}.win", "In the 18 months after the close? (helper)", "1 from the close month for 18 months: the window the Dashboard reads use of funds from.",
                      lambda m, mo=mo: f"=IF(AND({mcol(m)}$6>={mo},{mcol(m)}$6<{mo}+18),1,0)", "0")
            self.mrow(ws, f"round.{n}.rev", "Revenue in that window (helper)", "Window flag × revenue: the part of the spending customers pay for.",
                      lambda m, n=n: f"={self.ref(f'round.{n}.win', m, N)}*{self.ref('pl.rev', m, N)}")
            for ck, cname in UOF:
                src = {"sm": "pl.sm", "team": "pl.team", "direct": "pl.dc"}.get(ck)
                self.mrow(ws, f"round.{n}.spend.{ck}", f"{cname} in that window (helper)", f"Window flag × {cname.lower()} from the P&L.",
                          lambda m, n=n, src=src: f"={self.ref(f'round.{n}.win', m, N)}*" + (self.ref(src, m, N) if src else f"({self.ref('pl.opex', m, N)}-{self.ref('pl.team', m, N)})"))
        lin, lout, lbal, lint = [], [], [], []
        for n in range(1, len(self.loans) + 1):
            self.section_row(ws, f"Loan {n}: {self.loans[n - 1]['name']}")
            mi, am, mo, rt = (self.iref(f"loan.{n}.{x}", N) for x in ("month_in", "amount", "month_out", "rate"))
            self.mrow(ws, f"loan.{n}.bal", "Owed at end of month", "The amount, from the month it arrives (month 1 if already received) until the month it is repaid.",
                      lambda m, mi=mi, am=am, mo=mo: f"=IF(AND({mcol(m)}$6>=MAX({mi},1),{mcol(m)}$6<{mo}),{am},0)")
            self.mrow(ws, f"loan.{n}.in", "Received this month", "The amount, in the month it arrives (never for a loan already in starting cash).", lambda m, mi=mi, am=am: f"=IF({mcol(m)}$6={mi},{am},0)")
            self.mrow(ws, f"loan.{n}.out", "Repaid this month", "The whole amount, in the month it is repaid.", lambda m, mo=mo, am=am: f"=IF({mcol(m)}$6={mo},{am},0)")
            self.mrow(ws, f"loan.{n}.int", "Interest this month", "Amount × yearly rate ÷ 12, for every month the money is owed (including the month it is repaid).",
                      lambda m, mi=mi, am=am, mo=mo, rt=rt: f"=IF(AND({mcol(m)}$6>=MAX({mi},1),{mcol(m)}$6<={mo}),{am},0)*{rt}/12")
            lin.append(f"loan.{n}.in"); lout.append(f"loan.{n}.out"); lbal.append(f"loan.{n}.bal"); lint.append(f"loan.{n}.int")
        self.section_row(ws, "Totals")
        sumr = lambda ids, m: "=" + ("+".join(self.ref(x, m, N) for x in ids) or "0")
        self.mrow(ws, "fund.loan_in", "Loans received this month", "Sum over loans.", lambda m: sumr(lin, m))
        self.mrow(ws, "fund.loan_out", "Loans repaid this month", "Sum over loans.", lambda m: sumr(lout, m))
        self.mrow(ws, "fund.loan_bal", "Loans owed at end of month", "Sum over loans.", lambda m: sumr(lbal, m))
        self.mrow(ws, "fund.interest", "Interest this month", "Sum over loans; booked on the P&L below operating profit.", lambda m: sumr(lint, m))
        self.mrow(ws, "fund.in", "Equity raised this month", "Sum of every round's cash this month.", lambda m: "=" + ("+".join(self.ref(x, m, N) for x in amts) or "0"), total=True)
        self.mrow(ws, "fund.cum", "Equity raised to date", "Running total.", lambda m: f"={self.ref('fund.in', m, N)}" if m == 1 else f"={self.ref('fund.cum', m - 1, N)}+{self.ref('fund.in', m, N)}")
        self.mrow(ws, "fund.share", "Founders' ownership", "Last month's share × (1 − ownership sold this month), round by round. (A SAFE is held at its cap; if the next round prices below the cap, the SAFE takes more.)",
                  lambda m: ("=" + self.iref("founders_share0", N) if m == 1 else "=" + self.ref("fund.share", m - 1, N)) + "".join(f"*(1-{self.ref(d, m, N)})" for d in dils), "0.0%", total=True)
        self.mrow(ws, "fund.ev", "Company value (simple)", "Revenue multiple × this month's recurring revenue × 12, plus cash in the bank, minus loans owed: what the owners' shares are worth.",
                  lambda m: f"={self.iref('multiple', N)}*{self.ref('pl.valrev', m, N)}*12+{self.ref('cf.end', m, N)}-{self.ref('fund.loan_bal', m, N)}")
        self.mrow(ws, "fund.fv", "Founders' value", "Founders' ownership × company value. The number to compare deals by: a whole grape or half a watermelon.",
                  lambda m: f"={self.ref('fund.share', m, N)}*{self.ref('fund.ev', m, N)}", total=True)

    # ------------------------------------------------------------ balance sheet + cash flow
    def build_bs_cf(self):
        B, C = "Monthly Balance Sheet", "Monthly Cash Flow"
        wsb = self.monthly(B, "Monthly balance sheet", "A snapshot at each month's end: what the company has (assets), what it owes (liabilities), and what is left for the owners (equity). Assets always equal liabilities + equity; the Check row proves it.")
        wsc = self.monthly(C, "Monthly cash flow", "Cash in and cash out. Profit is a matter of opinion, cash is a matter of fact: this tab says how long the company can live.")
        P = "Monthly P&L"
        self.section_row(wsb, "Assets")
        self.mrow(wsb, "bs.cash", "Cash", "Ending cash, from the cash flow tab.", lambda m: f"={self.ref('cf.end', m, B)}")
        self.mrow(wsb, "bs.ar", "Receivables (owed by customers)", "This month's revenue × receivable days ÷ 30.", lambda m: f"={self.ref('pl.rev', m, B)}*{self.iref('ar_days', B)}/30")
        self.mrow(wsb, "bs.inv", "Inventory", "This month's product direct cost × inventory days ÷ 30.", lambda m: f"={self.ref('pl.goods', m, B)}*{self.iref('inv_days', B)}/30")
        self.mrow(wsb, "bs.assets", "Total assets", "Cash + receivables + inventory.", lambda m: f"={self.ref('bs.cash', m, B)}+{self.ref('bs.ar', m, B)}+{self.ref('bs.inv', m, B)}", total=True)
        self.section_row(wsb, "Liabilities and equity")
        self.mrow(wsb, "bs.ap", "Payables (owed to suppliers)", "This month's non-payroll expenses × payable days ÷ 30.",
                  lambda m: f"=({self.ref('pl.costs', m, B)}-{self.ref('pl.payroll', m, B)})*{self.iref('ap_days', B)}/30")
        self.mrow(wsb, "bs.loans", "Loans owed", "From the Funding tab.", lambda m: f"={self.ref('fund.loan_bal', m, B)}")
        open_loans = "".join(f"-IF({self.iref(f'loan.{n}.month_in', B)}=0,{self.iref(f'loan.{n}.amount', B)},0)" for n in range(1, len(self.loans) + 1))
        self.mrow(wsb, "bs.paidin", "Owners' capital", "What the owners had in the business on day one (cash + receivables + inventory − payables − loans already owed) + equity raised to date.",
                  lambda m: f"={self.iref('starting_cash', B)}+{self.iref('open_ar', B)}+{self.iref('open_inv', B)}-{self.iref('open_ap', B)}{open_loans}+{self.ref('fund.cum', m, B)}")
        self.mrow(wsb, "bs.re", "Retained earnings", "Net income accumulated since month 1.",
                  lambda m: f"={self.ref('pl.ni', m, B)}" if m == 1 else f"={self.ref('bs.re', m - 1, B)}+{self.ref('pl.ni', m, B)}")
        self.mrow(wsb, "bs.le", "Total liabilities and equity", "Payables + loans + owners' capital + retained earnings.",
                  lambda m: f"={self.ref('bs.ap', m, B)}+{self.ref('bs.loans', m, B)}+{self.ref('bs.paidin', m, B)}+{self.ref('bs.re', m, B)}", total=True)
        self.mrow(wsb, "bs.check", "Check (must be 0)", "Total assets − total liabilities and equity, rounded to cents. Anything else means a broken formula.",
                  lambda m: f"=ROUND({self.ref('bs.assets', m, B)}-{self.ref('bs.le', m, B)},2)")
        self.section_row(wsc, "Cash flow")
        self.mrow(wsc, "cf.begin", "Cash at start of month", "Last month's ending cash (month 1: cash at the start).",
                  lambda m: f"={self.iref('starting_cash', C)}" if m == 1 else f"={self.ref('cf.end', m - 1, C)}")
        self.mrow(wsc, "cf.ni", "Net income", "From the P&L.", lambda m: f"={self.ref('pl.ni', m, C)}")
        opening = {"bs.ar": "open_ar", "bs.inv": "open_inv", "bs.ap": "open_ap"}
        prev = lambda rid, m: self.iref(opening[rid], C) if m == 1 else self.ref(rid, m - 1, C)
        self.mrow(wsc, "cf.ar", "Less: increase in receivables", "Revenue earned but not yet collected is not cash.", lambda m: f"=-({self.ref('bs.ar', m, C)}-{prev('bs.ar', m)})")
        self.mrow(wsc, "cf.inv", "Less: increase in inventory", "Stock bought but not yet sold is cash gone.", lambda m: f"=-({self.ref('bs.inv', m, C)}-{prev('bs.inv', m)})")
        self.mrow(wsc, "cf.ap", "Plus: increase in payables", "Costs incurred but not yet paid keep cash in the bank, for now.", lambda m: f"={self.ref('bs.ap', m, C)}-{prev('bs.ap', m)}")
        self.mrow(wsc, "cf.ops", "Cash from operations", "Net income adjusted for working capital.",
                  lambda m: f"={self.ref('cf.ni', m, C)}+{self.ref('cf.ar', m, C)}+{self.ref('cf.inv', m, C)}+{self.ref('cf.ap', m, C)}", total=True)
        self.mrow(wsc, "cf.eq", "Equity raised", "From the Funding tab. Investment never appears as revenue.", lambda m: f"={self.ref('fund.in', m, C)}")
        self.mrow(wsc, "cf.loans", "Loans received − repaid", "From the Funding tab.", lambda m: f"={self.ref('fund.loan_in', m, C)}-{self.ref('fund.loan_out', m, C)}")
        self.mrow(wsc, "cf.net", "Net change in cash", "Cash from operations + equity raised + net loans.", lambda m: f"={self.ref('cf.ops', m, C)}+{self.ref('cf.eq', m, C)}+{self.ref('cf.loans', m, C)}", total=True)
        self.mrow(wsc, "cf.end", "Cash at end of month", "Start + net change.", lambda m: f"={self.ref('cf.begin', m, C)}+{self.ref('cf.net', m, C)}", total=True)
        self.mrow(wsc, "cf.ttl", "Months of cash left (runway)", "Ending cash ÷ this month's operating burn. Shows 'Cash-flow positive' when operations add cash.",
                  lambda m: f"=IF({self.ref('cf.ops', m, C)}<0,{self.ref('cf.end', m, C)}/-{self.ref('cf.ops', m, C)},\"Cash-flow positive\")", "0.0")
        self.mrow(wsc, "cf.low", "Lowest cash so far", "Minimum ending cash from month 1 to this month. Below zero = the company died here.",
                  lambda m: f"=MIN({self.ref('cf.end', 1, C, True)}:{self.ref('cf.end', m, C)})")

    # ------------------------------------------------------------ annual
    def annual(self, name, title, purpose, src_sheet, items):
        ws = self.sheet(name, "summary", title, purpose)
        ws.column_dimensions["A"].width = 44
        ws.column_dimensions["B"].width = 58
        for y in range(1, 6):
            ws.column_dimensions[mcol(y)].width = 18
        r = 5
        ws.cell(r, 1, "Line item")
        ws.cell(r, 2, "How it's calculated")
        for y in range(1, 6):
            ws.cell(r, FIRST_COL + y - 1, f"Year {y}")
        for c in range(1, FIRST_COL + 5):
            ws.cell(r, c).fill, ws.cell(r, c).font = F_HEAD, WHITE_BOLD
        ws.cell(6, 1, "Starts").font = ITALIC
        ws.cell(6, 2, "First month of the year.").font = ITALIC
        for y in range(1, 6):
            c = ws.cell(6, FIRST_COL + y - 1, f"=DATE(YEAR({self.iref('start', name)}),MONTH({self.iref('start', name)})+{12 * (y - 1)},1)")
            c.number_format, c.font = "mmm yyyy", ITALIC
        ws.freeze_panes = "C7"
        r = 7
        for it in items:
            if it[0] == "section":
                ws.cell(r, 1, it[1]).font = BOLD
                for c in range(1, FIRST_COL + 5):
                    ws.cell(r, c).fill = F_SECTION
                r += 1
                continue
            mode, rid, label, fmt, total = it
            src_sh, src_row = self.rows[rid]
            ws.cell(r, 1, label).font = BOLD if total else BLACK
            expl = {"sum": "Sum of the 12 months of the year.", "end": "Value at the last month of the year.", "begin": "Value at the first month of the year.", "min": "Lowest month of the year."}[mode] if mode in ("sum", "end", "begin", "min") else ""
            ws.cell(r, 2, f"{expl} Source: {src_sh}.").font = ITALIC
            self.rows[f"a.{name}.{rid}" + ("" if mode in ("sum", "end") else f".{mode}")] = (name, r)
            for y in range(1, 6):
                a, b = mcol(12 * (y - 1) + 1), mcol(12 * y)
                rng = f"{q(src_sh)}!{a}{src_row}:{b}{src_row}"
                f = {"sum": f"=SUM({rng})", "end": f"={q(src_sh)}!{b}{src_row}", "begin": f"={q(src_sh)}!{a}{src_row}", "min": f"=MIN({rng})"}[mode]
                c = ws.cell(r, FIRST_COL + y - 1, f)
                c.number_format = fmt or self.money
                if total:
                    c.font, c.border, c.fill = BOLD, TOP, F_TOTAL
            r += 1
        return ws

    def build_annuals(self):
        s = self.s
        items = [("section", "Revenue")]
        for seg in s["segments"]:
            for ln in seg["revenue_lines"]:
                items.append(("sum", f"pl.rev.{seg['key']}.{ln['key']}", f"{seg['name']}: {ln['name']}", None, False))
        items += [("sum", "pl.rev", "Total revenue", None, True), ("sum", "pl.dc", "Total direct costs", None, False), ("sum", "pl.gp", "Gross profit", None, True),
                  ("sum", "pl.sm", "Sales and marketing", None, False), ("sum", "pl.gpsm", "Gross profit after sales and marketing", None, True),
                  ("sum", "pl.opex", "Operating expenses", None, False), ("sum", "pl.ebitda", "EBITDA (operating profit)", None, True),
                  ("sum", "pl.int", "Interest on loans", None, False), ("sum", "pl.ebt", "Profit before tax", None, False),
                  ("sum", "pl.tax", "Income tax", None, False), ("sum", "pl.ni", "Net income", None, True),
                  ("section", "Customers"), *[x for seg in s["segments"] for x in (("sum", f"{seg['key']}.new", f"{seg['name']}: new customers in the year", "#,##0", False),
                                                                                       ("end", f"{seg['key']}.end", f"{seg['name']}: active customers at year end", "#,##0", False))],
                  ("end", "team.heads", "People at year end", "#,##0", False)]
        self.annual("Annual P&L", "Annual income statement", "Five years at a glance, summed from the monthly P&L. The one-slide summary for a deck comes from here; the detail stays in the model.", "Monthly P&L", items)
        self.annual("Annual Cash Flow", "Annual cash flow", "How much cash the plan needs and when. The bottom-right cell is cash at the end of year five.", "Monthly Cash Flow", [
            ("begin", "cf.begin", "Cash at start of year", None, False), ("sum", "cf.ni", "Net income", None, False), ("sum", "cf.ar", "Less: increase in receivables", None, False),
            ("sum", "cf.inv", "Less: increase in inventory", None, False), ("sum", "cf.ap", "Plus: increase in payables", None, False), ("sum", "cf.ops", "Cash from operations", None, True),
            ("sum", "cf.eq", "Equity raised", None, False), ("sum", "cf.loans", "Loans received − repaid", None, False), ("sum", "cf.net", "Net change in cash", None, True), ("end", "cf.end", "Cash at end of year", None, True), ("min", "cf.end", "Lowest cash in the year", None, False)])
        self.annual("Annual Balance Sheet", "Annual balance sheet", "Year-end snapshots from the monthly balance sheet.", "Monthly Balance Sheet", [
            ("end", "bs.cash", "Cash", None, False), ("end", "bs.ar", "Receivables", None, False), ("end", "bs.inv", "Inventory", None, False), ("end", "bs.assets", "Total assets", None, True),
            ("end", "bs.ap", "Payables", None, False), ("end", "bs.loans", "Loans owed", None, False), ("end", "bs.paidin", "Owners' capital", None, False), ("end", "bs.re", "Retained earnings", None, False),
            ("end", "bs.le", "Total liabilities and equity", None, True), ("section", "Ownership"), ("end", "fund.share", "Founders' ownership", "0.0%", False), ("end", "fund.fv", "Founders' value", None, True)])

    # ------------------------------------------------------------ unit economics
    def build_unit_economics(self):
        N = "Unit Economics"
        ws = self.sheet(N, "summary", "Unit economics, one customer at a time", "What one customer is worth (LTV, on contribution margin, never on revenue) against what it costs to win one in each channel (CAC). Rules of thumb for recurring revenue: LTV/CAC of 3x or more, and the CAC paid back within 12 months. The two trade off.")
        ws.column_dimensions["A"].width = 46
        for c, w in zip("BCDE", (24, 20, 14, 36)):
            ws.column_dimensions[c].width = w
        ws.column_dimensions["F"].width = 110
        r = 5
        team = self.s["team"]
        for seg in self.s["segments"]:
            sk = seg["key"]
            ws.cell(r, 1, f"Segment: {seg['name']}").font = BOLD
            for c in range(1, 7):
                ws.cell(r, c).fill = F_SECTION
            r += 1
            act = [ln for ln in seg["revenue_lines"] if ln["basis"] == "active"]
            one = [ln for ln in seg["revenue_lines"] if ln["basis"] == "new"]
            A = lambda i: self.iref(i, N)
            rev_pm = "+".join(f"{A(sk + '.' + ln['key'] + '.qty')}*{A(sk + '.' + ln['key'] + '.price')}" for ln in act) or "0"
            con_pm = "+".join(f"{A(sk + '.' + ln['key'] + '.qty')}*{A(sk + '.' + ln['key'] + '.price')}*{A(sk + '.' + ln['key'] + '.margin')}" for ln in act) or "0"
            vcs = "".join(f"-{A(sk + '.vc.' + vc['key'])}" for vc in seg.get("variable_costs", []) if "per_active_customer" in vc)
            per_new = "".join(f"-{A(sk + '.vc.' + vc['key'])}" for vc in seg.get("variable_costs", []) if "per_new_customer" in vc)
            pct = "+".join(A(sk + '.vc.' + vc['key']) for vc in seg.get("variable_costs", []) if "pct_of_revenue" in vc) or "0"
            vcs += f"-({rev_pm})*({pct})" if pct != "0" else ""
            crs = "".join(f"-{A('crole.' + cr['key'] + '.salary')}*(1+{A('benefits')})/{A('crole.' + cr['key'] + '.ratio')}" for cr in team.get("customer_driven_roles", []) if cr["segment"] == sk)
            one_m = "+".join(f"{A(sk + '.' + ln['key'] + '.qty')}*{A(sk + '.' + ln['key'] + '.price')}*({A(sk + '.' + ln['key'] + '.margin')}-({pct}))" for ln in one) or "0"
            rows = [
                ("rev", "Revenue per customer per month", f"={rev_pm}", self.money2, "Recurring lines only: units per customer × price."),
                ("con", "Contribution per customer per month", f"={con_pm}{vcs}{crs}", self.money2, "Revenue × gross margin, less variable costs and customer-driven staff per customer. The part you get to keep."),
                ("life", "Expected lifetime (months)", f"=IF({A(sk + '.churn')}<=0,120,MIN(120,1/{A(sk + '.churn')}))", "0.0", "1 ÷ monthly churn (capped at 120 months). 4% a month = 25 months."),
                ("one", "One-time margin at signup", f"={one_m}{per_new}", self.money2, "Margin on one-time lines (setup or onboarding fees) per new customer, less one-time costs per new customer."),
                ("ltv", "Lifetime value (LTV)", f"=B{r + 1}*B{r + 2}+B{r + 3}", self.money2, "Contribution × lifetime + one-time margin. Lifetime REVENUE would overstate it badly unless margins are ~90%."),
            ]
            base = r
            for i, (k, label, f, fmt, expl) in enumerate(rows):
                ws.cell(r, 1, label)
                c = ws.cell(r, 2, f)
                c.number_format = fmt
                if k == "ltv":
                    c.font = BOLD
                ws.cell(r, 6, expl).font = ITALIC
                self.rows[f"ue.{sk}.{k}"] = (N, r)
                r += 1
            ltv, con, one_c = f"$B${base + 4}", f"$B${base + 1}", f"$B${base + 3}"
            for i, h in enumerate(["Channel", "CAC (cost to win one)", "Months to pay back", "LTV / CAC", "Verdict", "How CAC is computed"]):
                cc = ws.cell(r, 1 + i, h)
                cc.fill, cc.font = F_HEAD, WHITE_BOLD
            r += 1
            for ch in seg["channels"]:
                ck = f"{sk}.{ch['key']}"
                ws.cell(r, 1, ch["name"])
                if ch["type"] == "organic":
                    ws.cell(r, 2, "free")
                    ws.cell(r, 5, "not a paid channel")
                    ws.cell(r, 6, "Kept out on purpose: mixing free customers into a 'blended CAC' flatters it and answers nothing. The question CAC answers is what the NEXT customer costs if you spend more.").font = ITALIC
                else:
                    cac = f"{A(ck + '.cpc')}/MAX({A(ck + '.conv')},0.000001)" if ch["type"] == "paid" else f"{A(ck + '.cost')}/MAX({A(ck + '.yield')},0.000001)"
                    ws.cell(r, 2, f"={cac}").number_format = self.money2
                    ws.cell(r, 3, f"=IF(B{r}<={one_c},0,IF({con}<=0,999,(B{r}-{one_c})/{con}))").number_format = "0.0"
                    ws.cell(r, 4, f"=IF(B{r}<=0,\"no acquisition cost\",{ltv}/B{r})").number_format = "0.00\"x\""
                    ws.cell(r, 5, f"=IF(B{r}<=0,\"no cost to win: any commission sits in the margin\",IF(AND(D{r}>=3,C{r}<=12),\"strong: >=3x and <=12 months\",IF(OR(D{r}>=3,C{r}<=12),\"mixed: one rule met\",\"weak: neither rule met\")))")
                    ws.cell(r, 6, ("Cost per click or lead ÷ conversion. Fully loaded in real life: include the salaries and commissions of people who sell." if ch["type"] == "paid"
                                   else "Loaded monthly cost per unit ÷ new customers per unit per month (a rep's cost ÷ the rep's closes).")).font = ITALIC
                    self.rows[f"ue.{ck}.cac"] = (N, r)
                r += 1
            r += 1
        ws.cell(r, 1, "Look at LTV and CAC per channel and per cohort, never blended. Customers won through a discount or a different channel often behave very differently.").font = ITALIC

    # ------------------------------------------------------------ funding (summary)
    def build_funding_summary(self):
        N, M = "Funding", "Funding by month"
        ws = self.sheet(N, "summary", "Funding: the rounds, who owns what, and what each round buys",
                        "Every money-in decision on one page. Inputs live on Assumptions (Funding rounds); the month-by-month engine is on 'Funding by month'. Judge a round by what it buys and by founders' value, not by the percentage sold.")
        ws.column_dimensions["A"].width = 52
        for c in "BCDEFGH":
            ws.column_dimensions[c].width = 17
        rowf = lambda rid: self.rrange(rid, N)
        rounds = self.s["funding"]["rounds"]
        r = 5
        # 1. the rounds
        for i, h in enumerate(["The rounds", "Instrument", "Closes (month)", "Amount", "Cap or pre-money used", "Ownership sold", "Founders after"]):
            c = ws.cell(r, 1 + i, h)
            c.fill, c.font = F_HEAD, WHITE_BOLD
        r += 1
        self.fs_cells = {}
        for n, rd in enumerate(rounds, 1):
            mo, am = self.name_of(f"round.{n}.month"), self.name_of(f"round.{n}.amount")
            price = f"={self.name_of(f'round.{n}.price')}" if rd["type"] == "safe" else f"=INDEX({rowf(f'round.{n}.pre')},{mo})"
            vals = [(f"Round {n}: {rd['name']}", None), ("SAFE (post-money cap)" if rd["type"] == "safe" else "Priced round", None), (f"={mo}", "0"), (f"={am}", self.money),
                    (price, self.money), (f"=INDEX({rowf(f'round.{n}.dil')},{mo})", "0.0%"), (f"=INDEX({rowf('fund.share')},{mo})", "0.0%")]
            for col, (v, fmt) in enumerate(vals, 1):
                c = ws.cell(r, col, v)
                if fmt:
                    c.number_format = fmt
            self.fs_cells[n] = {"amount": f"D{r}", "after": f"G{r}"}
            r += 1
        for n, ln in enumerate(self.loans, 1):
            ws.cell(r, 1, f"Loan {n}: {ln['name']}")
            ws.cell(r, 2, "Loan (repaid in one payment)")
            ws.cell(r, 3, f"={self.name_of(f'loan.{n}.month_in')}").number_format = "0"
            ws.cell(r, 4, f"={self.name_of(f'loan.{n}.amount')}").number_format = self.money
            ws.cell(r, 5, f"={self.name_of(f'loan.{n}.rate')}").number_format = "0.0%"
            ws.cell(r, 6, "repaid in month")
            ws.cell(r, 7, f"={self.name_of(f'loan.{n}.month_out')}").number_format = "0"
            r += 1
        r += 1
        # 2. who owns what (rounds in the order listed)
        heads = ["Who owns what", "At the start"] + [f"After round {n}" for n in range(1, len(rounds) + 1)]
        for i, h in enumerate(heads):
            c = ws.cell(r, 1 + i, h)
            c.fill, c.font = F_HEAD, WHITE_BOLD
        r += 1
        holders = ["Founders", "Option pool and earlier holders"] + [f"Round {n} investors: {rd['name']}" for n, rd in enumerate(rounds, 1)]
        top = r
        for k, h in enumerate(holders):
            ws.cell(top + k, 1, h)
        f0 = self.name_of("founders_share0")
        ws.cell(top, 2, f"={f0}").number_format = "0.0%"
        ws.cell(top + 1, 2, f"=1-{f0}").number_format = "0.0%"
        for k in range(2, len(holders)):
            ws.cell(top + k, 2, 0).number_format = "0.0%"
        for n, rd in enumerate(rounds, 1):
            col, prev = 2 + n, get_column_letter(1 + n)
            mo, am, pr, pool = (self.name_of(f"round.{n}.{x}") for x in ("month", "amount", "price", "pool"))
            if rd["type"] == "safe":
                new = f"{am}/MAX({pr},1)"
                newpool = "0"
            else:
                pre = f"INDEX({rowf(f'round.{n}.pre')},{mo})"
                new = f"IF({am}>0,{am}/({pre}+{am}),0)"
                newpool = f"IF({am}>0,{pool},0)"
            d = f"({new}+{newpool})"
            for k in range(len(holders)):
                rr = top + k
                if k == 1:
                    f = f"={prev}{rr}*(1-{d})+{newpool}"
                elif k == 1 + n:
                    f = f"={new}"
                else:
                    f = f"={prev}{rr}*(1-{d})"
                ws.cell(rr, col, f).number_format = "0.0%"
        r = top + len(holders)
        ws.cell(r, 1, "Total (must be 100%)").font = BOLD
        for col in range(2, 3 + len(rounds)):
            L = get_column_letter(col)
            ws.cell(r, col, f"=SUM({L}{top}:{L}{r - 1})").number_format = "0.0%"
        self.rows["fs.captotal"] = (N, r)
        ws.cell(r + 1, 1, "A SAFE is held at its post-money cap; if the next priced round prices below the cap, the SAFE converts at that lower price and takes more.").font = ITALIC
        r += 3
        # 3. each round: what it buys, then use of funds
        for n, rd in enumerate(rounds, 1):
            ws.cell(r, 1, f"Round {n}: {rd['name']}: what it buys").font = BOLD
            for c in range(1, 8):
                ws.cell(r, c).fill = F_SECTION
            r += 1
            mo, am = self.name_of(f"round.{n}.month"), self.name_of(f"round.{n}.amount")
            bm = f"MIN({rowf(f'round.{n}.belowmin')})"
            lines = [
                ("low", "Lowest cash from the close on", f"=MIN({rowf(f'round.{n}.cashafter')})", self.money),
                ("lowm", "Month of that lowest cash", f"=MIN({rowf(f'round.{n}.lowmonth')})", "0"),
                ("min", "First month cash falls below your minimum", f'=IF({bm}=999,"never",{bm})', "0"),
                ("cash", "Cash right after the close", f"=INDEX({rowf('cf.end')},{mo})", self.money),
                ("rr24", "Revenue run-rate 24 months after the close (× 12)", f"=INDEX({rowf('pl.rev')},MIN(60,{mo}+23))*12", self.money),
                ("ppl24", "People 24 months after the close", f"=INDEX({rowf('team.heads')},MIN(60,{mo}+23))", "#,##0"),
            ]
            for key, label, f, fmt in lines:
                ws.cell(r, 1, label)
                ws.cell(r, 2, f).number_format = fmt
                self.fs_cells[n][key] = f"B{r}"
                r += 1
            for i, h in enumerate(["Use of funds, 18 months after the close", "All spending in the window", "Share", "Plan (share of round)", "Plan amount"]):
                c = ws.cell(r, 1 + i, h)
                c.fill, c.font = F_HEAD, WHITE_BOLD
            r += 1
            first = r
            for ck, cname in UOF:
                ws.cell(r, 1, cname)
                ws.cell(r, 2, f"=SUM({rowf(f'round.{n}.spend.{ck}')})").number_format = self.money
                ws.cell(r, 3, f"=IF(SUM(B{first}:B{first + len(UOF) - 1})=0,0,B{r}/SUM(B{first}:B{first + len(UOF) - 1}))").number_format = "0%"
                if rd.get("use_of_funds"):
                    pn = self.name_of(f"round.{n}.uof.{ck}")
                    ws.cell(r, 4, f"={pn}").number_format = "0%"
                    ws.cell(r, 5, f"={pn}*{am}").number_format = self.money
                else:
                    ws.cell(r, 4, "no plan set")
                r += 1
            last = r - 1
            ws.cell(r, 1, "Total spending in the window").font = BOLD
            ws.cell(r, 2, f"=SUM(B{first}:B{last})").number_format = self.money
            r += 1
            ws.cell(r, 1, "Less: revenue in the same window")
            ws.cell(r, 2, f"=SUM({rowf(f'round.{n}.rev')})").number_format = self.money
            r += 1
            ws.cell(r, 1, "Burn the round has to cover (spending − revenue)").font = BOLD
            ws.cell(r, 2, f"=MAX(0,B{r - 2}-B{r - 1})").number_format = self.money
            ws.cell(r, 3, f"=IF({am}=0,0,B{r}/{am})").number_format = "0%"
            ws.cell(r, 4, "of the round")
            self.fs_cells[n]["burn"], self.fs_cells[n]["burnpct"] = f"B{r}", f"C{r}"
            r += 2
        ws.cell(r, 1, "A round is judged by what it buys: how low cash gets after it, when the company breaks even, and where the money goes.").font = ITALIC

    # ------------------------------------------------------------ dashboard
    def build_dashboard(self):
        N = "Dashboard"
        ws = self.sheet(N, "summary", f"{self.s['company']['name']}: dashboard", "The model on one page: five years in a few rows, each round and what it buys, the checks. Every number is a formula; change Assumptions and this page moves.")
        ws.column_dimensions["A"].width = 46
        for c in "BCDEF":
            ws.column_dimensions[c].width = 17
        ws.column_dimensions["G"].width = 4
        A = "Annual P&L"
        r = 5
        ws.cell(r, 1, "Scenario in use").font = BOLD
        ws.cell(r, 2, f"={self.name_of('scenario')}" if "scenario" in self.inputs else "Base")
        ws.cell(r + 1, 1, "Model checks").font = BOLD
        ws.cell(r + 1, 2, "=Checks!B4")
        r += 3
        heads = ["Five years", "Year 1", "Year 2", "Year 3", "Year 4", "Year 5"]
        for i, h in enumerate(heads):
            c = ws.cell(r, 1 + i, h)
            c.fill, c.font = F_HEAD, WHITE_BOLD
        r += 1
        def arow(label, sheet, rid, fmt=None, expr=None):
            nonlocal r
            ws.cell(r, 1, label)
            for y in range(1, 6):
                col = mcol(y)
                if expr:
                    f = expr(col)
                else:
                    sh, row = self.rows[f"a.{sheet}.{rid}"]
                    f = f"={q(sh)}!{col}{row}"
                c = ws.cell(r, 1 + y, f)
                c.number_format = fmt or self.money
            r += 1
        rr = lambda rid: self.rows[f"a.{A}.{rid}"][1]
        arow("Revenue", A, "pl.rev")
        arow("Gross margin", A, None, "0%", lambda col: f"=IF({q(A)}!{col}{rr('pl.rev')}=0,0,{q(A)}!{col}{rr('pl.gp')}/{q(A)}!{col}{rr('pl.rev')})")
        arow("EBITDA (operating profit)", A, "pl.ebitda")
        arow("Net income", A, "pl.ni")
        arow("Cash at year end", "Annual Cash Flow", "cf.end")
        sh, row = self.rows["a.Annual Cash Flow.cf.end"]
        ws.cell(r, 1, "Lowest cash in the year")
        for y in range(1, 6):
            a, b = mcol(12 * (y - 1) + 1), mcol(12 * y)
            cr = self.rows["cf.end"][1]
            ws.cell(r, 1 + y, f"=MIN({q('Monthly Cash Flow')}!{a}{cr}:{b}{cr})").number_format = self.money
        r += 1
        for seg in self.s["segments"]:
            arow(f"{seg['name']}: new customers in the year", A, f"{seg['key']}.new", "#,##0")
            arow(f"{seg['name']}: active at year end", A, f"{seg['key']}.end", "#,##0")
        arow("People at year end", A, "team.heads", "#,##0")
        r += 1
        bm = f"MIN({self.rrange('pl.bem', N)})"
        ws.cell(r, 1, "Break-even month (profitable from then on)").font = BOLD
        ws.cell(r, 2, f'=IF({bm}=999,"not within five years",{bm})')
        ws.cell(r, 3, f'=IF({bm}=999,"",DATE(YEAR({self.name_of("start")}),MONTH({self.name_of("start")})+{bm}-1,1))').number_format = "mmm yyyy"
        r += 2
        for i, h in enumerate(["Rounds (detail on Funding)", "Amount", "Founders after", "Lowest cash after", "Month of it", "Burn it covers"]):
            c = ws.cell(r, 1 + i, h)
            c.fill, c.font = F_HEAD, WHITE_BOLD
        r += 1
        for n in range(1, self.n_rounds + 1):
            fc = self.fs_cells[n]
            ws.cell(r, 1, f"Round {n}: {self.s['funding']['rounds'][n - 1]['name']}")
            for col, (key, fmt) in enumerate([("amount", self.money), ("after", "0.0%"), ("low", self.money), ("lowm", "0"), ("burnpct", "0%")], 2):
                ws.cell(r, col, f"=Funding!{fc[key]}").number_format = fmt
            r += 1
        r += 1
        add_charts(self.wb, self.rows, self.cur_code, sheet=N, anchors=("H5", "H22", None))

    # ------------------------------------------------------------ checks
    def build_checks(self):
        N = "Checks"
        ws = self.sheet(N, "calc", "Model checks", "Live checks that recalculate with every edit. All must read OK before the model goes to anyone.")
        ws.column_dimensions["A"].width = 60
        ws.column_dimensions["B"].width = 70
        r = 6
        B = "Monthly Balance Sheet"
        chk = []
        bsr = self.rows["bs.check"][1]
        rng = f"{q(B)}!{mcol(1)}{bsr}:{mcol(MONTHS)}{bsr}"
        items = [
            ("Balance sheet balances in every month", f"=IF(AND(MAX({rng})<=0.5,MIN({rng})>=-0.5),\"OK\",\"ERROR: assets do not equal liabilities + equity\")"),
            ("Annual revenue equals the sum of monthly revenue", f"=IF(ABS(SUM({self.annual_range('Annual P&L', 'pl.rev')})-SUM({self.month_range('pl.rev')}))<1,\"OK\",\"ERROR: annual and monthly revenue differ\")"),
            ("Cash: start + every year's net change = year-5 ending cash",
             f"=IF(ABS({self.iref('starting_cash', N)}+SUM({self.annual_range('Annual Cash Flow', 'cf.net')})-{self.ref('cf.end', MONTHS, N)})<1,\"OK\",\"ERROR: cash does not tie\")"),
            ("Cash never goes below zero", f"=IF(MIN({self.month_range('cf.end')})>=0,\"OK\",\"WARNING: cash goes negative; see Monthly Cash Flow, 'Lowest cash so far'\")"),
            ("Cash stays above the minimum you set", f"=IF(MIN({self.month_range('cf.end')})>={self.iref('min_cash')},\"OK\",\"WARNING: cash falls below the minimum; see Monthly Cash Flow, 'Lowest cash so far'\")"),
            ("Every segment has churn above zero", "=IF(AND(" + ",".join(f"{self.iref(seg['key'] + '.churn', N)}>0" for seg in self.s["segments"]) + "),\"OK\",\"WARNING: a churn of 0 means customers stay forever\")"),
        ]
        cap = self.rows["fs.captotal"]
        last_col = get_column_letter(2 + self.n_rounds)
        items.append(("Who owns what adds to 100% after every round", f"=IF(AND(MIN(Funding!B{cap[1]}:{last_col}{cap[1]})>0.9999,MAX(Funding!B{cap[1]}:{last_col}{cap[1]})<1.0001),\"OK\",\"ERROR: the ownership table does not add to 100%\")"))
        for seg in self.s["segments"]:
            sk = seg["key"]
            chans = "+".join(f"SUM({self.month_range(sk + '.' + ch['key'] + '.new')})" for ch in seg["channels"])
            items.append((f"{seg['name']}: new customers equal the sum of its own channels (Acquisition)",
                          f"=IF(ABS(SUM({self.month_range(sk + '.new')})-({chans}))<0.01,\"OK\",\"ERROR: Customers and Acquisition disagree for this segment\")"))
        ws.cell(5, 1, "Check").font = WHITE_BOLD
        ws.cell(5, 2, "Result").font = WHITE_BOLD
        ws.cell(5, 1).fill = ws.cell(5, 2).fill = F_HEAD
        for label, f in items:
            ws.cell(r, 1, label)
            ws.cell(r, 2, f)
            chk.append(f"B{r}")
            r += 1
        ws.cell(4, 1, "Overall").font = BOLD
        ws.cell(4, 2, "=IF(OR(" + ",".join(f'LEFT({c},5)="ERROR"' for c in chk) + "),\"ERRORS: the model is broken, see below\",IF(AND(" + ",".join(f'{c}="OK"' for c in chk)
                + "),\"ALL CHECKS PASS\",\"PASS WITH WARNINGS: the math is sound, the plan has a problem to discuss (see below)\"))").font = BOLD
        self.rows["checks.overall"] = (N, 4)

    def month_range(self, rid):
        sh, row = self.rows[rid]
        return f"{q(sh)}!{mcol(1)}{row}:{mcol(MONTHS)}{row}"

    def annual_range(self, sheet, rid):
        sh, row = self.rows[f"a.{sheet}.{rid}"]
        return f"{q(sh)}!{mcol(1)}{row}:{mcol(5)}{row}"

    # ------------------------------------------------------------ charts, waterfalls, test drive
    def build_charts(self):
        self.sheet("Charts", "summary", "Charts", "Revenue against expenses (where they cross, the company makes money; the area between them is profit or loss), cash in the bank, and founders' value.")
        add_charts(self.wb, self.rows, self.cur_code)

    def build_waterfalls(self):
        ws = self.sheet("Waterfalls", "log", "Waterfalls: how the forecast has moved",
                        "Each block starts with the budget (pasted as values when the model was built). Every monthly update adds one row: actual months to the left (red when below budget), the new forecast to the right. Read the trend down each column: forecasts climbing toward a month are good news, forecasts sliding are an early warning.")
        ws.column_dimensions["A"].width = 34
        for m in range(1, 13):
            ws.column_dimensions[get_column_letter(1 + m)].width = 15
        self.wf = {}
        r = 5
        blocks = [(f"cust.{seg['key']}", f"CUSTOMERS: {seg['name']} (end of month)") for seg in self.s["segments"]] + [("revenue", "REVENUE (monthly, all segments)"), ("cash", "CASH (end of month)")]
        for key, title in blocks:
            ws.cell(r, 1, title).font = BOLD
            for c in range(1, 14):
                ws.cell(r, c).fill = F_SECTION
            r += 1
            ws.cell(r, 1, "Row")
            for m in range(1, 13):
                ws.cell(r, 1 + m, f"='Monthly P&L'!{mcol(m)}5").number_format = "mmm yy"
            for c in range(1, 14):
                ws.cell(r, c).fill, ws.cell(r, c).font = F_HEAD, WHITE_BOLD
            self.wf[key] = r + 1
            self.rows[f"wf.{key}"] = ("Waterfalls", r + 1)  # first data row (the budget); the scripts find blocks by id
            r += 15
        ws.cell(r, 1, "Method: paste values, never formulas, so each row stays the forecast you believed that month.").font = ITALIC

    def build_test_drive(self):
        ws = self.sheet("Test Drive", "log", "Test drive: what moves the cash",
                        "Each row changes ONE assumption, recalculates the whole model, and records the result against the base case. Written by the agent's test-drive run; to repeat by hand, change the assumption, note the year-5 cash, change it back.")
        ws.column_dimensions["A"].width = 62
        for c in "BCDEF":
            ws.column_dimensions[c].width = 18
        ws.column_dimensions["G"].width = 110

    def build_readme(self):
        s, co = self.s, self.s["company"]
        ws = self.sheet("README", "readme", f"{co['name']}: financial model", co.get("description", ""))
        ws.column_dimensions["A"].width = 30
        ws.column_dimensions["B"].width = 120
        r = 5
        def put(a, b="", bold=False, fill=None):
            nonlocal r
            ws.cell(r, 1, a).font = BOLD if bold else BLACK
            c = ws.cell(r, 2, b)
            c.alignment = WRAP
            if fill:
                ws.cell(r, 1).fill = fill
                ws.cell(r, 2).fill = fill
            r += 1
        put("What this is", "A mathematical representation of how this business works. You change the inputs on Assumptions; every other tab recalculates. One model, many sets of projections: change the inputs, get a new set.", True)
        put("", "Every model is wrong. What has to be right is the math (visitors × conversion = new customers; customers × churn = lost customers). The inputs get replaced by real numbers, month after month, and the forecast sharpens.")
        put("")
        put("How to read the colors", "", True, F_SECTION)
        put("Bold blue on yellow", "An input. Edit these, on the Assumptions tab only.", fill=F_INPUT)
        ws.cell(r - 1, 1).font = BLUE
        put("Bold blue on orange", "A decisive input: one of the few assumptions that decide whether this is a great business.", fill=F_KEY)
        ws.cell(r - 1, 1).font = BLUE
        put("Black on white", "A formula. Do not type over it: add or change an assumption instead. Calculation tabs are locked: in Excel without a password (Review > Unprotect Sheet to type a month's actuals); in Google Sheets with a warning, set by the 'Model > Lock calculated tabs' menu after each upload, because Google drops Excel's protection on import.")
        put("Gray column", "History: an actual month, typed in during the monthly update. It never recalculates.", fill=F_HIST)
        put("Green tabs", "Logs (Waterfalls, Test Drive): values written as a record.")
        put("Named inputs", "Every input has a name, so formulas read like the business: =clinics_churn, not Assumptions!B12. Formulas > Named ranges lists them all.")
        put("Status and source", "On Assumptions, every input says how much it is worth: measured, quoted, benchmark, estimate, assumption or decided, and where it came from. Investors ask.")
        put("Moves", "On Assumptions, each input lists the tabs it changes, read from the formulas themselves: directly, then downstream. Each tab's line 4 says which tabs feed it and which it feeds.")
        put("Scenario switch", "Top of Assumptions: pick Pessimistic, Base or Optimistic and the decisive inputs change together. Show the downside live, then switch back.")
        put("")
        put("The tabs", "", True, F_SECTION)
        tabs = [("Dashboard", "The model on one page: five years, each round and what it buys (lowest cash after it, break-even month, use of funds), the checks, the charts."),
                ("Assumptions", "Every input, with its status (measured, quoted, estimate...) and source, and the tabs it moves. The scenario switch sits at the top. Start here."), ("Annual P&L", "Five-year income statement, summed from the monthly P&L."), ("Annual Cash Flow", "How much cash the plan needs and when; year-5 cash bottom right."),
                ("Annual Balance Sheet", "Year-end snapshots, with founders' ownership and value."),
                ("Funding", "The rounds, who owns what after each, what each round buys (lowest cash, the minimum line, burn it covers) and use of funds against the plan."), ("Unit Economics", "LTV against CAC, per segment and per channel; months to pay back."),
                ("Charts", "Revenue vs expenses, cash, founders' value."), ("Test Drive", "What happens to cash when one assumption moves: the levers that matter, and the ones to say no to."),
                ("Waterfalls", "Customers, revenue and cash: the budget, then each month's revised forecast."), ("Acquisition", "Each channel's lever × conversion = new customers."),
                ("Customers", "Beginning + new − lost = ending customers; revenue and direct cost per line."), ("Team", "Headcount and payroll by role."),
                ("Monthly P&L", "Income statement by month."), ("Monthly Balance Sheet", "Assets, liabilities and equity by month, with a check row that must be 0."),
                ("Monthly Cash Flow", "Cash in and out, runway, lowest cash so far."), ("Funding by month", "The month-by-month engine behind Funding: cash raised, ownership sold, loans, founders' ownership and value."), ("Checks", "Live checks; all must read OK.")]
        for a, b in tabs:
            put(a, b)
        put("")
        put("This business", "", True, F_SECTION)
        for seg in s["segments"]:
            chs = ", ".join(ch["name"] for ch in seg["channels"])
            lns = ", ".join(ln["name"] for ln in seg["revenue_lines"])
            put(seg["name"], f"Customers arrive through: {chs}. Each customer produces: {lns}.")
        if self.key:
            put("Decisive assumptions", "Highlighted orange on Assumptions. Get these right and the rest can be tweaked: " + ", ".join(self._input_label(k) for k in s.get("key_assumptions", [])) + ".")
        put("")
        put("The monthly update", "", True, F_SECTION)
        for i, t in enumerate([
            "Once a month, when the books close: duplicate this file first (keep the old version).",
            "Put each actual next to what the model predicted for that month (revenue per line, new and lost customers, spend, cash).",
            "Ask why the model was wrong and fix the ASSUMPTIONS, never the output: was churn different? spend? conversion? Tweak them until the formulas reproduce the actual month.",
            "Then type the actual numbers over that month's formulas (Customers, Monthly P&L), and gray the column: it is history now.",
            "Paste the new forecast for customers, revenue and cash as a new row on Waterfalls.",
            "The corrected assumptions now drive every future month: that is how the forecast sharpens. About 90 minutes, and the most useful 90 minutes of the month."], 1):
            put(f"Step {i}", t)
        put("")
        put("Using it with investors", "", True, F_SECTION)
        for t in ["Show a one-slide summary (five years, a handful of rows from the annual tabs) in the deck; keep the model for a working session.",
                  "Open the session with: the one thing I know for sure about this model is that it's wrong. Then invite them to change any assumption they doubt.",
                  "Give each investor their own copy, named with the investor and the date, so you both look at the same file later.",
                  "Investors read Excel: export an .xlsx copy for them even if you work in Google Sheets."]:
            put("", t)
        put("")
        put("Simplifications", "Customers can be fractional (it is an average). Revenue is booked when a customer signs or orders, even if the service is delivered over the following months (cash is right; the P&L is early). No depreciation or equipment purchases. Loans are repaid in one payment. A SAFE is held at its post-money cap. Taxes use a simple loss carry-forward. Spend, activities and headcount step by year. Add complexity only when it would change a decision: each step adds error and monthly upkeep.", True)
        put("Method", "Bottom-up venture model after Troy Henikoff's financial modeling class for Techstars founders. Built by the AIOS financial-modeler agent.")
        put("Built", dt.date.today().isoformat())

    def _input_label(self, iid):
        sh, cell = self.inputs[iid]
        row = cell[0] if isinstance(cell, tuple) else int(cell[1:])
        return self.ws_a.cell(row, 1).value

    # ------------------------------------------------------------ actuals + map
    def apply_actuals(self):
        act = self.s.get("actuals")
        if not act:
            return
        for rid, vals in act.get("rows", {}).items():
            sh, row = self.rows[rid]
            ws = self.wb[sh]
            for m, v in enumerate(vals, 1):
                c = ws.cell(row, FIRST_COL + m - 1, v)
                c.fill = F_HIST
        for m in range(1, act.get("months", 0) + 1):
            for sh in ["Acquisition", "Customers", "Team", "Monthly P&L", "Monthly Balance Sheet", "Monthly Cash Flow", "Funding by month"]:
                self.wb[sh].cell(5, FIRST_COL + m - 1).fill = F_HIST
                self.wb[sh].cell(5, FIRST_COL + m - 1).font = BOLD

    def write_map(self):
        ws = self.wb.create_sheet("_rows")
        ws.append(["id", "sheet", "row_or_cell", "kind"])
        for rid, (sh, row) in self.rows.items():
            ws.append([rid, sh, row, "row"])
        for iid, (sh, cell) in self.inputs.items():
            ws.append([iid, sh, cell if isinstance(cell, str) else f"{cell[0]}:{cell[1]}", "input"])
        ws.sheet_state = "hidden"

    def build(self, out):
        self.build_assumptions()
        # summary tabs are created first (for tab order) but filled after the engine exists
        order = ["README", "Assumptions"]
        self.build_acquisition()
        self.build_customers()
        self.build_team()
        self.build_pl()
        self.build_bs_cf()
        self.build_funding()
        self.build_annuals()
        self.build_unit_economics()
        self.build_charts()
        self.build_funding_summary()
        self.build_dashboard()
        self.build_test_drive()
        self.build_waterfalls()
        self.build_checks()
        self.build_readme()
        self.define_names()
        self.apply_actuals()
        self.write_map()
        want = ["README", "Dashboard", "Assumptions", "Annual P&L", "Annual Cash Flow", "Annual Balance Sheet", "Funding", "Unit Economics", "Charts", "Test Drive", "Waterfalls",
                "Acquisition", "Customers", "Team", "Monthly P&L", "Monthly Balance Sheet", "Monthly Cash Flow", "Funding by month", "Checks", "_rows"]
        self.wb._sheets = [self.wb[n] for n in want]
        self.wb.active = 0
        for ws in self.wb.worksheets:
            ws.sheet_properties.pageSetUpPr = PageSetupProperties(fitToPage=True)
        if out:
            self.wb.save(out)


LOCK_GS = '''// {name}: lock the calculated tabs in Google Sheets.
// Google Sheets drops Excel's sheet protection when an .xlsx is imported or replaces a Sheet,
// so run this after every upload. Once pasted it stays with the file and adds a menu:
//   First time: Extensions > Apps Script > paste > Save > Run lockCalcTabs (approve the prompt).
//   After that: menu "Model" > "Lock calculated tabs" after every upload (an upload recreates the
//   tabs, so their protection goes; if the Model menu is gone after an upload, paste this again).
// Warning-only: anyone can still edit (a month's actuals), but Sheets asks first.
const LOCKED_TABS = {tabs};
const NOTE = "Calculated: change the input on Assumptions instead (or type a closed month's actuals, on purpose).";

function onOpen() {{
  SpreadsheetApp.getUi().createMenu("Model").addItem("Lock calculated tabs", "lockCalcTabs").addToUi();
}}

function lockCalcTabs() {{
  const ss = SpreadsheetApp.getActive();
  let n = 0;
  LOCKED_TABS.forEach(function (name) {{
    const sh = ss.getSheetByName(name);
    if (!sh) {{ Logger.log("missing tab: " + name); return; }}
    sh.getProtections(SpreadsheetApp.ProtectionType.SHEET).forEach(function (p) {{
      if (p.getDescription() === NOTE) p.remove();
    }});
    sh.protect().setDescription(NOTE).setWarningOnly(true);
    n++;
  }});
  SpreadsheetApp.getActive().toast("Locked " + n + " calculated tabs (warning only).");
}}
'''


def write_lock_script(wb, out, company):
    tabs = [ws.title for ws in wb.worksheets if ws.protection.sheet]
    path = out[:-5] + "-lock-calc-tabs.gs" if out.endswith(".xlsx") else out + "-lock-calc-tabs.gs"
    with open(path, "w") as f:
        f.write(LOCK_GS.format(name=company, tabs=json.dumps(tabs)))
    return path


def add_charts(wb, rows, currency, sheet="Charts", anchors=("A5", "A22", "A39")):
    """Draw the charts on a tab from the row map. Also used after a re-load
    (monthly_update.py), because openpyxl drops charts when it reads a file."""
    from openpyxl.chart.series import SeriesLabel
    ws = wb[sheet]

    def add(title, refs, anchor):
        ch = LineChart()
        ch.title, ch.height, ch.width = title, 8, 26
        ch.y_axis.title, ch.x_axis.title = currency, "Month"
        for sh, row, name in refs:
            ch.add_data(Reference(wb[sh], min_col=FIRST_COL, max_col=FIRST_COL + MONTHS - 1, min_row=row, max_row=row), from_rows=True, titles_from_data=False)
            ch.series[-1].tx = SeriesLabel(v=name)
        ch.set_categories(Reference(wb["Monthly P&L"], min_col=FIRST_COL, max_col=FIRST_COL + MONTHS - 1, min_row=6, max_row=6))
        ws.add_chart(ch, anchor)

    charts = [("Revenue vs expenses", [("Monthly P&L", rows["pl.rev"][1], "Revenue"), ("Monthly P&L", rows["pl.costs"][1], "Total expenses")]),
              ("Cash in the bank", [("Monthly Cash Flow", rows["cf.end"][1], "Cash at end of month")]),
              ("Founders' value", [(rows["fund.fv"][0], rows["fund.fv"][1], "Founders' value")])]
    for (title, refs), anchor in zip(charts, anchors):
        if anchor:
            add(title, refs, anchor)


def main():
    import os
    spec = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    layout = Model(spec)
    layout.build(None)          # pass 1: row numbers only
    model = Model(spec, known=layout.rows)
    model.build(out)            # pass 2: every formula, written immediately
    # Evaluate the saved file's formulas, then paste the results that must be VALUES
    # (the waterfall budget and the test-drive log) into the in-memory workbook and save
    # again. Saving from memory keeps the charts, which openpyxl drops on re-load.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from drive import Ev, impact_map, write_impact, write_test_drive, write_waterfall_row
    ev = Ev(out)
    stamp = dt.date.today().isoformat()
    wf = ev.waterfall_values()
    for key, vals in wf.items():
        write_waterfall_row(model.wb["Waterfalls"], model.wf[key], f"Budget (built {stamp})", vals, "#,##0" if key.startswith("cust.") else model.money)
    for rid in layout.rows:
        assert model.rows.get(rid) == layout.rows[rid], f"pass 2 laid out {rid} differently"
    base, rows, extra = ev.test_drive()
    write_test_drive(model.wb["Test Drive"], base, rows, extra, model.money, stamp)
    per_input, feeds, fed_by = impact_map(ev)
    write_impact(model.wb, ev, per_input, feeds, fed_by)
    model.wb.save(out)
    gs = write_lock_script(model.wb, out, spec["company"]["name"])
    print(f"built {out}")
    print(f"Google Sheets lock script: {gs}")


if __name__ == "__main__":
    main()

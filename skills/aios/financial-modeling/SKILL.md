---
name: financial-modeling
description: Build, test-drive and keep alive a founder's bottom-up financial model (five years, monthly, three statements, unit economics per channel, funding and founders' value, waterfalls), as a Google Sheet when a Google Workspace connector is present, else an Excel file. Interviews the founder about how the business actually works, writes a business spec, generates the workbook with live formulas (inputs only on Assumptions; every other cell a formula), verifies it, runs the sensitivity test drive, and runs the monthly update that turns actuals into a sharper forecast. Use when someone asks for a financial model, projections, a forecast, a revenue model, unit economics (LTV, CAC, payback), a runway or burn plan, how much to raise and what it costs in dilution, or to update their model with last month's numbers.
---

# Financial modeling (bottom-up, founder-built)

The model is a mathematical representation of how the business works: inputs the founder controls (spend per channel, reps, price, money raised) drive the outputs. One model, many sets of projections. Every model is wrong; the math must be right. The value is in the questions it forces, the test drive it allows, and the monthly update that replaces guesses with real numbers.

Method credit: Troy Henikoff's financial-modeling class for Techstars founders. The rules below are his, distilled.

## The non-negotiables

1. **Revenue first.** Spend 90% of the effort on where customers come from and what each one pays. Expenses are a function of customers, of people, or of neither.
2. **No growth rates as drivers.** "Customers grow 20% a month" is fiction nobody controls. Every new customer comes from a lever × a conversion: spend ÷ cost per click × conversion; reps × closes per rep; events × attendees × conversion; free visitors × conversion.
3. **Parsimony.** Model the result, not the activity (closes per rep, not dials per rep). Add complexity only when it would change a decision.
4. **Inputs only on Assumptions, in bold blue on yellow.** Never a number typed into a formula. Long labels, no acronyms, churn always per month, every money figure with its currency.
5. **Three statements, monthly, timeline across; annual is a roll-up.** The language investors read.
6. **LTV on contribution margin, never revenue. CAC per channel, forward-looking, fully loaded, never blended.** Rules of thumb for recurring revenue: LTV/CAC ≥ 3, payback ≤ 12 months; they trade off.
7. **The founder builds it and knows it.** You co-build. You never hand over a template, and you never fill in the business from another company's model: a reference, never a template.
8. **Update monthly.** Fix the assumptions until the formulas reproduce the actual month, then hard-code and gray that month. Waterfalls record how the forecast moved.

## The flow

### 1. Interview (the founder's words, not spreadsheet words)

Read what the vault already knows first (venture context: offerings, pricing, GTM; project notes), so you only ask what is missing. Then ask, in this order, in plain language. One block at a time; recommend a default where you can; mark every number the founder doesn't know as an assumption to replace with the first real month.

1. **The business in two lines.** What do you sell, to whom, and how does money come in?
2. **Customer groups.** Are there groups that arrive differently or pay differently (consumers vs businesses, individuals vs teams)? Each becomes a *segment*.
3. **For each segment, how do customers arrive?** For each way: what do you spend or do, and what comes out? This picks the channel type:
   - you pay per click or lead → `paid` (monthly spend per year, cost per click/lead, conversion)
   - it comes free (search, referrals, word of mouth) → `organic` (visitors in month 1, monthly growth, conversion)
   - people or recurring activities produce customers (sales reps, events, workshops, partners, chapters) → `activity` (how many per year, customers each produces per month, loaded cost of each per month)
4. **What does one customer pay?** Each way they pay is a *revenue line*: a subscription or a repeat order (`basis: active`: units per active customer per month × price) or a one-time fee or first purchase (`basis: new`: units per new customer × price). Gross margin per line.
5. **How long do they stay?** Churn per month (if they say "per year", convert and say so). Seasonality if there is a known pattern: does it move only new customers, or reorders too (December gifts)?
6. **Costs that grow with customers:** per-customer costs (hosting, packaging, payment fees) and roles that grow with customers (support: one person per N customers).
7. **The team by year,** with monthly salaries; taxes and benefits load; per-employee costs; fixed monthly costs.
8. **Working capital:** days customers take to pay; days you take to pay suppliers; days of inventory.
9. **Money:** cash in the bank today; for a business already running, what customers owe it, the stock on hand and what it owes suppliers; loans (amount, when it arrived, when it is repaid, rate); rounds (SAFE with post-money cap, or priced with pre-money and option pool), the month each closes; who owns what today; the revenue multiple to value the company; tax rate.
10. **The three assumptions that decide this business** (ask the founder; propose: usually churn, the main channel's conversion or cost, and the main price or margin). They are highlighted and get a pessimistic and an optimistic value for the scenario switch (default 25% worse and better; ask what they can defend).
11. **How much is each number worth?** For the key inputs: measured (from their own data), quoted (a supplier's price), benchmark (an industry figure), estimate (their judgment), assumption (a guess to replace), decided (their call, such as a price). And the source. It goes on Assumptions; investors ask.
12. **What will each round pay for?** The planned split of the money (sales and marketing, team, direct costs, other). The Dashboard sets it against what the model actually spends in the 18 months after the close.

**Turning the founder's words into monthly numbers** (state each conversion back to them):

- "They reorder every six weeks" → 4.33 ÷ 6 = 0.72 orders per active customer per month.
- "Half are gone after six months" → monthly churn = 1 − 0.5^(1/6) = 10.9%. "We lose 1 in 30 a month" → 3.3%. "Churn is 30% a year" → 1 − 0.7^(1/12) = 2.9% a month.
- "80 people taste, one in ten buys" → 8 new customers per event.
- Mixed payment terms (cafés at 30 days, consumers by card) → receivable days weighted by revenue share (70% × 30 = 21 days).
- Two people who sell at different costs (a co-founder and a hire) → two activity channels, one cost each.
- A role that grows with customers when someone already holds it → the customer-driven role: its rounding up counts the person already there.
- A co-founder's equity → `founders_initial_share` is the founders' combined share before the first round; if the founders split it, say so in the README description.
- A customer who buys once and never again (a company buying one program) → a segment with churn 1.0 (100% a month) and a `basis: new` line; its unit economics read on the one-time margin.
- Paid upfront for a service delivered over months (a 12-week course) → book it at sign-up (cash is exact; the P&L is early by the delivery period) and say so; a follow-on subscription that starts after the course still bills from sign-up in this model.
- A commission or platform cut on every sale (a partner's 15%, card fees) → a variable cost with `pct_of_revenue`; a partner paid only by commission is an activity channel with `cost_per_unit: 0`.
- Equipment or capacity (a roaster, a second location) → not a purchase in this model: add the monthly lease or a step in fixed costs and roles by year, and name the capacity limit in the report.

**Shapes this covers** (combine freely):

| Business shape | Segments | Channels | Revenue lines |
|---|---|---|---|
| B2C subscription (box, app) | consumers | paid ads, organic | subscription (active, 1 × price); add-on (active, attach rate × price) |
| B2B SaaS | companies | paid, sales reps (activity), referrals | subscription per account (active); onboarding fee (new) |
| E-commerce / consumer goods | shoppers | paid, events or influencers (activity), organic | repeat orders (active, orders per month × average order); first order is included in the month they join |
| Wholesale / B2B goods | stores or accounts | sales reps (activity) | monthly purchases per account (active, qty × price) |
| Services / education | clients | partners or workshops (activity) | program fee (new); retainer (active) |
| Marketplace (take rate) | buyers, sellers | per side | book NET revenue: units per buyer per month × your take per unit (take rate × average value), margin = what you keep of that after direct costs. Never book the full booking value: it is not your revenue, and a valuation multiple on it overstates the company several times |

### 2. Write the spec

**Language:** the workbook's template text (tab titles, explanations, README) is English; the names you write in the spec appear as written. For a founder who reads another language, write the spec's names in their language and tell them the template text is English (a translated template is a known gap).

Save a real business's spec beside its deliverable (for a venture, in the vault where that venture's planning lives); only the imaginary demo businesses live in this skill's `examples/`. Schema, by example: `examples/clinicflow.json` (B2B SaaS: one segment, paid + sales reps + organic) and `examples/molino.json` (coffee roaster already operating: online consumers and wholesale accounts, inventory, seasonal reorders, a family loan, opening balances, MXN) `examples/rutadatos.json` (education business in Spanish: a prepaid course plus an alumni subscription, one-time corporate programs through commission-only partners, a SAFE and a priced round, COP) and `examples/tandem.json` (two-sided home-care marketplace: net take-rate revenue, processing as a share of revenue, a cost per new customer, employer benefit sales, hires by month, a seed priced at the revenue multiple). Keys:

```
company: name, description (two lines), currency (ISO code), start_month "YYYY-MM", starting_cash,
  opening_balances (optional, a business already running): {receivables, inventory, payables}
segments[]: key, name, unit, starting_customers, monthly_churn,
  channels[]: key, name, type paid|organic|activity, and per type:
    paid: spend_by_year[5], cost_per_click, conversion
    organic: start_visits, monthly_growth, conversion
    activity: count_by_year[5] (how many in a month), yield_per_unit (new customers per unit),
              cost_per_unit (one unit for a month), unit_label ("reps", "pop-ups"), unit_singular ("rep"),
              is_headcount (true when the units are people), optional count_help / yield_help / cost_help
              (your own explanation text for the Assumptions tab)
  revenue_lines[]: key, name, basis active|new, qty, qty_label, qty_unit (optional unit text), price, margin
  variable_costs[] (optional): key, name, and one of per_active_customer (amount a month), per_new_customer (once, when a customer joins: a background check, a welcome kit) or pct_of_revenue (share of this segment's revenue)
  seasonality (optional): 12 multipliers, January first
  seasonality_applies_to (optional): "new" (default) | "new_and_orders" (reorders follow the calendar too)
team: benefits_load, annual_raise (optional, e.g. 0.04),
  roles[] {key, name, monthly_salary, and either count_by_year[5] or start_month (+ end_month, count) for a hire in a given month},
  customer_driven_roles[] {key, name, segment, monthly_salary, customers_per_person},
  per_employee_monthly {name: amount}, fixed_monthly {name: amount}
working_capital: ar_days, ap_days, inventory_days
tax: rate
funding: founders_initial_share, valuation_multiple, minimum_cash (optional floor for the bank balance),
  rounds[] {name, type safe|priced, month, amount, cap (SAFE) | pre_money (priced, 0 = revenue multiple), option_pool,
            use_of_funds (optional) {sm, team, direct, other} as shares of the round},
  loans[] (optional) {name, month_in (0 = already in starting cash), amount, month_repaid (one payment; >60 = after the plan), annual_rate}
key_assumptions: up to 3 input ids, e.g. "<segment>.churn", "<segment>.<channel>.conv", "<segment>.<line>.price"
scenarios (optional): {input id: [pessimistic, optimistic]} for decisive inputs (default: 25% worse and better)
input_status (optional): {input id: [status, source]}, status one of measured|quoted|benchmark|estimate|assumption|decided (an input not listed shows blank: not stated yet). Every input id is listed in the hidden `_rows` tab (kind = input): role.<key>.salary, <segment>.<channel>.cpc, ar_days, ...
```

Input ids are the names in the workbook with dots turned to underscores (`clinics.churn` → `clinics_churn`; ids without an underscore get `in_`: `in_tax`).

### 3. Build

```bash
cd skills/aios/financial-modeling/scripts
UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python build_model.py <spec.json> <out.xlsx>
UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python drive.py <out.xlsx>
```

`build_model.py` writes the workbook, then evaluates it and pastes the waterfall budget and the test drive as values. `drive.py` is the read-only report.

Tabs: README · Dashboard · Assumptions · Annual P&L · Annual Cash Flow · Annual Balance Sheet · Funding · Unit Economics · Charts · Test Drive · Waterfalls · Acquisition · Customers · Team · Monthly P&L · Monthly Balance Sheet · Monthly Cash Flow · Funding by month · Checks (+ a hidden `_rows` map the scripts use). Every tab carries its purpose, an EDIT or DO NOT EDIT banner, a "Fed by / Feeds" line and a "How it's calculated" column. Every input has a workbook name (formulas read `=clinics_churn`), a status and source, and a "Moves" list of the tabs it changes, generated from the formula graph at build time.

### 4. Verify (all must hold before anyone sees it)

- `drive.py`: **0 formula errors, 0 hard-coded numbers in calculation tabs, and no check reading ERROR** (Checks overall = ALL CHECKS PASS, or PASS WITH WARNINGS). An ERROR means the math is broken: fix it before anything else. A WARNING (cash goes negative) means the math is sound and the plan has a problem: never hide it, never change the founder's plan to clear it; put it first in the report with the options (raise earlier, ramp slower, bridge).
- If you changed any script: `UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python skills/aios/financial-modeling/tests/test_models.py` (from the vault root) must print ALL PASS (it builds every example and proves the checks can fail).
- **Read the numbers like an investor.** Year-5 revenue per customer and margins plausible for the shape? Unit economics computed by hand for one channel match the tab? Cash low point and its month make sense against the rounds?
- **If the venture has a canon** (a brief or investor document the vault treats as the source of truth), check that the model's headline numbers (prices, round size and terms, the market figure, the adoption metric) match it, and list any line that disagrees for the founder to settle. Never quietly change either side.
- **Positive control for the evaluator:** after importing to Google Sheets, read `Checks!B4` and the Annual Cash Flow year-5 ending cash through the Sheets API; both must equal the local report. If they differ, the local evaluator is wrong for this workbook: trust Google's numbers and fix the evaluator before relying on the test drive.

### 5. Deliver: Google Sheets by default when a Workspace connector exists

- **Detect:** if a Google Workspace MCP tool that imports spreadsheets is available (`import_to_google_sheets`), offer: *"I'll create it as a Google Sheet in your Drive so you can edit it live; I'll export an .xlsx copy for each investor. Or would you rather have an Excel file?"* Google Sheets is the default. Without the connector, deliver the .xlsx.
- **First delivery: import** the built .xlsx with `import_to_google_sheets` into the folder the founder chooses (formulas, names, formats and charts carry over). Some servers only read files from an allowed directory; if the import refuses the path, copy the file into the directory it names. Share as the founder asks.
- **Excel, Google Sheets and Numbers:** Excel and Google Sheets keep the named inputs (`=clinics_churn`); Apple Numbers has no named ranges and shows each one as its cell address. Everything else works in Numbers (checked 28 Nov 2026), so send investors the .xlsx and suggest Excel or Google Sheets for reading the formulas.
- **Every later version: replace in place.** Upload the new .xlsx over the existing Sheet with `update_drive_file` (same file ID): the link, the sharing and Google's version history stay, so collaborators never chase a new link and every past version can be restored. Tab IDs (gids) change, so deep links to a tab break; links to the file don't.
- Run the positive control above on the imported Sheet.
- **Lock the calculated tabs in Google Sheets.** Google drops Excel's sheet protection whenever an .xlsx is imported or replaces a Sheet, so a Sheet built from the file is not locked at all. Every build writes `<model>-lock-calc-tabs.gs` beside the .xlsx (the protected tab names, warning-only protection, and a "Model" menu). The founder pastes it once (Extensions > Apps Script > paste > Save > run `lockCalcTabs` and approve: that locks the tabs and adds the menu on the next reload), then after every upload chooses Model > Lock calculated tabs. Proven on a live model (28 Nov 2026): the warning-only lock holds. Pasting a script and approving its access is the founder's step, never the agent's. Whether a pasted script survives an in-place replacement of the file has not been confirmed: check on the first update, and if the menu is gone, paste again.
- **Verify the lock, don't assume it:** Data > Protect sheets and ranges must list every calculated tab, and typing in a calculated cell must bring up Google's warning dialog (cancel it). A Sheet that shows no protected sheets is unlocked, whatever the .xlsx said.

### 6. Walk the founder through it (this is what makes it theirs)

Not a line reading: the logic, in this order. The business in two lines (README) → Assumptions, with the three decisive ones → one channel's math on Acquisition → one month of Customers (beginning + new − lost) → Annual Cash Flow (when does cash bottom out, and why) → Unit Economics (which channel earns its spend) → Test Drive (what moves the cash, what to say no to, the break-even churn) → Funding (founders' value, not percentage). Then ask them to change one assumption themselves and predict the result before looking.

### 7. The monthly update

When the month's books close (about 90 minutes):

1. **Duplicate first.** Google Sheets: copy the file in Drive as `<name> — before <Month YYYY>`; .xlsx: write a new file.
2. **Reconcile.** Put the actuals next to the model's month and fix assumptions, never outputs, until the gaps are small:
   `UV_CACHE_DIR="$HOME/aios/.aios-run/uv-cache" uv run --with openpyxl python monthly_update.py model.xlsx --month K --compare --set <input>=<value> ... --actual <row>=<value> ...`
3. **Record.** `... --out model-mK.xlsx` with the same `--set` and `--actual` flags: types the actuals over the month's formulas (gray), appends a waterfall row per metric (actuals left, red when below budget; new forecast right), reruns the test drive.
4. **On a Google Sheet:** export it to .xlsx (`get_drive_file_download_url`, which keeps every edit the founder made), run steps 2–3 on the export, then replace the Sheet in place with the result (`update_drive_file`, same file ID). Google's version history is the "duplicate first": the month before is one click away.
5. Tell the founder what changed and why in three lines: which assumptions were wrong, what the forecast now says, what the waterfall trend means.

Row and input ids live in the hidden `_rows` tab: `<segment>.<channel>.new` (new customers per channel, typed at its source on Acquisition), `<segment>.lost`, `<segment>.<line>.rev`, `<segment>.<channel>.spend`, `pl.rev`, `cf.end`, and every input id. An actual is always typed at its source row, so every tab agrees.

### 8. Investors

One summary slide (five years, a handful of rows from the annual tabs). The model is shown in a working session, opening with "the one thing I know for sure about this model is that it's wrong". One copy per investor, named with the investor and the date, exported to .xlsx.

## Funding, valuation and ownership (the rules the generator follows)

- **Inputs stay on Assumptions** (one place to edit, one colour code); the **Funding** tab presents every money-in decision: the rounds and loans, who owns what after each round (must add to 100%, checked), and per round what it buys (lowest cash after the close and its month, the first month below the minimum cash line, the 24-month marks) and use of funds (all spending in the 18 months after the close, against the founder's planned split, plus the burn the round actually has to cover). The month-by-month engine is its own tab, **Funding by month**, so every monthly tab shares one timeline layout.
- **A round whose pre-money is left at 0** is priced at the revenue multiple × last month's **recurring** revenue × 12 (subscriptions, repeat orders, retainers; total revenue only when the business has no recurring line). One-time fees are not worth a recurring multiple, and **cash is not added to a pre-money**: the new money buys into the business, not into its own bank account. **Company value** for founders' value is that run-rate value plus cash minus loans.
- **An option pool dilutes only when its round raises money**, so a placeholder round of 0 changes nobody's ownership.
- A SAFE is held at its post-money cap; if the next priced round prices below the cap it converts at that price and takes more (said in the README; not computed).

## Not built in (on purpose)

A hand-editable catalog tab for new revenue lines (the generator owns the structure, so a row added by hand is lost at the next rebuild; add the line to the spec instead), partner and platform economics (what makers or coaches earn outside your revenue; add as an extension for a marketplace), and growth benchmarks such as T2D3 (SaaS-only; the 3x and 12-month bars are on Unit Economics).

## Limits (say them; extend only when a decision needs it)

Customers are fractional averages. No depreciation or equipment purchases (use a lease as a fixed cost). Loans are repaid in one payment. A SAFE is held at its post-money cap. Taxes use a simple carry-forward and no local extras (Mexico's employee profit sharing, for one). Channel spend and activity counts step by year (a role can start in any month). Prices do not change by year. Extending the generator is fine (a new channel type, amortizing loans, price changes by year), as long as `tests/test_models.py` stays green, gains a test for the new behaviour, and the evaluator gains any new function it needs.

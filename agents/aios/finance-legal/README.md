# aios/finance-legal

> Accounting, legal review, invoicing, compliance. The "keep the books clean and the contracts safe" bundle.

Install this bundle if you run a business, handle invoicing, deal with contracts, or have legal/regulatory exposure.

## Agents

| Agent | What it does |
|---|---|
| [[accountant]] | Financial analysis, bookkeeping review, tax prep, cash flow modeling, P&L analysis. Reads from your finance project notes + uploaded statements |
| [[lawyer]] | Legal review of contracts, NDAs, terms of service. Risk assessment, IP/trademark analysis, dispute framing |
| [[invoice-tracker]] | Track pending invoices, flag overdue, draft follow-up emails. Useful for solo operators and small teams without dedicated AR |
| [[compliance-checker]] | Review documents against legal/regulatory requirements (GDPR, SOC2, contract clauses) before publication |
| [[financial-modeler]] | Co-builds a founder's bottom-up financial model (five years, monthly, three statements, unit economics per channel, funding and founders' value) from an interview, as a Google Sheet or Excel file; test-drives it and runs the monthly update against actuals. Uses the `financial-modeling` skill |

## When to install

- You handle your own invoicing or run a finance ops layer
- You sign contracts regularly and want a first-pass review
- Your work has regulatory exposure (healthcare, financial services, identity, etc.)

## Dependencies

- **Google Workspace MCP** — for sheets, docs, sometimes Gmail (invoice follow-ups)
- **Obsidian MCP** — to read finance project notes
- **PDF Generator** — to export polished reports
- **`uv`** (already required by the framework) — `financial-modeler` builds workbooks with `uv run --with openpyxl`

## Important note

These agents draft — they don't replace qualified legal/tax counsel. Always have material decisions reviewed by a human professional.

See [[../_index|top-level agents registry]] for the full agent vocabulary.

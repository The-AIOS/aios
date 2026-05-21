---
tags:
  - vault-commands
  - command
  - quarterly
description: Draft a structured role report with optional branded PDF export — per the pillars defined in role-expectations.md
allowed-tools: mcp__obsidian__*, Read, Write, Bash(cd ~/obsidian && git:*), Bash(ls *), Bash(cat *), Bash("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome":*)
argument-hint: "period (e.g. 'month', 'Q1 2026', 'March', '2026-03-01 to 2026-03-28')"
---

# /role-report — Role Activity Report

Draft a structured narrative report per the pillars defined in `role-expectations.md`, synthesized from role logs, daily notes, and observed context. Optionally export as a branded PDF.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /role-report` for any user overrides. Apply them to the steps below.

1. Read `USER.md` for personalizations and author info (for PDF export)
2. Read `00 - notes/context/declared/role-expectations.md` — extract role title, organization, pillars, success signals
3. **Determine period:** If argument provided, use it. Otherwise ask: "What period? (e.g. March, Q1 2026, last 3 months)"
4. **Gather data from multiple sources:**

   **Role logs** (primary narrative source):
   - List `00 - notes/logs/role-logs/{YYYY-MM}/` for the period
   - Read all matching role logs (`YYYY-MM-DD-role-log.md`)

   **Daily notes** (metrics source):
   - Read all daily notes in `01 - calendar/{YYYY-MM}/` for the period
   - Count: total tasks checked `[x]`, tasks per project, meetings from Calendar sections
   - Categorize checked tasks by pillar (match project → pillar via role-expectations.md)
   - Calculate: % core role vs not-core (tasks that map to a pillar vs those that don't)

   **Calendar data** (capacity source):
   - From daily notes' Calendar sections: count meetings, estimate hours by category
   - Categories: derive from meeting names (sales, founders, internal, external, admin)
   - Deep work = available hours - meeting hours (assume ~9h workday)

   **Observed context** (strategic context):
   - `00 - notes/context/observed/business.md` — strategic dynamics
   - `00 - notes/context/observed/session-insights.md` — recent entries in the period
   - `00 - notes/context/observed/patterns.md` — behavioral patterns relevant to role

   **Venture context** (if relevant):
   - `00 - notes/context/ventures/` — read relevant venture files

5. Synthesize into structured report (markdown)
6. Write to `01 - calendar/{YYYY-MM}/role-report-{period}.md`
7. Generate branded HTML report and save to vault (always — see Branded PDF Export below)
8. Ask: **"Want the PDF version too?"**
   - If yes → render PDF from the HTML
   - If no → done (HTML is already saved)

## Output (markdown)

```
# Role Report — {Role} @ {Organization}

**Period:** {start date} → {end date}
**Prepared:** {today's date}

## Executive Summary
{2–3 sentences: what moved this period, what the headline story is}

## Capacity Overview
- **Working days:** {N}
- **Tasks executed:** {N}
- **Core role tasks:** {N}% ({pillar breakdown})
- **Meetings:** {N} ({N}h total, {avg}h/day)
- **Deep work:** ~{N}h/day average

## {Pillar 1}

### Key activities
- {activity, date}

### Outcomes & progress
- {what moved, what didn't}

### Relationships progressed
- {who, current status}

## {Pillar 2}
...repeat for each pillar...

## Other work
{Real work that didn't map to a pillar — 2–4 bullets. Skip if nothing.}

## What didn't move
{Honest account of what was planned but didn't progress — and why}

## Next period focus
{Per pillar: one priority each}
```

## Branded PDF Export

When the user says yes to PDF export, generate a branded HTML report. Always generate **both** the HTML and the PDF. Save both to `vault/03 - export/reports/role/` (create the folder if it doesn't exist).

The design system and full HTML template are embedded below — no external template file needed.

### HTML template

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Role Report — {Name} · {Role} · {Period}</title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=Figtree:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root{--bg:#0a0915;--s1:#0f0d1a;--s2:#141220;--s3:#1a1728;--pri:#0099ff;--ora:#f97316;--pur:#8b5cf6;--grn:#22c55e;--red:#ef4444;--txt:#fff;--txt2:#888;--txtm:rgba(255,255,255,0.5);--brd:rgba(255,255,255,0.08)}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--txt);font-family:'Figtree',sans-serif;font-size:15px;line-height:1.6;padding:40px 20px}
.c{max-width:900px;margin:0 auto}
.header{text-align:center;margin-bottom:48px;padding-bottom:32px;border-bottom:1px solid var(--brd)}
.badge{display:inline-block;padding:6px 16px;background:rgba(0,153,255,0.1);color:var(--pri);font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:1.5px;border-radius:100px;margin-bottom:20px}
h1{font-family:'Plus Jakarta Sans',sans-serif;font-size:36px;font-weight:800;background:linear-gradient(135deg,#0099ff 0%,#8b5cf6 50%,#f97316 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;margin-bottom:8px}
.sub{color:var(--txt2);font-size:16px}
h2{font-family:'Plus Jakarta Sans',sans-serif;font-size:22px;font-weight:700;margin-bottom:20px}
h3{font-family:'Plus Jakarta Sans',sans-serif;font-size:16px;font-weight:600;margin-bottom:12px;color:var(--txt2);text-transform:uppercase;letter-spacing:0.5px}
.card{background:var(--s1);border:1px solid var(--brd);border-radius:16px;padding:28px;margin-bottom:24px}
.stats{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:32px}
.st{background:var(--s2);border:1px solid var(--brd);border-radius:16px;padding:24px;text-align:center}
.st .n{font-family:'Plus Jakarta Sans',sans-serif;font-size:48px;font-weight:800;line-height:1;margin-bottom:4px}
.st .l{color:var(--txt2);font-size:14px;font-weight:500}
.st .s{color:var(--txtm);font-size:12px;margin-top:4px}
.callout{background:linear-gradient(135deg,rgba(0,153,255,0.08),rgba(139,92,246,0.08));border:1px solid rgba(0,153,255,0.2);border-radius:16px;padding:24px 28px;margin-bottom:32px;font-size:17px;font-weight:500;text-align:center;line-height:1.5}
.callout strong{color:var(--pri)}
.callout em{color:var(--ora);font-style:normal;font-weight:600}
.bg{margin-bottom:16px}
.bl{display:flex;justify-content:space-between;margin-bottom:6px;font-size:14px}
.bl .t{font-weight:500}.bl .v{color:var(--txt2);font-family:'JetBrains Mono',monospace;font-size:13px}
.bt{height:28px;background:var(--s3);border-radius:8px;overflow:hidden}
.bf{height:100%;border-radius:8px;display:flex;align-items:center;padding-left:10px;font-size:12px;font-weight:600;color:rgba(255,255,255,0.9)}
.ring-row{display:flex;align-items:center;justify-content:center;gap:40px;margin:24px 0}
.ring{position:relative;width:140px;height:140px;flex-shrink:0}
.ring svg{width:140px;height:140px}
.ring-c{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center}
.ring-c .p{font-family:'Plus Jakarta Sans',sans-serif;font-size:32px;font-weight:800;color:var(--pri)}
.ring-c .ll{font-size:11px;color:var(--txtm)}
.mb{flex:1;max-width:400px}
.sum{background:var(--s2);border-radius:12px;padding:16px 20px;display:flex;gap:24px;justify-content:center;font-size:14px;color:var(--txt2)}
.sum strong{color:var(--txt);font-size:20px}
.sum .ora{color:var(--ora)}
.sum .div{border-left:1px solid var(--brd);padding-left:24px}
table{width:100%;border-collapse:collapse;font-size:14px}
th{text-align:left;padding:10px 14px;border-bottom:1px solid rgba(255,255,255,0.15);color:var(--txt2);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:0.5px}
td{padding:10px 14px;border-bottom:1px solid var(--brd)}
.tag{display:inline-block;padding:2px 10px;border-radius:100px;font-size:12px;font-weight:600}
.ty{background:rgba(34,197,94,0.15);color:var(--grn)}.tn{background:rgba(239,68,68,0.15);color:var(--red)}.tp{background:rgba(249,115,22,0.15);color:var(--ora)}
.split{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:24px}
.sc{background:var(--s2);border:1px solid var(--brd);border-radius:16px;padding:24px}
.pg{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px}
.pi{background:var(--s2);border-radius:12px;padding:16px 20px;border-left:3px solid}
.pi.do{border-left-color:var(--grn)}.pi.de{border-left-color:var(--ora)}
.pi h4{font-family:'Plus Jakarta Sans',sans-serif;font-size:14px;font-weight:600;margin-bottom:6px}
.pi p{font-size:13px;color:var(--txt2);line-height:1.5}
.al{list-style:none;counter-reset:a}
.al li{counter-increment:a;display:flex;gap:16px;margin-bottom:16px;align-items:flex-start}
.al li::before{content:counter(a);display:flex;align-items:center;justify-content:center;width:32px;height:32px;background:rgba(0,153,255,0.15);color:var(--pri);border-radius:10px;font-family:'Plus Jakarta Sans',sans-serif;font-weight:700;font-size:15px;flex-shrink:0}
.al li strong{color:var(--txt)}.al li span{color:var(--txt2);font-size:14px}
.tldr{background:linear-gradient(135deg,rgba(0,153,255,0.06),rgba(139,92,246,0.06),rgba(249,115,22,0.06));border:1px solid rgba(0,153,255,0.15);border-radius:16px;padding:28px 32px;text-align:center;margin-bottom:24px}
.tldr p{font-size:17px;line-height:1.6;font-weight:500}
.hl{background:linear-gradient(135deg,#0099ff,#8b5cf6);-webkit-background-clip:text;-webkit-text-fill-color:transparent;font-weight:700}
.footer{text-align:center;padding-top:32px;margin-top:32px;border-top:1px solid var(--brd);color:var(--txtm);font-size:13px}
.sg{margin-bottom:40px}
@media print{body{background:#0a0915;padding:20px;font-size:13px}.c{max-width:100%}.card,.st,.sc{break-inside:avoid}h1{font-size:28px}.st .n{font-size:36px}}
</style>
</head>
<body>
<div class="c">

<!-- HEADER -->
<div class="header">
<div class="badge">Internal report · {Organization from role-expectations.md}</div>
<h1>Capacity & Focus</h1>
<p class="sub">{Name from about_me.md} · {Role from role-expectations.md} · {Period}</p>
</div>

<!-- CALLOUT -->
<div class="callout">
In {period}, <strong>{N} tasks</strong> were executed across all domains.<br>
<strong>{core_pct}%</strong> were core {role} responsibilities. <em>{100-core_pct}%</em> were outside the role.
</div>

<!-- STATS GRID (4 cards) -->
<div class="stats">
<div class="st"><div class="n" style="color:var(--pri)">{N}</div><div class="l">Tasks executed</div><div class="s">{working_days} working days</div></div>
<div class="st"><div class="n" style="color:var(--ora)">{core_pct}%</div><div class="l">Core {Role}</div><div class="s">{100-core_pct}% outside role</div></div>
<div class="st"><div class="n" style="color:var(--pur)">{meetings}</div><div class="l">Meetings in period</div><div class="s">~{meeting_hours}h total</div></div>
<div class="st"><div class="n" style="color:var(--grn)">~{deep_work}h</div><div class="l">Deep work / day</div><div class="s">of {available}h available</div></div>
</div>

<!-- MEETING TIME BREAKDOWN -->
<div class="card sg">
<h2>Time in meetings</h2>
<p style="color:var(--txt2);margin-bottom:20px;font-size:14px">{working_days} working days · {available_hours}h available</p>
<div class="ring-row">
<div class="ring">
<svg viewBox="0 0 140 140"><circle cx="70" cy="70" r="58" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="14"/><circle cx="70" cy="70" r="58" fill="none" stroke="var(--pri)" stroke-width="14" stroke-dasharray="{meeting_pct_of_364} 364" stroke-dashoffset="0" stroke-linecap="round" transform="rotate(-90 70 70)" opacity="0.9"/></svg>
<div class="ring-c"><div class="p">{meeting_pct}%</div><div class="ll">in meetings</div></div>
</div>
<div class="mb">
<!-- Repeat per meeting category: -->
<div class="bg"><div class="bl"><span class="t">{Category name}</span><span class="v">{hours}h · {pct}%</span></div><div class="bt"><div class="bf" style="width:{pct}%;background:var(--grn)">{Core tag}</div></div></div>
<!-- More categories... -->
</div>
</div>
<div class="sum">
<div><strong>{avg_meetings}h</strong> avg/day in meetings</div>
<div class="div"><strong>{remaining}h</strong> remaining to execute</div>
<div class="div"><strong class="ora">~{deep_work}h</strong> deep work actual</div>
</div>
</div>

<!-- TASK DISTRIBUTION TABLE -->
<div class="card sg">
<h2>Task distribution</h2>
<table>
<thead><tr><th>Category</th><th>Tasks</th><th>Examples</th><th>Core {Role}?</th></tr></thead>
<tbody>
<!-- Repeat per category derived from pillars + daily note analysis: -->
<tr><td><strong>{Pillar/Category}</strong></td><td>~{count}</td><td style="color:var(--txt2)">{example tasks}</td><td><span class="tag ty">Yes</span></td></tr>
<tr><td><strong>{Non-core category}</strong></td><td>~{count}</td><td style="color:var(--txt2)">{example tasks}</td><td><span class="tag tn">No</span></td></tr>
<!-- .ty = Yes (green), .tn = No (red), .tp = Partial (orange) -->
</tbody>
</table>
</div>

<!-- DO / DELEGATE GRID -->
<div class="pg">
<div class="pi do"><h4>Keep doing (core)</h4><p>{Activities that map to role pillars — keep and protect}</p></div>
<div class="pi de"><h4>Delegate / reduce</h4><p>{Activities outside role — candidates for delegation or elimination}</p></div>
</div>

<!-- ACTION ITEMS -->
<div class="card">
<h2>Recommended actions</h2>
<ol class="al">
<li><div><strong>{Action 1}</strong><br><span>{Why and expected impact}</span></div></li>
<li><div><strong>{Action 2}</strong><br><span>{Why and expected impact}</span></div></li>
<!-- 3-5 numbered actions -->
</ol>
</div>

<!-- TLDR -->
<div class="tldr">
<p>{One-paragraph executive summary with <span class="hl">highlighted key insight</span> about role capacity and focus}</p>
</div>

<!-- FOOTER -->
<div class="footer">
{Author name from about_me.md} · {Role} · {Period}<br>
AI Operating System
</div>

</div>
</body>
</html>
```

### PDF generation

Write the HTML to `/tmp/role-report-{period}.html`, then:

1. **Always save HTML to vault** (the editable source):
```bash
mkdir -p ~/obsidian/vault/04\ -\ export/reports/role
cp /tmp/role-report-{period}.html "$HOME/obsidian/vault/03 - export/reports/role/{period}-role-report.html"
```

2. **Ask: "Want the PDF version too?"** If yes:
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless \
  --no-pdf-header-footer \
  --print-to-pdf="$HOME/obsidian/vault/03 - export/reports/role/{period}-role-report.pdf" \
  /tmp/role-report-{period}.html
```

HTML is mandatory. PDF is optional. Check `USER.md` → `### /role-report` for author/footer overrides.

## Rules

- Pull from logs AND daily notes — logs give narrative, daily notes give numbers
- Be honest about gaps — an empty pillar is worth noting, not hiding
- Keep the executive summary to what a board member needs in 30 seconds
- The capacity analysis (core % vs not) is the most valuable section — be precise
- Check `USER.md` → `### /role-report` for overrides before executing. Apply them to the steps above.
- Do not commit — let the user review and refine before saving
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.
- No financial disclosures in the PDF (no dollar amounts, deal sizes, invoice info).

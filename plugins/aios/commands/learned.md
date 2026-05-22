---
tags:
  - aios
  - command
  - on-demand
description: Distill the period's learnings into a reflective report with optional branded PDF — from observed context, daily notes, and growth edges
allowed-tools: mcp__obsidian__*, Read, Write, Bash(cd ~/aios && git:*), Bash(ls *), Bash(cat *), Bash("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome":*)
argument-hint: "period (e.g. 'month', 'March', 'Q1 2026', 'this week', '2026-03-01 to 2026-03-28')"
---

# /learned — Learning Report

Distill the period's learnings into a reflective report — what was understood, what shifted, what compounded. Reads from observed context, daily notes, growth edges, and patterns. Optionally exports as a branded PDF.

## When to use

After a substantive period (week / month / quarter) to distill insights into a publish-ready report. Output doubles as the source for blog posts, newsletter material, or quarterly reviews.


## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /learned` for any user overrides. Apply them to the steps below.

1. Read `USER.md` for personalizations and author info
2. **Determine period:** If argument provided, use it. Otherwise default to current month. Ask for confirmation: "Generating learning report for {period}. Correct?"
3. **Gather data from multiple sources:**

   **Observed context — current state (what's true now):**
   - `session-insights.md` — all entries in the period (richest source: raw observations per session)
   - `growth.md` — growth edges active in the period
   - `patterns.md` — behavioral patterns confirmed or shifted
   - `business.md` — strategic observations about ventures
   - `ecosystem.md` — how ventures connected, flywheel dynamics
   - `preferences.md` — working preferences discovered

   **Observed context — evolution (the goldmine):**
   - `logs/observed-snapshots/{YYYY-MM}/` — archived versions of observed files. These show HOW observations evolved over the period. Read all snapshots in the period's month folder(s).
   - Compare: what was written in an early snapshot vs what the current file says. The delta IS the learning. A growth edge that was "new" on Mar 5 and "confirmed" by Mar 25 = a real shift.
   - If a pattern was added, removed, or rewritten between snapshots, that's signal.

   **Daily notes (supporting evidence):**
   - Read all daily notes in `01 - calendar/{YYYY-MM}/` for the period
   - Extract `### Learned` sections from each close-of-day
   - Count: sessions, shipped items, growth streaks, drift items

   **Weekly summaries (already-distilled):**
   - Read weekly summaries in the period (`W{N}-summary.md`)
   - Extract `## Learnings` and `## Questions opened` sections

   **Voice calibration:**
   - `personal_voice.md` — how to write
   - `about_me.md` — thesis, values, purpose (to connect learnings to broader direction)

4. Synthesize into structured report (markdown)
5. Write to `01 - calendar/{YYYY-MM}/learned-{period}.md`
6. Generate branded HTML report and save to vault (always — see Branded PDF Export below)
7. Ask: **"Want the PDF version too?"**
   - If yes → render PDF from the HTML
   - If no → done (HTML is already saved)

## Output (markdown)

```
# What I Learned — {Period}

**Period:** {start date} → {end date}
**Sessions:** {N} working days with close-of-day entries
**Prepared:** {today's date}

## The Headline
{One paragraph: the single most important thing that was understood this period. Not what was done — what was UNDERSTOOD. The insight that changes how you work going forward.}

## Insights

### {Learning 1 — strong headline}
{Reframe → Insight → Implication. "I thought X. Turns out Y. This means Z."}
**Evidence:** {which sessions/dates showed this}
**Connected to:** [[{observed file or project}]]

### {Learning 2}
{Same structure}

### {Learning 3}
{Same structure}

{Include ALL significant learnings — don't trim for aesthetics. A week may have 3, a month may have 12. Order by impact, not chronology. If the list is long, group by theme (e.g. "System Design", "Personal Growth", "Strategic"). Never leave a real insight out just to keep the count tidy.}

## Growth Edges — What Moved

### Advancing
{Growth edges from growth.md that progressed this period — with evidence}

### Stuck
{Growth edges that didn't move — honest account of why}

### New
{Growth edges that emerged this period — first noticed when?}

## Patterns — What Changed
{Behavioral or strategic patterns that were confirmed, shifted, or broken this period. Reference patterns.md.}

## Questions Opened
{Questions that emerged but weren't answered. These are as valuable as the insights — they shape next period's focus.}

## The Compound
{How this period's learnings connect to the broader thesis (from about_me.md). What compounds from here? One paragraph, earned punchline.}
```

## Branded PDF Export

When the user says yes to PDF export, generate a branded HTML report. Always generate **both** HTML and PDF. Save both to `vault/03 - export/reports/learned/` (create the folder if it doesn't exist).

The design is reflective/editorial — lighter than role-report's operational dark theme.

### HTML template

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>What I Learned — {Period}</title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Figtree:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
@page{size:A4;margin:0}
body{font-family:'Figtree',sans-serif;color:#1a1a2e;font-size:10pt;line-height:1.65;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.page{width:210mm;min-height:297mm;padding:22mm 28mm 14mm 28mm;display:flex;flex-direction:column;page-break-after:always}
.page:last-child{page-break-after:avoid}
.page-content{flex:1}
h1{font-family:'Plus Jakarta Sans',sans-serif;font-size:28pt;font-weight:800;color:#1a1a2e;margin-bottom:4pt}
h1 span{color:#8b5cf6}
h2{font-family:'Plus Jakarta Sans',sans-serif;font-size:16pt;font-weight:700;color:#1a1a2e;margin:16pt 0 8pt 0}
h3{font-family:'Plus Jakarta Sans',sans-serif;font-size:11pt;font-weight:700;margin:12pt 0 4pt 0}
.subtitle{font-size:11pt;color:#666;margin-bottom:4pt}
.meta{font-size:8.5pt;color:#888;margin-bottom:12pt}
.divider{height:2px;background:linear-gradient(90deg,#8b5cf6,#0099ff,#10b981);margin:10pt 0;border:none}
.divider-thin{height:1px;background:#e5e7eb;margin:10pt 0;border:none}
.headline{background:linear-gradient(135deg,#f5f3ff,#eff6ff);border:1px solid #c4b5fd;border-radius:12pt;padding:18pt 22pt;margin:12pt 0;font-size:11pt;line-height:1.7;color:#333}
.insight{border-left:3px solid #8b5cf6;padding:10pt 16pt;margin:8pt 0;background:#faf9ff;border-radius:0 8pt 8pt 0}
.insight h3{color:#5b21b6;margin:0 0 4pt 0}
.insight p{font-size:9.5pt;color:#444;margin:3pt 0}
.insight .evidence{font-size:8pt;color:#888;font-style:italic;margin-top:4pt}
.growth-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10pt;margin:8pt 0}
.growth-card{background:#f8fafc;border:1px solid #e5e7eb;border-radius:8pt;padding:12pt;border-top:3px solid}
.growth-card.advancing{border-top-color:#10b981}
.growth-card.stuck{border-top-color:#f97316}
.growth-card.new{border-top-color:#0099ff}
.growth-card h4{font-family:'Plus Jakarta Sans',sans-serif;font-size:8pt;font-weight:700;text-transform:uppercase;letter-spacing:0.5pt;margin-bottom:6pt}
.growth-card.advancing h4{color:#10b981}
.growth-card.stuck h4{color:#f97316}
.growth-card.new h4{color:#0099ff}
.growth-card ul{font-size:8.5pt;padding-left:14pt;color:#555}
.growth-card li{margin:3pt 0}
.pattern{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8pt;padding:10pt 14pt;margin:6pt 0;font-size:9pt}
.pattern strong{color:#166534}
.question{background:#fffbeb;border:1px solid #fde68a;border-radius:8pt;padding:10pt 14pt;margin:6pt 0;font-size:9pt}
.question strong{color:#92400e}
.compound{background:linear-gradient(135deg,#ede9fe,#f0f7ff);border:1px solid #c4b5fd;border-radius:12pt;padding:16pt 20pt;margin:12pt 0;text-align:center}
.compound .big{font-family:'Plus Jakarta Sans',sans-serif;font-size:14pt;font-weight:800;color:#1a1a2e;margin:6pt 0}
.compound p{font-size:9.5pt;color:#555}
.footer{margin-top:auto;padding-top:10pt;border-top:1px solid #e5e7eb;display:flex;justify-content:space-between;font-size:7.5pt;color:#999}
.footer a{color:#8b5cf6;text-decoration:none}
</style>
</head>
<body>

<!-- PAGE 1 — Headline + Insights -->
<div class="page">
<div class="page-content">
  <h1>What I <span>Learned</span></h1>
  <div class="subtitle">{Period — e.g. "March 2026"}</div>
  <div class="meta">{N} working days · {N} sessions · {N} learnings distilled · Prepared {today}</div>
  <hr class="divider">

  <div class="headline">
    {The single most important understanding from the period. Not what was done — what was UNDERSTOOD. The paragraph that changes how you work going forward.}
  </div>

  <h2>Insights</h2>

  <div class="insight">
    <h3>{Learning 1 — strong headline}</h3>
    <p>{Reframe → Insight → Implication. "I thought X. Turns out Y. This means Z."}</p>
    <div class="evidence">Evidence: {dates/sessions} · Connected to: {observed file or project}</div>
  </div>

  <div class="insight">
    <h3>{Learning 2}</h3>
    <p>{Same structure}</p>
    <div class="evidence">Evidence: {dates/sessions}</div>
  </div>

  <div class="insight">
    <h3>{Learning 3}</h3>
    <p>{Same structure}</p>
    <div class="evidence">Evidence: {dates/sessions}</div>
  </div>

  <!-- 3-7 insights, ordered by impact -->

</div>
<div class="footer">
  <span>What I Learned — {Period}</span>
  <span>AI Operating System</span>
</div>
</div>

<!-- PAGE 2 — Growth + Patterns + Compound -->
<div class="page">
<div class="page-content">

  <h2>Growth Edges</h2>
  <div class="growth-grid">
    <div class="growth-card advancing">
      <h4>Advancing</h4>
      <ul>
        <li>{Edge that progressed — with evidence}</li>
        <li>{Edge that progressed}</li>
      </ul>
    </div>
    <div class="growth-card stuck">
      <h4>Stuck</h4>
      <ul>
        <li>{Edge that didn't move — honest why}</li>
        <li>{Edge that didn't move}</li>
      </ul>
    </div>
    <div class="growth-card new">
      <h4>New</h4>
      <ul>
        <li>{Edge that emerged this period}</li>
        <li>{First noticed when?}</li>
      </ul>
    </div>
  </div>

  <hr class="divider-thin">

  <h2>Patterns That Changed</h2>
  <div class="pattern">
    <strong>{Pattern name}</strong> — {What was confirmed, shifted, or broken. Reference to patterns.md.}
  </div>
  <div class="pattern">
    <strong>{Pattern name}</strong> — {Description}
  </div>

  <hr class="divider-thin">

  <h2>Questions Opened</h2>
  <div class="question">
    <strong>{Question 1}</strong> — {Why it matters. What it shapes.}
  </div>
  <div class="question">
    <strong>{Question 2}</strong> — {Context}
  </div>

  <hr class="divider-thin">

  <div class="compound">
    <p style="font-size:8pt;color:#8b5cf6;text-transform:uppercase;letter-spacing:1pt;font-weight:700">The Compound</p>
    <div class="big">{Earned punchline connecting this period's learnings to the broader thesis}</div>
    <p>{How what was learned this period connects to about_me.md values/purpose. What compounds from here.}</p>
  </div>

</div>
<div class="footer">
  <span>What I Learned — {Period}</span>
  <span>{Author name from about_me.md} · AI Operating System</span>
</div>
</div>

</body>
</html>
```

### PDF generation

Write the HTML to `/tmp/learned-{period}.html`, then:

1. **Always save HTML to vault** (the editable source):
```bash
mkdir -p ~/aios/vault/03\ -\ export/reports/learned
cp /tmp/learned-{period}.html "$HOME/aios/vault/03 - export/reports/learned/{period}-learned.html"
```

2. **Ask: "Want the PDF version too?"** If yes:
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless \
  --no-pdf-header-footer \
  --print-to-pdf="$HOME/aios/vault/03 - export/reports/learned/{period}-learned.pdf" \
  /tmp/learned-{period}.html
```

HTML is mandatory. PDF is optional. Check `USER.md` → `### /learned` for author/footer overrides.

## Rules

- **Insights over activities.** This is NOT a list of what was done — it's what was UNDERSTOOD. "Shipped 20 agents" is an activity. "USER.md solves the two-repo problem permanently" is an insight.
- **Don't cap insights artificially.** Include every significant learning. A rich month may have 12+ insights — group by theme if needed. Never leave real value on the floor to fit a number.
- **Snapshots are the goldmine.** Compare early vs late observed context snapshots. The delta between them IS the learning. A growth edge that moved from "new" to "confirmed" over the period = a real shift worth naming.
- Each learning starts with a reframe: "I thought X. Turns out Y."
- **Evidence is mandatory.** Every insight must reference specific sessions, dates, or observed context entries.
- Growth edges must be honest — "stuck" is as valuable as "advancing"
- Questions opened are as important as insights — they shape next period's focus
- The compound section connects to `about_me.md` thesis — don't force it, but look for it
- Write in the user's voice — calibrate from `personal_voice.md`
- Check `USER.md` → `### /learned` for any overrides before executing
- No financial disclosures in the PDF
- Use [[wiki-links]] for all project names, context files, and ventures mentioned

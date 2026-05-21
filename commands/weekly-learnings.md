---
tags:
  - vault-commands
  - command
  - weekly
description: Compile the week's insights from daily notes into a single writing-ready summary
allowed-tools: mcp__obsidian__*, Read, Write, Bash(cd ~/obsidian && git:*), Bash(ls:*), Bash(cat:*), Bash("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome":*)
---

# /weekly-learnings — Weekly Summary

Consolidate the week's daily notes and sessions into one summary.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /weekly-learnings` for any user overrides (author block, footer text, etc.). Apply them to the steps below.

1. Read all daily notes for this week from `01 - calendar/{YYYY-MM}/` (and previous month folder if the week spans months)
2. Read this week's entries in `00 - notes/context/observed/session-insights.md`
3. Check what changed in observed context files this week
4. Consolidate into summary

## Output

Write to `01 - calendar/{YYYY-MM}/{YYYY}-W{WW}-summary.md` with frontmatter `{"tags": ["weekly", "learnings", "vault"], "created": "{today}"}`:

```
# Week {number} Summary — {date range}

## What happened
{3-5 bullet narrative}

## Key decisions made
- {Decision}: {why and what it means}

## Learnings
- {Insight 1}
- {Insight 2}

## Questions opened
- {New questions that emerged but weren't answered}

## Momentum check
- **Accelerating**: {what gained speed}
- **Stalling**: {what lost speed}
- **New**: {what started unplanned}

## Next week signal
{One sentence on where energy should go}
```

## Rules
- Accuracy over polish — this is consolidation
- "Questions opened" is as valuable as "Decisions made"
- Keep to one page. If the week was light, say so.
- Commit and push after writing
- Use [[wiki-links]] for all project names, context files, and ventures mentioned.

---

## Branded PDF Report

After writing the markdown summary, generate a branded HTML→PDF report.

### Period auto-detection

**Default output:** MD + HTML every run. **PDF is on-request** — ask the user before rendering (see the PDF generation pipeline below, step 4). MD summary + HTML always ship; PDF requires explicit greenlight.

The weekly HTML file is `Week{N}-AI-OS.html`. If the user approves a PDF, it's `Week{N}-AI-OS.pdf`.

Additionally, detect if bigger periods close this week — same rule applies (HTML always, PDF on-request):
- **Last Friday of month** → also generate `Month{N}-AI-OS-{MonthName}.html` (+ PDF if user asks)
- **Last Friday of quarter** → also generate `Q{N}-AI-OS.html` (+ PDF if user asks)
- **Last Friday of semester** → also generate `H{N}-AI-OS.html` (+ PDF if user asks)
- **Last Friday of year** → also generate `Year-AI-OS-{Year}.html` (+ PDF if user asks)

The user can force a bigger period mid-cycle: `/weekly-learnings month` generates a monthly report even if it's not month-end. Same for `quarter`, `semester`, `year`.

For monthly/quarterly/semester/year reports, aggregate all weekly data in that period — read every daily note and weekly summary in the range.

### Design system

The design system is embedded below — no external template file needed. Key specs:

**Fonts & colors:**
- Font: `Plus Jakarta Sans` (body) + `JetBrains Mono` (code/mono)
- Import: `https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap`
- Purple: `#8b5cf6` — primary accent, hero h1, card values, divider gradient start
- Blue: `#0099ff` — secondary accent, `.value.blue`, `.eq-role.blue`
- Orange: `#f97316` — tertiary accent
- Green: `#10b981` — quaternary accent
- Dark: `#1a1a2e` — body text, equiv-card bg, table header bg
- Light gray bg: `#f8fafc` — cards, output sections, alternating table rows
- Border: `#e5e7eb`

**Layout:**
- `@page { size: A4; margin: 0; }`
- `.page { width: 210mm; min-height: 297mm; padding: 22mm 25mm 12mm 25mm; page-break-after: always; display: flex; flex-direction: column; }`
- `.page-content { flex: 1; }` — wraps all content EXCEPT the footer
- Last page: `page-break-after: avoid` (but keep `min-height: 297mm` — do NOT set `min-height: auto`)
- `body { font-size: 11pt; line-height: 1.55; -webkit-print-color-adjust: exact; print-color-adjust: exact; }`

**Components (use these CSS classes):**
- `.hero` — h1 (32pt/800), .subtitle (13pt/600), .tagline (10pt/italic)
- `.divider` — 3px gradient (`#8b5cf6 → #0099ff → #10b981`)
- `.divider-thin` — 1px `#e5e7eb`
- `.numbers-grid` — `grid-template-columns: repeat(4, 1fr)`, gap 8pt. Each `.number-card` has `.value` (22pt/800) and `.label` (7.5pt uppercase). Color variants: `.value.blue`, `.value.orange`, `.value.green` (default = purple)
- `.equiv-row` — `grid-template-columns: repeat(5, 1fr)`. Each `.equiv-card` (dark bg) has `.eq-role` (colored label), `.eq-value` (18pt white), `.eq-label` (6.5pt). Role colors: `.blue`, `.purple`, `.orange`, `.green`, `.cyan`
- `.comparison` — 2-column grid. `.compare-col.week1` (blue tint) and `.compare-col.week2` (purple tint)
- `.output-grid` — `grid-template-columns: repeat(2, 1fr)`. Each `.output-section` has h4 (colored uppercase) + ul (arrow bullets via `li::before { content: "→" }`)
- `.compound-table` — dark header, alternating rows, `.highlight` for row labels, `.week1`/`.week2` for period styling
- `.quote` — purple left border, italic, light bg
- `.oracle-box` — gradient bg (`#ede9fe → #f0f7ff`), purple border, `.big-line` for emphasis
- `.footer` — `margin-top: auto` (NOT position: absolute — that causes overlap and misalignment). 7.5pt gray, `border-top: 1px solid #e5e7eb`, `display: flex; justify-content: space-between`

### HTML template structure (3 pages)

**Page 1 — Hero + Numbers:**
```html
<div class="page">
  <div class="hero">
    <h1>Week {N}.</h1>
    <!-- For monthly: <h1>Month {N}.</h1> etc. -->
    <div class="subtitle">{One-line theme of the period}</div>
    <div class="tagline">{2-3 sentence summary of highlights}</div>
  </div>
  <hr class="divider">

  <!-- 8 metric cards in a 4×2 grid -->
  <div class="numbers-grid">
    <div class="number-card">
      <div class="value blue">{N}</div>
      <div class="label">Days shipped<br>(active working days)</div>
    </div>
    <div class="number-card">
      <div class="value">{N}</div>
      <div class="label">Tasks completed<br>(Google Tasks closed)</div>
    </div>
    <div class="number-card">
      <div class="value orange">{N}</div>
      <div class="label">Meetings attended<br>(with AI-prepared context)</div>
    </div>
    <div class="number-card">
      <div class="value green">{N}</div>
      <div class="label">Proposals &amp;<br>deliverables shipped</div>
    </div>
    <div class="number-card">
      <div class="value blue">{N}</div>
      <div class="label">Active streaks<br>(study, content, etc.)</div>
    </div>
    <div class="number-card">
      <div class="value">{N}</div>
      <div class="label">Growth edges<br>tracked</div>
    </div>
    <div class="number-card">
      <div class="value orange">{N}</div>
      <div class="label">Behavioral patterns<br>observed</div>
    </div>
    <div class="number-card">
      <div class="value green">{N}</div>
      <div class="label">Custom tools<br>built or enhanced</div>
    </div>
  </div>

  <!-- People-equivalent row -->
  <div class="equiv-row">
    <div class="equiv-card">
      <div class="eq-role blue">Engineering</div>
      <div class="eq-value">{N}</div>
      <div class="eq-label">{what was built}</div>
    </div>
    <div class="equiv-card">
      <div class="eq-role purple">Research</div>
      <div class="eq-value">{N}</div>
      <div class="eq-label">{what was researched}</div>
    </div>
    <div class="equiv-card">
      <div class="eq-role orange">Chief of Staff</div>
      <div class="eq-value">{N}</div>
      <div class="eq-label">{what was coordinated}</div>
    </div>
    <div class="equiv-card">
      <div class="eq-role green">Sales</div>
      <div class="eq-value">{N}</div>
      <div class="eq-label">{what was sold/proposed}</div>
    </div>
    <div class="equiv-card">
      <div class="eq-role cyan">Knowledge</div>
      <div class="eq-value">{N}</div>
      <div class="eq-label">{what was curated}</div>
    </div>
  </div>
  <p class="equiv-total"><strong>{total} people equivalent.</strong> One person. {One-line compound insight.}</p>

  <hr class="divider-thin">

  <!-- Period comparison -->
  <h2>{Prev Period} → {This Period}: <span class="accent">The Compound</span></h2>
  <div class="comparison">
    <div class="compare-col week1">
      <div class="compare-label">{Prev period label}</div>
      <p><strong>{Theme.}</strong> {Summary of previous period.}</p>
      <p style="margin-top: 6pt; font-size: 8pt; color: #666;">{Key stats}</p>
    </div>
    <div class="compare-col week2">
      <div class="compare-label">{This period label}</div>
      <p><strong>{Theme.}</strong> {Summary of this period.}</p>
      <p style="margin-top: 6pt; font-size: 8pt; color: #5b21b6;">{Key stats}</p>
    </div>
  </div>
  <div class="quote">{Period-defining quote}</div>
  <div class="footer">Week {N} — AI Operating System</div>
</div>
```

**Page 2 — What the Period Looked Like:**
```html
<div class="page">
  <h2>What <span class="accent">{Period}</span> Looked Like</h2>
  <p style="font-size: 9.5pt; color: #666; margin-bottom: 10pt;">{Subtitle with day count and notable context.}</p>

  <!-- 4-quadrant output grid -->
  <div class="output-grid">
    <div class="output-section">
      <h4 class="blue">Built</h4>
      <ul>
        <li>{Software, tools, infrastructure shipped}</li>
        <!-- 4-8 items -->
      </ul>
    </div>
    <div class="output-section">
      <h4>Operated</h4>
      <ul>
        <li>{Meetings, pings, proposals, coordination}</li>
      </ul>
    </div>
    <div class="output-section">
      <h4 class="orange">Integrated</h4>
      <ul>
        <li>{Context deepened, data connected, systems linked}</li>
      </ul>
    </div>
    <div class="output-section">
      <h4 class="green">Grew</h4>
      <ul>
        <li>{Study, content, personal development, health}</li>
      </ul>
    </div>
  </div>

  <hr class="divider-thin">

  <!-- Signature build highlight (optional — use for standout project/achievement) -->
  <h2>The <span class="accent">{Signature Achievement}</span> — {Period}'s Highlight</h2>
  <div class="oracle-box">
    <h3>{Headline}</h3>
    <p>{Context and story}</p>
    <div class="big-line">{Memorable one-liner}</div>
    <div class="small">{Supporting detail or attribution}</div>
  </div>

  <div class="footer">{Period} — AI Operating System</div>
</div>
```

**Page 3 — Compound Curve + Closing:**
```html
<div class="page">
  <h2>The <span class="orange">Compound Curve</span> — Updated</h2>
  <p style="margin-bottom: 4pt;"><strong>{Compound thesis statement.}</strong></p>
  <p style="font-size: 9.5pt; color: #666;">{Evidence paragraph.}</p>

  <!-- Period-over-period comparison table -->
  <table class="compound-table">
    <thead>
      <tr>
        <th></th>
        <th>{Previous Period}</th>
        <th>{This Period}</th>
        <th>Δ</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td class="highlight">People equivalent</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Tasks completed</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Meetings with AI context</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Proposals / deliverables</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Context depth</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Behavioral patterns</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Observed growth edges</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
      <tr>
        <td class="highlight">Custom tools / skills</td>
        <td class="week1">{prev}</td>
        <td class="week2">{current}</td>
        <td>{delta}</td>
      </tr>
    </tbody>
  </table>

  <hr class="divider-thin">

  <h2>What <span class="accent">Changed</span> Between {Prev} and {Current}</h2>
  <div class="output-grid">
    <div class="output-section">
      <h4 class="blue">System matured</h4>
      <ul>
        <li><strong>{Improvement.}</strong> {Detail}</li>
        <!-- 2-4 items -->
      </ul>
    </div>
    <div class="output-section">
      <h4>Person evolved</h4>
      <ul>
        <li><strong>{Growth.}</strong> {Detail}</li>
      </ul>
    </div>
  </div>

  <div class="quote" style="border-left-color: #0099ff;">
    "{Closing insight about the compound effect.}"
  </div>

  <hr class="divider-thin">

  <!-- Closing statement -->
  <div style="text-align: center; padding: 10pt 0;">
    <div style="font-size: 18pt; font-weight: 800; color: #1a1a2e; margin-bottom: 4pt;">{Previous period}: {what it did}.</div>
    <div style="font-size: 18pt; font-weight: 800; color: #8b5cf6; margin-bottom: 4pt;">{This period}: {what it did}.</div>
    <div style="font-size: 10pt; color: #999; margin-top: 8pt;">{Forward-looking teaser for next period.}</div>
  </div>

  <hr class="divider">

  <!-- Author block -->
  <div style="text-align: center; margin-top: 10pt;">
    <div style="font-size: 11pt; font-weight: 700; color: #1a1a2e;">{Author name from about_me.md}</div>
    <div style="font-size: 9pt; color: #666;">{Role + affiliations from about_me.md}</div>
    <div style="font-size: 9pt; margin-top: 3pt; color: #999;">{Website or links from about_me.md, if available}</div>
  </div>

  <div class="footer">
    This document was generated from a personal AI operating system — from vault data, not from memory.
  </div>
</div>
```

### Data sources for metrics

Gather numbers from these sources in order:

1. **Daily notes** in the period — `01 - calendar/{YYYY-MM}/{YYYY-MM-DD}.md`. Count: working days, tasks mentioned as done, meetings listed, deliverables shipped.
2. **Weekly summary** just generated — use the "What happened" and "Momentum check" sections.
3. **Project index** — `00 - notes/projects/_index.md` for active project count and status changes.
4. **Observed context** — `00 - notes/context/observed/growth.md` for growth edge count, `patterns.md` for behavioral pattern count.
5. **Prior period's HTML/PDF — MANDATORY, never estimate.** The prior HTML lives at `vault/03 - export/reports/weekly/Week{N-1}-AI-OS.html` — grep it directly. If only the PDF exists, extract text first:
   ```bash
   pdftotext "$HOME/obsidian/vault/03 - export/reports/weekly/Week{N-1}-AI-OS.pdf" /tmp/w{N-1}-content.txt
   ```
   Use this for EVERY number in the "Previous Period" column — both the narrative compare block on page 1 AND the compound curve table on page 3. If the prior file doesn't exist, flag "Prior period data not available — comparison column skipped" rather than invent. **Known failure mode (2026-04-22 cascade fix):** past runs invented prior-period numbers, producing false decline narratives — W16 reported W15 = ~12 when actual was 25; W15 reported W14 = ~18 when actual was ~29; W14 reported W13 = ~25 when actual was 10. Three weeks of fiction before correction. Never estimate prior numbers.
6. **Session insights** — `00 - notes/context/observed/session-insights.md` for the period's key learnings.

For the current period's people-equivalent row, **count** from the week's actual work — do not estimate, do not inflate. Use these role buckets as the categorization guide:
- **Engineering**: features built, tools created, pipelines set up
- **Research**: analysis done, data indexed, context deepened
- **Chief of Staff**: meetings prepped, pings sent, coordination handled
- **Sales**: proposals sent, materials created, pipeline managed
- **Knowledge**: vault curation, observed context, documentation

### PDF generation pipeline

1. Assemble the full HTML (all 3 pages) with inline CSS (use the design system embedded above — no external template file).
2. Write to `/tmp/weekly-stats-W{N}.html` (or `M{N}`, `Q{N}`, `H{N}`, `Y{YYYY}` for bigger periods).
3. **Always save HTML to vault** (the editable source):
```bash
cp /tmp/weekly-stats-W{N}.html "$HOME/obsidian/vault/03 - export/reports/weekly/Week{N}-AI-OS.html"
```

4. **Ask: "Want the PDF version too?"** If yes:
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless \
  --no-pdf-header-footer \
  --print-to-pdf="$HOME/obsidian/vault/03 - export/reports/weekly/Week{N}-AI-OS.pdf" \
  /tmp/weekly-stats-W{N}.html
```

For additional period reports, render each separately with its own filename. **Output path by period:**
- Weekly (`Week{N}-AI-OS.{html,pdf}`) → `vault/03 - export/reports/weekly/`
- Monthly (`Month{N}-AI-OS-{Name}.{html,pdf}`) → `vault/03 - export/reports/monthly/`
- Quarterly / Semester / Year (`Q{N}`, `H{N}`, `Year-AI-OS-{YYYY}` files) → `vault/03 - export/reports/monthly/` (rare; rolls up here for now)

HTML is mandatory for all. PDF is optional for all.

5. Confirm files were created and report their paths.

### PDF rules
- The HTML must be **fully self-contained** — inline CSS, Google Fonts import, no external files.
- Use the **exact CSS from the design system** embedded in this command. Do not simplify or modify.
- Content must **fit exactly 3 pages**. Adjust item counts in lists if needed to avoid overflow (6-8 items per quadrant is the sweet spot).
- Numbers must be **real** — counted from daily notes, not estimated. If a metric can't be determined, use `~{N}` with a tilde to signal approximation.
- The closing quote should be **original and specific** to the period — not generic motivation.
- Always include the author block (from `about_me.md`) and footer on page 3. Check `USER.md` → `### /weekly-learnings` for any author/footer overrides.
- **No financial disclosures.** Never include dollar amounts, revenue, deal sizes, payables, pricing percentages, tax regime details, or invoice information. Keep it productivity-focused — the PDF is shareable externally. Use generic terms: "consulting pipeline advanced", "partner fee framework designed", "compliance audit initiated".
- For periods beyond weekly, adjust the hero title (e.g., "Month 1.", "Q1.", "H1.", "2026.") and expand the comparison to cover the full range.

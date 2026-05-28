---
name: infographic-builder
description: Turn a structured document (an /ingest reflection, role report, weekly-learnings digest, deck outline, research note) into a beautiful, self-contained HTML infographic — a visual one-pager — with brand-aware theme selection. Use when the user asks to "make an infographic," "visualize this note/report," "turn this into a one-pager/poster," or accepts the post-ingest "generate a visual infographic?" offer.
---

# Infographic Builder

Take a finished document and distill it into a single, share-ready HTML infographic. Not a slide deck, not a dashboard — a *one-page visual argument*: hero thesis, a few hero stats, the narrative arc, the key contrast visualized, the takeaways as cards.

The output is **one self-contained `.html` file** (Tailwind via CDN + Google Fonts, no build step) that opens anywhere and can be rasterized to PNG/PDF for sharing.

## When to use

- A document already exists and is worth a visual summary (ingests, role reports, weekly learnings, research notes, strategy memos).
- The user says "infographic," "visualize this," "one-pager," "poster," or takes the `/ingest` post-step offer.

Do **not** use this to build dashboards (always-on metric views → `aios/data-presentation`) or multi-page decks.

## Process

### 1. Read the source, extract the spine
Read the full document. Pull: the **one-line thesis**, the **2–4 hardest stats/facts**, any **narrative sequence** (steps/timeline), any **tension or dichotomy** (X vs Y), the **takeaways/lessons**, the **best pull-quote**, and the **sources**.

> **Fact discipline (non-negotiable).** Use ONLY facts present in the source. Never invent metrics, dates, impression counts, percentages, or compositional details to make a panel look fuller. If the source doesn't say it, it doesn't go on the infographic. (A blank-but-true panel beats a full-but-fabricated one. Common LLM failure: inserting plausible-sounding metrics like *"~12M impressions in 72 hours"* or invented chemical/material names — *plausible*, *narratively useful*, *not in the source*. Skip the stat or replace with a true qualitative descriptor. See `feedback_no_fabricated_specifics`.) When a number is striking, attribute it the way the source does.

### 2. Map to the Infographic IA

Distill into the seven-section taxonomy. Not every section is mandatory — include only what the content earns. Order is suggestive; what matters is the *hierarchy of attention*.

| # | Section | Purpose | Shape |
|---|---|---|---|
| 1 | **Hero** | Argument in 3 seconds. | 5–9-word title (noun phrase, the thesis) + a one-line subtitle that states what the page proves. |
| 2 | **Stat callouts** (1–3) | The hardest, most arresting facts. | One "before/positive" stat ↔ one "after/negative" stat, paired and source-attributed. If the source has only one hero number, use one card, not two. |
| 3 | **Narrative arc → timeline** | The sequence, in order. | 3–6 steps; each = short label + one-line mechanism + one-line outcome. Step grid or tabbed cascade. Skip if no sequence. |
| 4 | **Contrasting forces → paired cards** | The tension visualized. | Two parallel 3-card stacks (X-layer vs Y-layer, promise vs reality, what-worked vs what-failed). Items must be *semantically paired*, not just thematically. Skip if no real dichotomy. |
| 5 | **Lessons** | What generalizes. | Exactly 3 cards. One-phrase title + 2–3 lines of explanation. The *structural* lessons — not a recap. |
| 6 | **Key Contrast** (the "wow") | The one panel people screenshot. | ONE viz of the single quantitative or structural asymmetry the whole piece pivots on. If the source has no single pivot, *cut this section* — do not fabricate one. |
| 7 | **Quote + sources** | Voice + traceability. | One pull-quote with attribution + source list (URL/path). Every striking number elsewhere on the page traces back here. |

### 3. Select the theme (matching hierarchy)

In priority order — and **always tell the user which theme you picked and why, and offer a one-line override**:

1. **Explicit reference** — the user named a brand, dropped a `design.md`, or pointed at one → use it verbatim.
2. **Brand-first** — if the content maps to a venture (frontmatter `venture:`, wiki-links to a venture, tags), use that venture's design system: `vault/00 - notes/context/ventures/{venture}/design.md`. (Per the AIOS rule: read the design system, never hand-pick fonts/colors.)
3. **Fallback library** — otherwise pick (or combine) the best-matching `DESIGN.md` from **[VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md)** by mood/domain. This is the **default when there is no input or design reference.** Fetch at runtime:
   ```
   https://raw.githubusercontent.com/VoltAgent/awesome-design-md/main/design-md/<slug>/DESIGN.md
   ```
   (`<slug>` is the lowercase brand name; confirm it exists first — slugs vary, e.g. `wired` resolves, some don't). **Combining two is allowed** when it sharpens — pick one as the *typography spine* and the other as the *surface/palette*.
4. **Local alternative**: `anthropic/theme-factory` themes are also available if no web fetch is desired.

**Mood → brand starting points** (suggestive, not authoritative — read the actual DESIGN.md to confirm):

| Content tone / domain | Try first | Why |
|---|---|---|
| Investigative, editorial, journalism | `wired` | Print-magazine gravitas. Note: light, not dark. |
| Dark, precise, technical / SaaS | `vercel`, `supabase` (dark variant), `linear` | Modern dark editorial. |
| Warm, trustworthy, AI / research | `claude`, `cohere`, `mistral` | Approachable; Anthropic-adjacent. |
| Fintech, money, identity | `stripe`, `coinbase`, `wise` | Restrained, institutional. |
| Consumer playful | `spotify`, `airbnb`, `notion` | Color-forward, friendly. |
| Automotive / luxury / kinetic | `tesla`, `ferrari`, `bmw` | Bold, sculptural. |

### 4. Render

One self-contained HTML file. Tailwind (CDN) + Google Fonts. Apply the chosen design system's **actual tokens** — color palette + roles, typography hierarchy, component stylings, depth/elevation. Write the markup **directly** (do not fill a JS template-string — that leaks `${placeholders}` under pressure). Responsive (mobile → desktop). Light, purposeful interactivity only (a tabbed cascade for a timeline is good; gratuitous motion is not). For visual craft follow `anthropic/frontend-design` + `anthropic/canvas-design`; for which-viz-for-which-data follow `aios/data-presentation`.

**Render checklist:**

- [ ] Self-contained single `.html` (no build step). Tailwind via CDN + Google Fonts.
- [ ] Design tokens applied **from the chosen DESIGN.md, verbatim** — exact hex values, exact font families, exact weights, exact spacing scale. No drift.
- [ ] Markup generated **directly** — no JS template-string fill.
- [ ] **Dark/light toggle, unless explicitly out of scope.** Architecture: CSS custom properties for surface/text tokens (`:root` = one mode, `[data-theme="..."]` = the other). Brand colors (primary, accent) stay constant — they're identity. Tailwind colors point at the vars (`rgb(var(--c-surface) / <alpha-value>)`) so existing classes adapt without markup churn. Include a header toggle button + a tiny inline FOUC-prevention script in `<head>` that reads `localStorage` + `prefers-color-scheme` *before* render. Default to whichever mode the chosen DESIGN.md leans toward; let the user flip. ~30 lines of CSS + 15 of JS — not overweight.
- [ ] Responsive: mobile (single column) → tablet → desktop (max-w-7xl). Verify breakpoints.
- [ ] Selection color, scrollbar styling, focus rings — small details that make it feel finished.
- [ ] Light interactivity only when it earns its place.
- [ ] All facts traceable to the source. Sources section at the bottom with URLs/paths.
- [ ] No `${placeholders}` in output. Grep for `$` before declaring it done.
- [ ] **External scripts: Subresource Integrity (SRI).** For shareable / embedded / hosted use, every `<script src="https://...">` and CDN `<link href="https://...">` MUST carry `integrity="sha384-…"` + `crossorigin="anonymous"` against a *pinned* version (jsdelivr/unpkg with an exact version + hash). For **Tailwind Play CDN** (`cdn.tailwindcss.com`): no stable hash exists by design (JIT-compiled), and Tailwind itself states it is **not for production** — acceptable only for local preview artifacts the user opens from disk. For anything hosted/embedded/attached, swap Tailwind Play CDN for either (a) a pinned `tailwindcss@X.Y.Z` build from jsdelivr with SRI, or (b) inline the compiled CSS. Default the local-preview build to Play CDN with a comment noting the production swap; flip the moment the artifact leaves `file://`.

### 5. Output + optional export

Save the `.html` to the location the caller specifies. **Default path + naming:**
```
03 - export/infographics/{YYYY-MM-DD}-{slug}.html
```
- `{YYYY-MM-DD}` = the *render* date (not the source-doc date), so a re-render lands as a new file rather than silently overwriting.
- `{slug}` = lowercase-kebab-case derived from the source filename or the one-line thesis (strip dates, articles, punctuation; max ~6 words).
- Mirrors the vault's date-prefixed convention used in `reflections/ingests/` and other dated artifacts.

Offer optional exports:
- **PNG** — Chrome headless `--screenshot` per the rasterize recipe (native viewport + `--force-device-scale-factor=2`).
- **PDF** — `mcp__pdf-generator__html_to_pdf`.

Then surface the file to the user (e.g. `SendUserFile`).

## Composition

This skill orchestrates existing ones — it doesn't reinvent them:
- `anthropic/frontend-design` + `anthropic/canvas-design` — visual execution quality.
- `aios/data-presentation` — choosing the right viz for the key contrast.
- `anthropic/theme-factory` — local theme option (alternative to the awesome-design-md fetch).

## Anti-patterns

- ❌ Fabricating data to fill panels. ← the cardinal sin.
- ❌ A wall of text. An infographic is a *visual hierarchy*; if a panel needs a paragraph, cut it to a stat + a clause.
- ❌ Generic AI-gradient soup. Commit to one design system's real tokens.
- ❌ Hand-picking fonts/colors when a brand `design.md` exists. Read it first.
- ❌ Template-string fills that leak `${...}`. Generate markup directly.
- ❌ Forcing a Key Contrast viz when the source has no single pivot. Cut the section.

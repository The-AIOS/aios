# Sovra PDF Style Reference

When generating a new Sovra-branded PDF, follow these rules.

## Method

1. Start from `base.html` — it has all the CSS inline
2. Build content inside `<div class="page">` containers (one per A4 page)
3. Open in browser, Cmd+P, save as PDF
4. Or use `to_pdf.py` for programmatic conversion

## Page Model

- A4 (210mm x 297mm), zero margin on `@page`, padding on `.page`
- Default padding: `16mm 22mm 14mm 22mm`
- Footer is `position: absolute; bottom: 10mm` — always sits at page bottom
- `overflow: hidden` on `.page` — content that overflows is clipped, not wrapped

## Fonts

| Role | Font | Weight | Where |
|------|------|--------|-------|
| Headlines, labels, metrics | Plus Jakarta Sans | 700–800 | h1, h2, h3, .t-value, .col-price |
| Body text, descriptions | Figtree | 400–600 | body, p, td, .desc |
| Both load from Google Fonts via @import in the `<style>` block |

## Colors

| Token | Hex | Usage |
|-------|-----|-------|
| Primary | `#0099ff` | Links, taglines, phase numbers, accent text |
| Status teal | `#0ea5e9` | Table status labels (INCLUIDO, OPCIONAL) — NOT primary blue |
| Dark bg | `#0a0915` | .traction-bar, .total-bar, .cta-bar |
| Text primary | `#0a0915` | Headlines, .col-name |
| Text body | `#374151` | Body text, descriptions, table cells |
| Text muted | `#9ca3af` | Footnotes, .col-muted |
| Border | `#e5e7eb` | Dividers, card borders |
| Surface | `#f8fafc` | Card backgrounds |
| SovraGov | `#3b82f6` | Blue product accent |
| SovraID | `#22c55e` | Green product accent |
| SovraWallet | `#a855f7` | Purple product accent |
| SovraChain | `#f97316` | Orange product accent |

## Available Components

### Layout
- `.page` — A4 page container
- `.hero` — Logo + title + tagline
- `.traction-bar` > `.traction-item` — Dark stats bar
- `.divider` — Gradient line (blue→purple→orange→green)
- `.divider-thin` — 1px gray line
- `.footer` — Absolute-positioned page footer

### Content
- `.info-box` — Bordered box with left accent
- `.callout` — Orange-accented callout
- `.card` — Simple bordered card
- `.card-accent` — Card with colored left border (`.blue`, `.green`, `.purple`, `.orange`)
- `.metric-card` — Centered big number + label

### Data
- `table` — Clean pricing/data table
- `.total-bar` — Dark summary with big price
- `.phases` > `.phase` — Horizontal timeline cards

### Comparison
- `.compare-card` — Side-by-side red/green response card
- `.ps-col.problem` / `.ps-col.solution` — Problem/solution columns

### CTA
- `.cta-bar` — Dark CTA (or `.cta-bar.blue` for blue variant)

### Grids
- `.grid-2`, `.grid-3`, `.grid-4` — CSS grid layouts

## Logo

Use inline SVG (copy from any existing template in `~/sovra/web-site/public/sales-templates/`).
The logo SVG includes a gradient background (`#0099ff` → `#2060df`) with white paths.

## Key Design Principles

1. **Dense but not cramped** — Use `pt` units. Body is 8.5–10pt. Leave 6–8pt between sections.
2. **One dark bar per page, max** — The traction/stats bar at top is pitch dark (`#0a0915`). Everything else should use lighter treatments.
3. **Visual weight hierarchy** — Stats bar (dark) > Total bar (dark) > CTA (light surface) > Cards (lightest). Don't stack multiple dark bars — it makes the page feel heavy.
4. **CTA bars are light by default** — Use `background: #f0f1f3` with dark text and blue link. Reserve `.cta-bar` dark style for special emphasis only.
5. **Total bar can be dark** — It's a summary element, dark works. But if the stats bar is already dark on the same page, consider using a bordered style instead.
6. **Gradient divider = section break** — Use sparingly (1–2 per page). The gradient `(#0099ff → #8b5cf6 → #f97316 → #22c55e)` is a strong visual signal.
7. **Text colors vary by context** — Headlines: `#0a0915`. Body paragraphs: `#374151`. Info boxes and featured text: `#1a1a2e` (darker than body for emphasis). Footnotes: `#9ca3af`.
8. **Plus Jakarta Sans at weight 800** for metrics/numbers — gives them visual punch.
9. **Cards use #f8fafc background** with `1px solid #e5e7eb` border.
10. **Footer**: Use `.footer` (flows with content) when page is full. Use `.footer-absolute` (pinned to bottom) only when content is short and you want it anchored. Never use absolute footer on content-heavy pages — it will overlap.
11. **Color variation creates rhythm** — Alternate between dark, white, light gray, and bordered sections. Never put two same-colored blocks adjacent.

## Creating New Components

Follow the existing patterns:
- Use `font-family: 'Plus Jakarta Sans'` for any new headings/labels/metrics
- Use `border-radius: 8px` for containers
- Use the color tokens above, not arbitrary colors
- Keep font sizes in the 6.5pt–12pt range (matching existing scale)
- Add new CSS classes inside the `<style>` block — everything stays self-contained

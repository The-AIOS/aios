---
tags:
  - context
  - ventures
  - index
  - MOC
created: '2026-03-02'
updated: '2026-04-28'
type: index
---
# Venture Deep Dives — Index

> Detailed reference material for venture strategy, product, and market work. Each subfolder holds deep-dive documents for one venture. These complement the high-level [[about_business|declared/about_business]] with depth.

---

## Convention

Each venture gets its own subfolder (`ventures/{venture-name}/`). Inside, use one file per domain:

| Standard file | What it covers |
|---------------|---------------|
| `about_venture.md` | **Required.** Venture overview — one-liner, category, thesis, products, traction. Read by `about_business.md` and `/company-sync`. |
| `{venture}_gtm.md` | Go-to-market strategy — channels, motions, sequencing |
| `{venture}_market_{year}.md` | Market intelligence — landscape, competitors, trends |
| `{venture}_personas.md` | Buyer personas and ICPs — motivations, objections, journeys |
| `{venture}_positioning.md` | Positioning and messaging — category, differentiation, narratives |
| `{venture}_pricing.md` | Pricing and business model — tiers, packaging, revenue |
| `{venture}_primitives.md` | Technical primitives — core architecture, key abstractions |

Not every venture needs all six. Start with what you have and add files as the thinking deepens.

A venture subfolder may also contain a `README.md` with onboarding context, a `branding-guidelines.md` for visual identity, or a `{venture}-design.md` for the brand design system (colors, typography, components, render targets).

---

## Current Contents

*No ventures defined yet. Add your first venture by following the steps below.*

*As ventures are created, list them here with a file table per venture. Each gets its own section.*

---

## Adding a New Venture

1. Create a subfolder: `ventures/{venture-name}/`
2. Create `about_venture.md` from [[about_venture-template]] — this is the required overview file
3. Add deep-dive files using the naming convention: `{venture}_{domain}.md`
4. Update this index with a new section listing the files
5. Update `declared/about_business.md` with a summary entry for the new venture
6. Optionally add a `README.md` inside the subfolder for onboarding context

---

## When to Use These

- **Strategy sessions**: positioning, GTM, pricing decisions
- **Content creation**: decks, one-pagers, website copy, investor materials
- **Product work**: architecture decisions, SDK design, developer docs
- **Sales enablement**: persona-specific messaging, objection handling

See [[about_business|declared/about_business]] for the canonical business overview.
See [[business|observed/business]] for observed strategic dynamics.

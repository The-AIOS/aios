---
name: pdf-generator
description: Sovra-branded HTML templates and PDF generation from markdown content
type: context
version: 1.0.0
author: Sovra
tags: [pdf, templates, branding, sales, html]
provides:
  scripts: [to_pdf.py]
  templates: [base.html, sales-templates/*]
  reference-docs: [STYLE-REFERENCE.md]
triggers:
  - pdf
  - branded document
  - sales template
  - html template
  - sovra branding
  - product sheet
  - case study
  - industry brief
register-in-marketplace: false
---

# pdf-generator

Self-contained HTML templates for Sovra-branded documents. Same approach used in `sovrahq/web-site` (`/admin/sales-ondemand`).

## How to use

1. **Read `STYLE-REFERENCE.md`** for design rules (colors, fonts, components)
2. **Scan `sales-templates/`** to pick the best layout for the content type
3. **Generate styled HTML** using `base.html` components and the chosen template as reference
4. **Save output** to `vault/03 - export/{document-name}.html`
5. **Convert to PDF** via browser print (Cmd+P) or `python to_pdf.py`

## What's inside

| Path | Purpose |
|------|---------|
| `base.html` | Master template — all CSS inline, A4 page model, full component library |
| `STYLE-REFERENCE.md` | Design rules for Claude — colors, fonts, spacing, component docs |
| `sales-templates/` | 19 reference templates Claude uses to pick layouts |
| `to_pdf.py` | Optional CLI converter (WeasyPrint) |
| `assets/fonts/` | Offline font files (Figtree, Plus Jakarta Sans, JetBrains Mono) |
| `assets/logos/` | Sovra logo PNG + wordmark SVG |

## Template selection guide

| Content type | Best template(s) |
|-------------|-------------------|
| Product overview | `*-product-sheet.html` (one per product) |
| Technical architecture | `*-architecture.html` (one per product) |
| Sector/industry brief | `*-industry-brief.html` |
| Sales proposal | `sovra-sales-template.html` |
| Case study | `nuevo-leon-case-study.html` |
| Competitive comparison | `competitive-battlecards.html` |
| ROI analysis | `roi-model-government.html` |
| Implementation timeline | `implementation-phases.html` |
| Objection handling | `objection-handler.html` |

See `README.md` for full documentation.

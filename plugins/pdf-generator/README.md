# Sovra PDF Generator

Self-contained HTML templates for Sovra-branded documents.
Same approach used in `sovrahq/web-site` (`/admin/sales-ondemand`).

## Quick Start — Generate a PDF from Markdown

The fastest way to create a branded PDF from any markdown content:

### 1. Prepare your markdown
Place your source `.md` file in the vault assets folder:
```
vault/03 - assets/your-document.md
```

### 2. Ask Claude to generate the HTML
Open a Claude Code session at the vault root and run:
```
Based on the sales-templates in plugins/pdf-generator/sales-templates/,
choose the best template to present this markdown:
'vault/03 - assets/your-document.md'

The audience is [describe who will read this and what they expect].
```

Claude will:
- Read `STYLE-REFERENCE.md` for design rules
- Scan the 19 sales templates to pick the best layout for your content
- Generate a styled HTML file using `base.html` components
- Save it to `vault/04 - export/your-document.html`

### 3. Convert to PDF

**Option A — Browser (recommended)**
```
Open the HTML file in Chrome/Safari → Cmd+P → Save as PDF
```

**Option B — Programmatic (WeasyPrint)**
```bash
cd plugins/pdf-generator
python3 -m venv .venv && source .venv/bin/activate
brew install pango  # system dep (one-time)
pip install -r requirements.txt
python to_pdf.py ../../vault/04\ -\ export/your-document.html output.pdf
```

## How It Works

1. `base.html` has all CSS inline — fonts, colors, components, print rules
2. `STYLE-REFERENCE.md` documents every component, color token, and design principle
3. `sales-templates/` contains 19 real examples that Claude uses as layout references
4. Claude picks the closest template, adapts the layout, and fills it with your content
5. The output is a single self-contained HTML file — no external dependencies

## Structure

```
pdf-generator/
├── base.html              ← Base template. All CSS inline, A4 page model
├── STYLE-REFERENCE.md     ← Design rules for Claude (colors, fonts, components)
├── to_pdf.py              ← HTML → PDF converter (optional, uses WeasyPrint)
├── requirements.txt       ← Python deps (only needed for to_pdf.py)
├── sales-templates/       ← 19 reference templates Claude uses to pick layouts
│   ├── sovragov-product-sheet.html
│   ├── enterprise-industry-brief.html
│   ├── implementation-phases.html
│   ├── roi-model-government.html
│   └── ... (15 more)
└── assets/
    ├── fonts/             ← Offline font files (for to_pdf.py)
    └── logos/             ← Logo files (for to_pdf.py)
```

## Sales Templates Reference

These are the 19 templates Claude chooses from based on your content type:

| Template | Best for |
|----------|----------|
| `sovra-sales-template` | General sales proposals |
| `sovragov-product-sheet` | Product one-pagers (SovraGov) |
| `sovraid-product-sheet` | Product one-pagers (SovraID) |
| `sovrawallet-product-sheet` | Product one-pagers (SovraWallet) |
| `sovrachain-product-sheet` | Product one-pagers (SovraChain) |
| `sovragov-architecture` | Technical architecture diagrams |
| `sovraid-architecture` | Technical architecture diagrams |
| `sovrawallet-architecture` | Technical architecture diagrams |
| `sovrachain-architecture` | Technical architecture diagrams |
| `sovra-rag-product-sheet` | RAG product overview |
| `sovra-rag-architecture` | RAG technical architecture |
| `enterprise-industry-brief` | Enterprise sector briefs |
| `finance-industry-brief` | Financial sector briefs |
| `government-industry-brief` | Government sector briefs |
| `implementation-phases` | Project timelines and phases |
| `competitive-battlecards` | Competitive comparisons |
| `objection-handler` | Sales objection responses |
| `roi-model-government` | ROI calculations |
| `nuevo-leon-case-study` | Case studies |

## Tips

- **Be specific about the audience** — Claude picks a different layout for an IT team than for executives
- **Long documents work** — Claude will paginate across multiple A4 pages automatically
- **Iterate** — If the first version isn't right, ask Claude to adjust specific sections
- **Output goes to `vault/04 - export/`** — all generated HTML lives there

## Relationship to web-site repo

The templates in `sovrahq/web-site/public/sales-templates/` are the originals.
The `sales-templates/` folder here is a local copy for offline use.
This plugin adds:
- `base.html` — a clean starting point with all components
- `STYLE-REFERENCE.md` — rules for generating new documents that match
- `to_pdf.py` — offline PDF conversion without a browser

## Design source

All styles derived from `branding-guidelines.md` and the existing
sales templates in `sovrahq/web-site`.

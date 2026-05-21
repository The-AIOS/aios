# PDF Generator MCP

Bundled MCP that converts markdown or HTML to a branded PDF via the standard vault pipeline: pandoc (md → HTML) → Chrome headless (HTML → PDF). Matches what `/weekly-learnings`, `/role-report`, and `/learned` already do, but exposed as a reusable tool.

## What it does

- `markdown_to_pdf(markdown, output_path?, theme?)` — converts markdown to PDF, saves to disk, returns path.
- `html_to_pdf(html, output_path?)` — converts HTML directly to PDF (useful when you already have a styled template).

Output defaults to `~/obsidian/vault/04 - export/generated/{timestamp}.pdf`.

## Example usage

Ask Claude naturally — it picks the right tool:

```
"Turn today's daily note into a branded PDF I can share"
"Convert this markdown manifesto to PDF and drop it in 04 - export/"
"Take this HTML wireframe and render it as a printable PDF"
"Export the last three reflections as a single PDF titled 'Field Notes'"
"Generate a PDF from this audit markdown and save it with today's date"
"Merge these three briefs into one PDF for the meeting"
```

## Setup

```bash
# Installed via mcps/setup.sh — or manually:
cd mcps/pdf-generator-mcp
python3 -m venv .venv
.venv/bin/pip install mcp

# Requires: pandoc + Google Chrome (both typically already installed on dev machines)
which pandoc || brew install pandoc
ls "/Applications/Google Chrome.app" || echo "Install Google Chrome from https://google.com/chrome"
```

## Auth

None. Local binaries only.

## Register with Claude Code

```bash
claude mcp add pdf-generator -- ~/obsidian/mcps/pdf-generator-mcp/.venv/bin/python ~/obsidian/mcps/pdf-generator-mcp/server.py
```

Tools appear as `mcp__pdf-generator__markdown_to_pdf` and `mcp__pdf-generator__html_to_pdf`.

## Why this exists

The PDF pipeline was inline in several vault commands. Extracting it to a reusable MCP means: future commands can call it, agents can generate PDFs on demand, and teammates get the same branded output regardless of which command they're running.

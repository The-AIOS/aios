# NotebookLM MCP

Unofficial Python API for Google NotebookLM. Full programmatic access including features the web UI doesn't expose.

## What it does

- Create notebooks, add sources (URLs, Drive files, text, research queries)
- Generate artifacts: audio overviews, podcasts, flashcards, quizzes, mind maps, slide decks, reports, infographics, videos
- Download all artifact types in multiple formats
- Chat with notebooks (ask questions against your sources)
- Share and collaborate

## Install

```bash
cd mcps/notebooklm-mcp
python3 -m venv .venv
source .venv/bin/activate
pip install notebooklm-py
```

## Setup

```bash
source mcps/notebooklm-mcp/.venv/bin/activate
notebooklm login
```

This opens a browser for Google OAuth. After login, the session is cached.

## Usage

### Example usage

Ask Claude naturally — the `/notebooklm` skill picks up the workflow:

```
"Create a NotebookLM podcast about my latest weekly learnings"
"Turn this manifesto into a 10-minute audio overview"
"Generate a deep-research notebook on a given topic and make it a podcast"
"Create an audio overview of these book chapters for my commute"
"Package this design doc + a linked repo as a NotebookLM I can share with my team"
```

### Via the `/notebooklm` skill (auto-installed)

```
/notebooklm create a podcast about my latest weekly learnings
```

### Or via CLI

```bash
notebooklm create "My Research"
notebooklm source add-research "latest AI trends in digital identity"
notebooklm generate audio
notebooklm download audio ~/Downloads/podcast.wav
```

## In the AI-OS

Used by:
- **Gift/Demo workflow** — Gemini Deep Research + NotebookLM audio package as an outreach gift in a consulting/sales workflow
- **Content pipeline** — turn vault insights into podcast episodes
- **Study workflow** — generate audio overviews of book chapters for commute listening

## Source

[teng-lin/notebooklm-py](https://github.com/teng-lin/notebooklm-py) — 8K+ stars

# NotebookLM MCP

Unofficial Python API for Google NotebookLM. Full programmatic access including features the web UI doesn't expose.

## What it does

- Create notebooks, add sources (URLs, Drive files, text, research queries)
- Generate artifacts: audio overviews, podcasts, flashcards, quizzes, mind maps, slide decks, reports, infographics, videos
- Download all artifact types in multiple formats
- Chat with notebooks (ask questions against your sources)
- Share and collaborate

## Not a connector — there is nothing to register

This folder lives under `mcps/` by history, but **it contains no MCP server**: no server code, no
`FastMCP`, no stdio transport. Verified 2026-08-27 while auditing all bundled folders for the connector
manifest.

Capability reaches you through the **bundled `notebooklm` skill** (`setup.sh` runs
`notebooklm skill install`), plus the CLI documented below. `connector.json` here carries
`registers: false`, which tells the AIOS App two things: never list this as a connector, and **never
treat the absent registration as drift.**

An earlier audit recorded this folder as *"bundled but registered nowhere, no register command in the
README"* and proposed authoring one. That would have invented a server that does not exist — the App
would then register a command that fails at first use, which is precisely the failure class this whole
effort removes. The honest fix is this section.

## Install

> ⚠️ **Requires Python 3.10+.** `notebooklm-py` uses PEP 604 syntax (`str | None`), so building the
> venv against a system `python3` older than 3.10 — **macOS still ships 3.9.6** — leaves you with a
> venv that *looks* installed and a CLI that crashes on import
> (`TypeError: unsupported operand type(s) for |` in `cli/helpers.py`).
>
> The failure is worse than a clean crash: **pip resolves backwards** until it finds a release
> compatible with the old interpreter and silently pins `notebooklm-py==0.1.1`, many minors behind
> current. Nothing errors, so the version gap is invisible until a command that needs a newer API
> quietly does the wrong thing. Use `uv`, which fetches its own interpreter:

```bash
cd mcps/notebooklm-mcp
uv venv --python 3.12 .venv
VIRTUAL_ENV=.venv uv pip install 'notebooklm-py[browser]'
./.venv/bin/notebooklm --version
```

The **`[browser]`** extra (playwright) is **not optional**: without it `notebooklm login` cannot open
a browser and `doctor` reports *Headless Reauth: unavailable*.

> 💡 **A venv cannot be renamed** — its shebangs carry absolute paths. If you built it at the wrong
> path, recreate it at the final one; moving it produces a venv whose entry points all fail.

## Setup

```bash
./.venv/bin/notebooklm doctor --fix   # creates ~/.notebooklm/profiles/default
./.venv/bin/notebooklm login          # Google OAuth — run by the operator, not an agent
./.venv/bin/notebooklm doctor         # verify: Auth ✓
```

`doctor` is the canonical diagnostic — it reports profile, migration, auth and headless-reauth
state in one table, and `doctor --fix` creates the profile directory a first `login` expects.

**`login` is run by a person, not by a Claude session:** it opens Google's OAuth flow, and an agent
does not enter credentials. Afterwards the session is cached in
`~/.notebooklm/profiles/<profile>/storage_state.json`.

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

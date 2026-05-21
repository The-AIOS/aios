---
name: ingest
description: Process a source into the vault — extract, file, cross-reference, log
version: 1.0.0
allowed-tools:
  Read, Write, Edit, Bash, Grep, Glob, mcp__obsidian__read_note, mcp__obsidian__write_note, mcp__obsidian__patch_note, mcp__obsidian__search_notes, mcp__obsidian__list_directory, WebFetch, WebSearch
---

# /ingest — Process a Source Into the Vault

You are ingesting a new source into the vault. The source can be anything: an article, a PDF, a video transcript, a voice memo, meeting notes, a report, a Slack thread, a research paper, or a URL. Your job: read it, extract the key information, and integrate it into the existing vault — updating project notes, context files, reflections, and cross-references.

Read `USER.md` → `### /ingest` for command personalizations.

## The Principle

> "Instead of just retrieving from raw documents at query time, the LLM incrementally builds and maintains a persistent wiki. When you add a new source, the LLM doesn't just index it for later retrieval. It reads it, extracts the key information, and integrates it into the existing wiki — updating entity pages, revising topic summaries, noting where new data contradicts old claims." — Karpathy, LLM Wiki

A single source might touch 5-15 vault files. That's the point — the bookkeeping is the LLM's job.

## Steps

### 1. Receive the source

The user provides one of:
- A file path (any format — PDF, Word, Excel, PowerPoint, images, audio, EPUB, CSV, JSON, XML, ZIP)
- A URL (article, video, repo, YouTube)
- Pasted text (Slack thread, meeting notes, email)
- A reference ("ingest Karpathy's LLM Wiki post")

**File conversion (MarkItDown):**
For non-markdown files, convert first using the MarkItDown wrapper:
```bash
python3 ~/obsidian/hooks/markitdown-convert.py <input_file> /tmp/ingest-source.md
```
Then read the converted markdown. Supported formats: PDF, Word (.docx), Excel (.xlsx), PowerPoint (.pptx), images (with OCR), audio (with transcription), HTML, CSV, JSON, XML, ZIP, YouTube URLs, EPUB.

**Routing by source type:**
- URL → `WebFetch` to retrieve content
- PDF/Word/Excel/PowerPoint/EPUB → MarkItDown conversion → read markdown
- Image → MarkItDown (OCR + EXIF) → read markdown
- Audio → MarkItDown (transcription) → read markdown
- YouTube URL → MarkItDown (transcript extraction) → read markdown
- Markdown/text → read directly
- Pasted text → process directly

**Standalone MarkItDown usage (outside /ingest):**
```bash
# Convert any file to markdown
python3 hooks/markitdown-convert.py input.pdf                    # prints to stdout
python3 hooks/markitdown-convert.py input.pdf output.md          # saves to file
python3 hooks/markitdown-convert.py presentation.pptx slides.md  # PowerPoint → markdown
python3 hooks/markitdown-convert.py recording.mp3 transcript.md  # audio → transcript
```

### 2. Read and extract

Read the full source. Extract:
- **Key claims** — what does this source assert?
- **Entities** — people, companies, products, concepts mentioned
- **Actions** — anything the user should do, consider, or follow up on
- **Connections** — which existing vault projects, ventures, or context files relate?
- **Contradictions** — does anything here conflict with existing vault knowledge?

### 3. Discuss with the user

Before filing, present a brief summary:

```
## Ingest: {source title}

**Key takeaways:**
1. {takeaway}
2. {takeaway}
3. {takeaway}

**Vault connections I see:**
- [[project-name]] — {how it connects}
- [[context-file]] — {what to update}

**Contradictions flagged:**
- {existing claim} vs {new claim from source} — needs resolution

**Where I'd file this:**
- Summary → `00 - notes/reflections/ingests/{slug}.md`
- Action items → [[project-name]] to-dos
- Context update → `context/observed/{file}.md` (if pattern-level)

Proceed? Or redirect?
```

Wait for the user to confirm, redirect, or add context before filing.

### 4. File into the vault

After confirmation:

**a. Write the summary page**
- Default location: `00 - notes/reflections/ingests/{slug}.md` (for knowledge/research metabolized from external sources)
- Alternative: `00 - notes/ideas/{slug}.md` (for half-formed thoughts)
- Alternative: directly into a project note's session notes (for project-specific sources)
- Include frontmatter: `title`, `type: ingest`, `source`, `source-date`, `ingested-by`, `created`, `tags`
- Include a `## Source` section with link/path to the raw source
- Use `[[wiki-links]]` for all vault connections

**b. Update related project notes**
- For each connected project: add relevant to-dos, update session notes, or update status
- Follow the rule: update project note FIRST, then cascade to `_index.md`

**c. Update context files (if warranted)**
- Only update observed context if the source reveals a pattern (2+ sessions of evidence)
- Update `business.md` if it's a strategic insight about a venture
- Update `ecosystem.md` if it changes how ventures connect
- Snapshot before editing (mandatory per CLAUDE.md rules)

**d. Flag contradictions**
- If the source contradicts existing vault content, add a `> ⚠️ Contradiction:` callout in the relevant file
- Don't auto-resolve — flag for the user to decide

**e. Update indexes**
- Add the new reflection/idea to the relevant `_index.md`
- Update the reflections or ideas index

### 5. Log the ingest

Append to today's daily note (if it exists) or note for `/close-day`:

```
### Ingested: {source title}
- Source: {URL/path}
- Filed to: [[reflection-slug]] + {N} project notes updated
- Contradictions: {none / listed}
- Action items: {count} added to project notes
```

## Rules

- **Never modify raw sources.** The source is immutable. The vault pages are the LLM's layer.
- **Always discuss before filing.** Show the user what you extracted and where you'd put it. Don't silently update 15 files.
- **Cross-reference aggressively.** Use `[[wiki-links]]` everywhere. The connections between pages are as valuable as the pages themselves.
- **Flag contradictions, don't resolve them.** The user decides what's current.
- **One source at a time.** Stay involved per source. Batch ingestion is possible but the user should opt into it.
- **Update project notes first, then index.** Source of truth → derived artifact. Always. (Antifragile #12)

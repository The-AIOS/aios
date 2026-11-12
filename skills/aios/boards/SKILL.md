---
name: boards
description: >-
  Build, update and remove a BOARD: a sidebar card in the AIOS App whose content is one static HTML page
  your own tooling writes to ~/.aios/boards/<name>/index.html. Use when the operator asks for a card,
  board, panel, dashboard or status view in the App's sidebar ("put this on my sidebar", "make a board
  for X", "show the queue in the App", "a card with what's waiting on me"), when a session or a scheduled
  job should surface live state there, or when an existing board looks stale, broken or needs to go.
  Covers the contract (folder, board.json, what the locked-down viewer allows and refuses), an atomic
  writer, sizing for the sidebar, and removal. Requires AIOS App 0.15.0 or later; Glass does not show
  boards. NOT for deliverables the operator opens on purpose (those are exports in 03 - export/) and NOT
  for interactive pages (a board never runs scripts).
---

# Boards: a sidebar card you program

A **board** is the sidebar's `custom/` slot. The App lists the folders under `~/.aios/boards/`, shows each one as a card, and knows nothing about what it means. Whatever writes the page owns its content and its freshness.

## The contract

- **One folder per card:** `~/.aios/boards/<name>/index.html`. No folder, no card. A folder without `index.html` is not a board. Folders whose name starts with `.` are ignored. `$AIOS_BOARDS_DIR` moves the root (for tests).
- **Optional `board.json`** beside it: `{ "title": "Inbox queue", "valid_for": 600 }`.
  - `title` replaces the folder name on the card.
  - `valid_for` is in **seconds** (default `3600`). Unknown keys are ignored.
  - `icon` (App 0.15.1+) picks the card header's icon from the App's own icon set: `{ "title": "Inbox queue", "valid_for": 600, "icon": "inbox" }`. Names that suit boards: `chart`, `inbox`, `calendar`, `users`, `rocket`, `megaphone`, `shield`, `brain`, `note`, `building`, `star`, `stack`. The full list is in the App's [`docs/rfcs/sidebar-boards.md`](https://github.com/The-AIOS/aios-app/blob/main/docs/rfcs/sidebar-boards.md). It is a name made of letters only, never a path, a URL or SVG. An unknown name, a wrong type or no key keeps the default board glyph, with no error line, and an App older than 0.15.1 ignores the key, so a board using it never breaks.
  - A malformed `board.json` shows an error line on the card; the board still renders. Fix the file rather than delete it.
- **Static only.** The viewer is locked down, and each rule below is enforced in more than one place, so do not try to work around it:
  - **No scripts.** `<script>`, inline handlers and `javascript:` never run.
  - **No network.** Nothing from `http(s):`, `file://` or another board: no web fonts, CDN stylesheets, remote images or analytics.
  - **Only these files load, from the board's own folder:** `.html`, `.css`, images (`.png .jpg .jpeg .gif .webp .avif .svg .ico`) and fonts (`.woff .woff2 .ttf .otf`), up to **8 MB each**. Dot-files, symlinks that point outside the folder, `board.json` itself and every other type are refused.
  - **No navigation, popups or forms.** Links do nothing; a board is something to read, not to click through.
- **Refresh = rewrite the file.** The App checks `index.html`'s modification time every 15 seconds and reloads the card only when it changed.
- **Stale = the writer stopped.** Once `index.html` is older than `valid_for`, the title dims and the card reads *no update since …*. Set `valid_for` a little above your writer's interval, so one late run does not flag it.
- **The App never writes into `~/.aios/boards/`**, and `/aios:update` never touches it. The folder is yours.

## Make one

1. **Pick a name** (kebab-case: `status`, `inbox-queue`). It becomes the folder and, without a `title`, the card's heading.
2. **Render the page from data, atomically.** Write to a temporary file in the same folder, then rename it over `index.html`, so the App never reads a half-written page:

   ```python
   #!/usr/bin/env python3
   """Render a board: a static status page for the AIOS App sidebar."""
   import html, json, os, tempfile, time
   from pathlib import Path

   root = Path(os.environ.get("AIOS_BOARDS_DIR", Path.home() / ".aios" / "boards"))
   board = root / "status"
   board.mkdir(parents=True, exist_ok=True)

   items = [("Deploy", "green"), ("Inbox", "3 waiting on you")]  # your data source goes here
   rows = "".join(f"<li><b>{html.escape(k)}</b> {html.escape(v)}</li>" for k, v in items)
   page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
   :root {{ color-scheme: light dark; }}
   body {{ margin: 0; padding: 10px 12px; font: 13px/1.45 -apple-system, "Segoe UI", sans-serif; }}
   ul {{ margin: 0; padding-left: 16px; }} li {{ margin: 2px 0; }}
   .meta {{ opacity: .6; font-size: 11px; margin-top: 6px; }}
   </style></head><body><ul>{rows}</ul>
   <div class="meta">updated {time.strftime("%H:%M")}</div></body></html>"""

   fd, tmp = tempfile.mkstemp(dir=board, prefix=".tmp-", suffix=".html")   # dot-file: never served
   with os.fdopen(fd, "w", encoding="utf-8") as f:
       f.write(page)
   os.replace(tmp, board / "index.html")                                    # atomic on one filesystem
   (board / "board.json").write_text(json.dumps({"title": "Status", "valid_for": 600, "icon": "chart"}))
   ```

   Escape every value that comes from data (`html.escape`). A board is rendered as HTML, and text pulled from an issue, an email or a file can carry markup.
3. **Keep it running.** Call the writer from whatever already runs: a hook, a scheduled job, the end of a `/close-session`. A board that nothing rewrites goes stale, which is the honest signal.

## Design for the sidebar

- **About 280 px wide**, 220 px tall by default (the operator can drag it taller). Design for a narrow column: one idea per line, short labels, no tables wider than the card, no horizontal scroll.
- **Both themes.** `color-scheme: light dark` plus system colors, or colors that read on both a light and a dark panel. Never hard-code a white background.
- **Small.** A few KB of inline CSS is plenty. Use system fonts; a bundled font file must sit in the folder.
- **Say when.** Print the update time on the card itself, so the operator can tell a fresh board from a quiet one without relying on the stale dim alone.
- **Nothing secret.** A board sits on screen all day, including in screenshots and screen shares.

## Update, rename, remove

- **Update:** run the writer again. Nothing else is needed.
- **Rename the card:** change `title` in `board.json`. Renaming the folder makes a new card in a new position; the old position is forgotten.
- **Remove:** delete the folder (`rm -rf ~/.aios/boards/<name>`), and stop whatever writes it, or the card comes back on the next run.
- **Hide without deleting:** move the folder under a name that starts with `.`.

## When it does not show

- **No card:** check that `index.html` exists in its own folder directly under the boards root, that the folder name does not start with `.`, and that the App is 0.15.0 or later. Glass has no boards.
- **Blank or unstyled card:** something the page needs was refused. Look for a script, a remote URL, a `file://` path, a file type outside the list above, or a symlink pointing outside the folder.
- **Error line on the card:** `board.json` does not parse, or `title` / `valid_for` has the wrong type.
- **Always dimmed:** the writer stopped, or `valid_for` is shorter than its interval.

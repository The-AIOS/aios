---
tags:
  - vault-commands
  - command
  - on-demand
description: Scaffold a shared Collaboration Space (collab folder + first project) and create a router project note in the personal vault. Substrate-pluggable — any substrate with an active adapter and MCP/CLI on the machine can host a space. Subcommands for add-project, status, dry-run.
allowed-tools: mcp__google-workspace__*, mcp__obsidian__*, Read, Write, WebFetch, Bash(mkdir *), Bash(git *), Bash(gh *)
argument-hint: "optional: --add-project | --status | --dry-run | space name"
---

# /collaborate — Scaffold a Collaboration Space

Create a shared knowledge space with one or more collaborators. Scaffolds a substrate-pluggable folder containing `collaborate.md` (operating protocol), `README.md` (welcome page), and a first collaborative project. Creates a router project note in the personal vault that points to the shared space as source of truth.

## Mental model

The hierarchy:

- **Personal vault** — your individual AIOS (declared / observed / intent / projects-you-own)
- **Collaboration space** — shared OS with a stable group of collaborators (one space per group; many projects inside)
- **Project** — unit of work inside a space (same shape as a project in your personal vault, but shared)

**Space router** = `vault/00 - notes/projects/space-{slug}.md` — a **content-identical mirror** of the substrate's `space-{slug}.md` artifact. Same information, materialized natively per substrate. The local file exists for `/today`, Radar, and wiki-link navigation; the substrate version is canonical.

**Substrate root holds three artifacts:**
- `README.md` — human welcome page (rarely changes)
- `collaborate.md` — operating protocol + **mount instructions** (rarely changes; carries `collaborate-version` marker)
- `space-{slug}.md` — shared metadata: Current State, Active Collaborators, Projects table (updates as projects grow / status changes)

> **Substrate-native artifact types.** All substrates name artifacts with `.md` extension; how they materialize differs per substrate:
> - **Drive:** Google Docs **named `foo.md`** — the `.md` is a visual signal that the Doc is markdown-source-of-truth. Drive treats it as `application/vnd.google-apps.document` regardless of filename; humans browsing Drive see "collaborate.md" / "README.md" / etc. as Doc names. In-browser editing, comments, suggestions all work natively.
> - **GitHub:** `.md` files — git-native, version-controlled.
> - **Local:** `.md` files — Obsidian-native.
>
> Round-tripping through Google Docs (Drive) is **content-identical, not byte-identical** — two collaborators each round-tripping the same Doc produce locally-different bytes for the same semantic content. The "mirror" is semantic, not mechanical.
>
> **Drive round-trip caveats** (pilot finding 2026-05-09 — must inform v8+ adapter design):
> - YAML frontmatter (`---` blocks) does NOT survive the round-trip — Drive interprets `---` as section dividers and breaks the YAML body. **Frontmatter only lives in the local mirror;** the substrate Doc has no frontmatter. Markers like `collaborate-version: 1` are detected by *folder structure* (presence of `collaborate.md` + `space-*.md` + `projects/`), not by frontmatter parse.
> - HTML comments (`<!-- ... -->`) are stripped by Drive — append-to-table marker strategy must use Doc-native primitives (named ranges, structural table position via `inspect_doc_structure`) rather than text markers.
> - Blockquote `>` markers may be lost — use bold + paragraph indentation as substitute when blockquote-style emphasis matters in Drive.
> - Cosmetic: table headers auto-bolded, plain emails/URLs auto-linked. Acceptable.

> **Naming convention:** personal projects are `{slug}.md`; shared-space routers are `space-{slug}.md`. Same conceptual file on substrate AND in vault — local is always `.md` (Obsidian-native); substrate is per-adapter.

> **Zero private sections in the router.** The local file is fully shared content, content-identical to substrate. Want private notes about a shared project? Use existing vault tools: daily notes (tasks, narration), `00 - notes/ideas/` (half-formed thoughts), `00 - notes/reflections/` (longer riffs), or personal observed-context. The router doesn't try to host these — keeps collaborator parity automatic and the vault's shared/private boundary structural.

> *"Code repo vs knowledge repo"* — this command is the knowledge-repo creator. Storage substrate is a per-space decision; the knowledge primitives (markdown + folder navigation) are portable across substrates.

## Natural-language triggers

Claude routes to `/collaborate` when the user says things like:

| Phrase | Subcommand |
|---|---|
| *"I want to collaborate with X on Y"* | `/collaborate` (default flow → new-space) |
| *"Let's co-create with X..."* (casual synonym) | `/collaborate` (default flow → new-space) |
| *"Spin up a collab / shared space / collaboration with X"* | `/collaborate` (default flow → new-space) |
| *"Mount the X collab"* / *"mount the {space} collaboration space"* | `/collaborate` (default flow → mount-existing) |
| *"Add a project to my collab/space with X"* / *"new collaborative project in {space}"* | `/collaborate --add-project` |
| *"What's the status of my collaborations?"* / *"are my spaces synced?"* | `/collaborate --status` |
| *"What would happen if I collaborated with X..."* (preview intent) | `/collaborate --dry-run` |

`co-create` and `co-creation` are recognized as casual synonyms — they map to the same command. The canonical verb is `collaborate.md`.

**Don't auto-fire on ambient mentions.** *"I was collaborating with X yesterday"* is narration, not a request to scaffold. Trigger only on first-person intent statements (*"I want to..."*, *"let's..."*, *"spin up..."*).

## Subcommands

| Invocation | What it does |
|---|---|
| `/collaborate` | Default interactive flow — create new space OR mount existing |
| `/collaborate --add-project` | Add a new collaborative project to an already-mounted space (skips name/collaborators/substrate scaffold) |
| `/collaborate --status` | Read-only: list mounted spaces, substrates, last-sync, drift indicators |
| `/collaborate --dry-run` | Preview-only — outputs the scaffold plan and exits without writing. Combinable with `--add-project` |

## Steps (default flow)

> **Before executing:** Read `USER.md` → `## Sources` for substrate preferences, `## Command personalizations` → `### /collaborate` for any user overrides, and `INTENT.md` for autonomy levels (especially if substrate access changes are involved).
>
> **Subcommand routing:** if invoked with `--add-project` → jump to § Subcommand: --add-project. If `--status` → jump to § Subcommand: --status. If `--dry-run` → continue with default flow but skip all write operations in step 4 onward (output the scaffold plan and exit).

### 1. Read user preferences + check active substrates

- Read `USER.md` → `### /collaborate` section (if it exists).
- Detect available substrates at runtime by checking for active MCPs / CLIs / local filesystem access. Cross-reference the result against the registered adapters in § Substrate adapters below — only show substrates that have BOTH a registered adapter AND an active MCP/CLI on this machine.
- **Zero active substrates:** if no adapter has an active MCP/CLI, surface clearly:
  > *"No substrate adapters are active on this machine. To create a Collaboration Space, install at least one substrate's MCP/CLI. See `mcps/_index.md` for bundled options or `mcps/setup.sh` for first-run install. Cancelling /collaborate."*
  Exit cleanly. Don't proceed with an empty menu.
- **Recommendation rule:** for knowledge spaces, prefer collaboration-native substrates (auto-sync, comment-friendly, non-coder-readable) over code-native ones (PR-governed, version-controlled). The recommendation message should reflect what's actually available — don't hardcode specific substrate names in the recommendation.

### 2. Gather inputs (interactive — one question at a time)

**First question (branch):** *"Are we creating a new Collaboration Space, or mounting an existing one?"*

- **(a) Create a new space** → continue with the New-space flow below.
- **(b) Mount an existing space** → jump to the Mount-existing flow below.

#### New-space flow

1. **"What's the name for this Collaboration Space?"** — pre-suggest an adjective-animal handle (e.g. `amber-otter`, `bold-falcon`, `wise-elephant`) to remove naming friction. Show the suggestion, let the user accept or override. The space name is a memorable handle, not a meaningful label — the description (next question) carries the substantive purpose. **No personal-name patterns in the suggestion** — don't suggest `{name1}-{name2}` even if collaborators are known. The adjective-animal pair is identity-neutral by design. User can still override with anything (hyphenated first-names, topic anchor, project-family) — it's their handle.

2. **Existing-space check (early).** Search each active substrate (from step 1) where cross-substrate enumeration is possible (Drive: search whole user's Drive; GitHub: enumerate all repos the user has access to via `gh repo list`). Local substrate is skipped — no canonical default path to scan; local-side collisions are caught at step 4.1 if the user picks local substrate. If any match, surface all matches across substrates and ask: *"A '{space}' already exists at {URL(s)}. Add a new collaborative project inside it (recommended — compound-value path), or pick a different name for a separate space?"*
   - If user picks "add to existing" → route to `--add-project` subcommand with this space pre-selected. **Do not** continue collecting inputs that won't be used (collaborators, substrate, scaffold root).
   - If "different name" → loop back to step 1.

3. **"Brief description of this Collaboration Space?"** — 1-2 sentences. What this shared workspace is for, who it serves, what success looks like at a high level. Lands in the substrate's `README.md` artifact as the welcome paragraph and in `space-{slug}.md` Overview.

4. **"Who are the collaborators?"** — names + emails, one at a time, until the user says "done".

5. **"Which substrate?"** — show only active substrates. Recommend collaboration-native substrates for knowledge spaces.

6. **"Where in {substrate} should this space live?"** — accepts a substrate-native pointer (folder URL for Drive, `{owner}` / `{org}` for GitHub, absolute path for local). If the user presses Enter without input, default to the substrate's natural root:
   - **Drive:** *"Paste a Drive folder URL, or press Enter — I'll look for an existing `/spaces/` folder in your Drive root and offer to create one if missing (recommended convention for keeping all collaboration spaces together)."*
   - **GitHub:** *"Paste an org or username, or press Enter to use your personal GitHub account ({user})."*
   - **Local:** *"Paste an absolute path, or press Enter — I'll look for / offer to create `~/spaces/` (recommended convention)."*

   **`/spaces/` convention (Drive + local):** if the user accepts the default, search the substrate root for a folder named `spaces`. If it exists → use it as parent. If not → ask: *"No `/spaces/` folder found at the root. Create one? It's a useful convention for keeping all collaboration spaces together (one folder per space inside)."* Default: yes. Only use the bare root as a last-resort fallback if user explicitly declines.

   **Parse the input** to extract the substrate-native parent identifier — Drive folder ID from URL (e.g. `drive.google.com/drive/folders/abc123` → `abc123`), GitHub owner/org from URL or input, absolute path for local. This identifier is passed to step 4.1 as `parent_id`.

   This is where the space's parent will live. The space folder itself (`{slug}`) is then created inside.

7. **"What's the name of the first collaborative project?"** — full human-readable name. The command derives the kebab-case slug; the user doesn't need to think about it. **Slug derivation guard:** if the derived slug is empty, all-numeric-prefix, or contains only punctuation after sanitization, surface and ask the user for an explicit slug.

8. **"Brief description of the first project?"** — 1-2 sentences. What this project is, why it exists, what success looks like. Lands in the project's `README.md` artifact.

9. **"Any pre-existing context for this project?"** — optional. Accepts a substrate-native pointer (folder URL, repo, local path, doc URL, or "no"). If provided:
   - Read the context using the appropriate adapter for the source substrate. **If the source substrate's adapter isn't active**, fall back to WebFetch (only works if the URL is publicly readable) or surface a clear cross-substrate-mismatch message and offer to skip context-import.
   - Identify themes / document types in the source content.
     - **0 themes** (incoherent or empty source): tell the user, ship project with `README.md` only.
     - **1 theme**: ask if the user wants to skip file-derivation and just keep the `README.md`, or auto-create a single `{theme}` artifact.
     - **2-4 themes**: propose a corresponding artifact for each (kebab-case names derived from the source); show the user a brief list with one-line explanations. User opts in / out per artifact.
     - **5+ themes**: propose the top-N by content volume; ask if user wants top-N, all, or to manually pick.
   - If "no": project folder ships with just `README.md`.

Then continue to step 3 (Confirm scaffold plan).

#### Mount-existing flow

1. **"What's the substrate link for the existing space?"** — accepts substrate-native pointer (folder URL, repo, local path).

2. **Detect substrate from URL pattern.** Match against the URL-pattern table in § Substrate adapters. If unambiguous, set `detected_substrate`. If ambiguous (e.g. a single Google Doc URL could be Drive metadata or context source), ask the user.

3. **Check active MCP for detected substrate.** If the detected substrate's adapter is **not active** on this machine, surface honestly:
   > *"Substrate '{detected}' detected from the URL. Your active adapters: {list}. The MCP for '{detected}' isn't active.*
   >
   > *Most {detected}-shared spaces are invite-based (e.g. Drive folders shared with your email, GitHub private repos). Authentication for those is handled by the MCP — there's no public URL to fetch.*
   >
   > *Options:*
   > *1. **Install the MCP** (recommended) — see `mcps/_index.md` for bundled adapters and `mcps/setup.sh` for the install path. Re-run `/collaborate` after install.*
   > *2. **Web-only mount** (only works if the substrate folder is publicly readable — public GitHub repo, public Drive share-by-link, etc.). I'll attempt WebFetch on the URL; if it returns a sign-in page or 403, this won't work and you'll need option 1.*
   > *3. **Cancel.**"*

   On choice 2: attempt `WebFetch` on the URL. If the response is the substrate's content (raw markdown, file listing), proceed to mount the `space-{slug}.md` artifact via WebFetch and write to local with `mount-mode: read-only` in frontmatter. Write-back (e.g. `--add-project`) is blocked while in read-only mode. If the response is a sign-in page or auth error, surface honestly: *"That substrate is invite-based, not public. WebFetch can't reach it. Install the MCP."*

4. **List substrate root via adapter** (`list_root_artifacts(folder_id)` — Drive: `list_drive_items`; GitHub: `gh api .../contents/`; local: `ls`). Check for two well-known artifacts:
   - `collaborate.md` (well-known name)
   - `space-*.md` (pattern match — should match exactly one Doc/file whose name starts with `space-`)

5. **Branch on what's found:**

   - **Both `collaborate.md` AND exactly one `space-*.md` exist** → **MOUNT.**
     - Read `collaborate.md`'s frontmatter to verify `collaborate-version: 1` is present. (If absent, it might be a hand-rolled or legacy collab folder — surface and ask user whether to mount anyway.)
     - **Take the matched `space-{X}.md` artifact's name as the local filename** — no slug "discovery" needed; just propagate. The filename IS the slug. (E.g. substrate has Doc named `space-human-being-research` → local mirror is `vault/00 - notes/projects/space-human-being-research.md`.)
     - **Filename-collision guard.** If `vault/00 - notes/projects/space-{X}.md` already exists locally with a *different* `shared-space-url` in frontmatter, surface: *"You have a local `space-{X}.md` pointing to {other-url}. The space you're mounting points to {this-url}. Options: (a) use a suffixed local name (e.g. `space-{X}-2.md`), (b) overwrite the local file (existing mount lost), (c) cancel."*
     - **Mount.** Two cases:
       - **First-time mount (no local mirror exists yet):** Read substrate's `space-{X}.md` artifact via adapter's `read_doc` (converts Drive Doc to markdown; returns `.md` content directly on GitHub/local). Write the markdown content to `vault/00 - notes/projects/space-{X}.md`. Accept that Drive substrate's lossy round-trip will produce a slightly-mangled local mirror (frontmatter destroyed, HTML comments stripped) — known limitation; collaborator can clean up by running `/collaborate --add-project` later (which writes from source-of-truth markdown).
       - **Re-mount (local mirror already exists with same `shared-space-url`):** **Option-2 preservation.** Don't blindly overwrite local with substrate's lossy round-trip — that would destroy the clean source-of-truth markdown locally. Instead:
         1. Read substrate via `read_doc` → `substrate_lossy_content`
         2. Read local mirror → `local_clean_content`
         3. **Compare** by section headings (parse both for `## Quick navigation`, `## Working in this space (AI session guide)`, `## Current State`, `## Active Collaborators`, `## Projects`, `## Overview`, `## Links`)
         4. **Merge:** for each well-known AI-nav section (`## Quick navigation`, `## Working in this space`), use LOCAL's clean version (source-of-truth). For each canonical-content section (Current State, Active Collaborators, Projects, Overview, Links), use SUBSTRATE's version (carries any collaborator edits made via Drive UI).
         5. Reconstruct local with: existing local frontmatter + title + 📜 callout + merged sections.
         6. Write merged result to local. Surface to user any meaningful canonical-content changes detected (e.g., "Active Collaborators table: a collaborator's role description was edited on substrate; pulled into local").
       - **Edge case (rare):** if substrate's AI-nav sections were edited directly via Drive UI (collaborator changed them), those edits are LOST in option-2 merge (we use local's version). Document as a constraint: *"AI-nav sections (Quick navigation, Working in this space) should be edited via /collaborate command, not by direct Drive UI editing — direct edits to those sections are not preserved across re-mounts."* Surface this constraint in the spec template's Working section.
     - Confirm to user with file path, summary table (collaborators / projects), and an orientation pointer: *"For orientation, view `README.md` and `collaborate.md` directly in {space URL} — they're co-located in the substrate folder."*
     - **Mount terminates here** — no scaffold operations follow.

   - **Multiple `space-*.md` artifacts exist** (rare — manual copy-paste, migration artifact, or someone created sibling spaces in the same folder) → list them and ask the user: *"This folder has multiple space metadata artifacts: {list}. Which one represents this space?"* User picks one; mount that one (continue with the MOUNT path above). Other `space-*.md` artifacts are left alone.

   - **One or both required artifacts missing** (folder isn't properly set up as a collaboration space) → surface what's there and what's missing, e.g. *"This folder is missing `collaborate.md` and `space-*.md`. It's not a collaboration space yet."* / *"This folder has `collaborate.md` but no `space-*.md` artifact — it was partially set up or `space-*.md` got deleted."* Offer three paths:
     - **(i) Set this folder up as a collaboration space** — routes to New-space flow with this folder pre-supplied as the substrate location (skips step 2.6). When asking for the space name (step 2.1), pre-suggest the substrate folder's existing name as the default handle (kebab-cased — e.g. *"Sovereignty Research"* → `sovereignty-research`). User can override. The new-space flow will write the missing artifacts on substrate AND create the local mirror. **Caveat:** the existing-artifact collision check at step 3 (Confirm scaffold plan) will surface any name conflicts (e.g. existing `README.md` Doc, existing `space-*.md`) and ask the user per artifact whether to preserve, overwrite, or cancel.
     - **(ii) Use this folder as pre-existing context for a separate new space** — the existing folder becomes input context (step 2.9 of New-space flow). A NEW space is created at a different substrate location; this folder is read for context-seeding artifacts. Lands at step 3 (Confirm scaffold plan).
     - **(iii) Cancel.**

### 3. Confirm scaffold plan

Present what will be created as a **numbered list** (NOT a wide markdown table — tables wrap badly in narrow terminals; pilot finding 2026-05-09). Wait for confirmation. Allow opt-out per item.

**Existing-artifact collision check (mount-existing branch (i) only).** When scaffolding into an existing folder (i.e. routed from mount-existing → "set this folder up"), before the plan, list any artifacts already present in the folder that would collide with the scaffold (`README.md`, `collaborate.md`, `space-*.md`, `projects/` subfolder). Per collision, ask the user: *"Existing `{artifact}` found. Preserve (skip the scaffold for this one), overwrite (replace with template), or cancel?"*. New-space flow into a fresh folder skips this check (nothing to collide).

**Format (terminal-friendly — short bolded items, indented detail):**

```
**Scaffold plan:**

1. **Space folder** — `{space}` at {parent path/URL} ({create new | use existing})
2. **Space access** — {collaborators} as editors (only if new space + substrate supports access)
3. **Space root artifacts** — `README.md`, `collaborate.md`, `space-{slug}.md` (3 artifacts; `collaborate.md` carries the operating protocol; on Drive these are Google Docs named with .md)
4. **Project folder** — `projects/{project-slug}/` (new collaborative project inside the space)
5. **Project artifacts** — `README.md` (always) + {opted-in context-derived artifacts}
6. **Local mirror** — `vault/00 - notes/projects/space-{slug}.md` (content-identical mirror; written from source-of-truth markdown, NOT round-tripped from substrate — preserves frontmatter)
```

Each item lives on its own line with bolded label + concise detail. Avoid wide tables in interactive output — they break in 80-column terminals.

**`--dry-run` mode:** output the plan above with `[DRY RUN — no writes will happen]` header and exit. Steps 4-7 are skipped entirely.

### 4. Scaffold the Collaboration Space (substrate-agnostic flow)

**Maintain a rollback log.** Every persistent op appends `{op, target, undo}` to an in-memory log. On any step failure: surface the failure, show the rollback plan, ask the user *"Roll back all changes, or stop here for manual investigation?"*. If rollback is chosen, execute undo ops in reverse order. If rollback itself fails, dump the log so the user can clean up manually.

> **No pre-write health probe.** The first real op (`ensure_folder` in step 1 below) fails loudly on auth/network/permission issues, and the rollback log handles partial-write states. A separate probe duplicates the signal and (on Drive specifically) clutters the user's root with `.collaborate-probe-*` folders if cleanup fails. Real failure = real signal.

For the chosen substrate, execute these abstract operations using the substrate's adapter:

1. **Ensure space folder** — create at user-specified parent location (step 2.6) if new (log undo: delete-folder); identify ID/URL if existing (no undo needed). **Auth/network/permission failures surface here as natural fail-fast** — abort cleanly before any further state.
2. **Apply access** (only if new space) — add each collaborator at the substrate's "editor" equivalent (log undo: revoke each grant).
   - **GitHub default:** read-only (`pull`). Push permission requires explicit user approval — outside-the-org collaborators start with safe permissions.
   - **Other substrates:** editor-equivalent default is fine; defer to user preference.
   - **Verify access applied (read-back).** Immediately after each `apply_access` call, query the access list to confirm the grant landed. Some APIs silently no-op on permission changes — read-back catches this. If mismatch: surface clearly, retry once, otherwise abort with rollback prompt.
3. **Write space root artifacts** (only if new space — the three canonical artifacts):
   - `README.md` from the welcome template (§ Templates), via adapter's `write_doc` (log undo: delete artifact)
   - `collaborate.md` from the operating-protocol template (§ Templates) — **frontmatter includes `collaborate-version: 1`** plus Mount instructions. On Drive, frontmatter is preserved as plain text at the top of the Google Doc (verify on first pilot run) (log undo: delete artifact)
   - `space-{slug}.md` from the space-metadata template (§ Templates), via `write_doc` (log undo: delete artifact)
4. **Ensure `projects/` folder** at space root (log undo: delete if newly created).
5. **Create project folder** `projects/{project-slug}/` (log undo: delete folder).
6. **Write project artifacts**:
   - `README.md` from the project-README template (always), via `write_doc` (log undo: delete artifact)
   - Any opted-in artifacts derived from pre-existing context (only if step 2.9 returned context) (log undo: delete each)
7. **Update substrate's `space-{slug}.md` Projects table** — append a new row for the new project (with link to its `projects/{project-slug}/` folder). Use the adapter's `append_to_table` operation (Drive: `append_table_rows` against the Google Doc; GitHub/local: read+modify+write the `.md` file). **Capture prior content before write** (log undo: restore prior content).

The substrate's adapter handles the substrate-native specifics (MCP calls, CLI commands, access conventions, artifact formats). The command spec itself stays substrate-agnostic.

### 5. Create or refresh the local mirror

**The local mirror is content-identical to the substrate's `space-{slug}.md` artifact** (semantically identical at the section/content layer; byte-equality only holds for `.md`-native substrates like GitHub/local). Both must be **written together** at scaffold time — same source-of-truth markdown to substrate (via `import_to_google_doc`) AND to local (via direct file write). Never one without the other.

**Critical pattern — DO NOT re-read from substrate to write local mirror at scaffold time.** Drive round-trip is lossy (frontmatter destroyed, HTML comments stripped, blockquotes lost — see § Substrate adapters Drive caveats). The local mirror is the source-of-truth markdown layer; the substrate Doc is the Drive-rendered view. They share identical content at scaffold time:

- **New space (or `--add-project`):** write BOTH (substrate via `import_to_google_doc` in step 4.3 / 4.7 + local via direct file write) using the same source-of-truth markdown. This preserves frontmatter validity for Obsidian AND ensures the substrate has the AI-nav sections collaborators need.
- **Mount-existing flow (re-mount with local already present):** apply **option-2 preservation** as defined in mount-existing step 5 — preserve well-known AI-nav sections from local (clean source), refresh canonical-content sections from substrate (carries collaborator edits). Never blindly overwrite.
- **Mount-existing flow (first-time mount, no local):** read substrate via `read_doc`, accept Drive's lossy artifacts in the local mirror as a one-time tax. Subsequent `--add-project` writes will replace the lossy local with clean source-of-truth markdown.
- **GitHub/local substrate:** byte-identical round-trip; no special preservation logic needed.

**Slug-collision guard at write time.** If a local `space-{slug}.md` exists with a different `shared-space-url` in frontmatter, the slug-collision branch in mount-existing already surfaced this. New-space flow shouldn't hit this case (existing-space check in step 2.2 catches it earlier). Defensive check: refuse to overwrite, surface the conflict.

Sync trigger going forward: any AI session that reads the substrate's `collaborate.md` artifact (per CLAUDE.md's Project Focus Protocol when working on a shared project) will run the Mount instructions inside, which apply option-2 preservation to refresh the local mirror automatically. No separate command needed.

### 6. Update projects index

Add or refresh the entry in `00 - notes/projects/_index.md` Project Snapshots, under a "**Collaboration Spaces**" sub-header.

- New space: add a new entry `[[space-{space-slug}]]` with one-line pulse (substrate + collaborators + first project).
- Existing space: refresh the pulse line if the projects table grew or status changed.

### 7. Confirm done

Output a summary table:

> **Scaffold complete:**
> | What | Where |
> |---|---|
> | Space | `{space}` at {URL/path} |
> | Project | `projects/{project-slug}/` (inside the space) |
> | Space router | `vault/00 - notes/projects/space-{space-slug}.md` (new — first project in space) **OR** Projects-table row appended (existing space) |
> | Collaborators | {names + access level per collaborator} |

Suggest 2-3 generic next steps based on what was created (e.g. *"share the space link with collaborators"*, *"consider seeding `projects/{slug}/` context with relevant agents from `agents/_index.md` based on project topic"*, *"update USER.md → Sources if this space should be a routine `/today` source"*). **Don't auto-spawn agents.** Don't reference specific agent names in the spec — let the user match agents to their topic from the registry.

## Subcommand: `/collaborate --add-project`

Adds a new collaborative project to an already-mounted Collaboration Space without re-running the full flow.

### Steps

1. **Pick the space.** Four cases:
   - **Pre-selected space** (when invoked from step 2.2 collision routing in the default flow — *"add to existing"* choice): skip the picker entirely. Confirm once: *"Adding a new project to '{pre-selected slug}' on {substrate}?"*. Then continue to step 2.
   - **Discover mounted spaces** by globbing `vault/00 - notes/projects/space-*.md`. Three sub-cases:
   - **Multiple spaces:** show as a numbered menu (slug + substrate + collaborators line). User picks one.
   - **Single space:** default to it and confirm (`"Add a project to '{slug}'?"`).
   - **Zero spaces (no `space-*.md` files locally):** surface and offer fall-through:
     > *"No mounted Collaboration Spaces found in `vault/00 - notes/projects/`. `--add-project` adds a project to a space you've already created or mounted.*
     > *Options:*
     > *1. **Create a new space** (route to `/collaborate` default flow → new-space)*
     > *2. **Mount an existing space** (route to `/collaborate` default flow → mount-existing)*
     > *3. **Cancel.**"*
     On choice 1 or 2, hand off to the default flow (which scaffolds/mounts a space and creates the first project — same end state as `--add-project` would have produced for an existing space).

2. **Refresh local mirror.** Read substrate's `space-{slug}.md` artifact via the substrate's adapter. **MCP-availability check:** if the substrate's adapter is no longer active (e.g. user uninstalled the MCP since mounting), surface the same options as the mount-existing MCP-mismatch fallback (install / web-only read / cancel). Web-only mode blocks `--add-project` from completing — write-back requires the active MCP. **Auth/network failures here are the natural fail-fast** — no separate probe needed.

3. **Ask for project name.** Same as default-flow step 2.7 (with slug-derivation guard).

4. **Ask for project description.** Same as default-flow step 2.8.

5. **Ask for pre-existing context.** Same as default-flow step 2.9 (with theme-count branching).

6. **Confirm scaffold plan** — table shows only project-level operations (no space-creation, no access-grants). `--dry-run` honored.

7. **Scaffold (rollback log enabled):**
   - Create `projects/{project-slug}/` (log undo: delete folder)
   - Write project README + opted-in context artifacts via adapter's `write_doc` (log undo: delete each)
   - Append new row to substrate's `space-{slug}.md` Projects table via `append_to_table` (log undo: restore prior content)
   - **Append bullet to substrate's `space-{slug}.md` Links section** — `- **{project-name}:** {project-folder-URL}` after the last existing project bullet. Use `find_replace` on the prior project's bullet line as anchor: find the prior line, replace with `prior-line\n- **{new-project}:** {URL}`. (Pilot finding 2026-05-09: this step was missed in v8.2 spec — Links section grew stale on first `--add-project`. Now mandatory.)

8. **Refresh local mirror.** Re-read substrate's `space-{slug}.md` and write to local.

9. **Update `_index.md`** — refresh the pulse line for this space (project count grew).

10. **Confirm done** with a summary line.

> **Why this exists.** Adding a collaborative project to an existing space is the high-frequency op; full `/collaborate` is one-time per space. `--add-project` is the daily-driver; the default flow is the bootstrapper.

## Subcommand: `/collaborate --status`

Read-only — reports mount health across all Collaboration Spaces in the local vault.

### Steps

1. List all `vault/00 - notes/projects/space-*.md` files.

2. For each space:
   - Read local frontmatter (`shared-substrate`, `shared-space-url`, optional `mount-mode`).
   - **MCP active?** Check whether the substrate's adapter is currently active.
   - **Substrate reachable?** Via the adapter, fetch `space-{slug}.md` artifact metadata only (last-modified timestamp + content hash if cheap).
   - **Drift detected?** Compare local content hash vs substrate hash. (Note: for Drive substrate, byte-equality comparison won't work due to Google Doc round-trip; use a normalized-content hash or a "last-known-substrate-modified-at" timestamp stored in local frontmatter.)

3. Output a table:

> **Mounted Collaboration Spaces:**
> | Space | Substrate | MCP active? | Reachable? | Drift? | Notes |
> |---|---|---|---|---|---|
> | `{slug}` | {drive/github/local} | ✅ / ❌ | ✅ / ❌ | none / local-stale / unknown | {one line — last-mounted date or specific issue} |

4. For any row with drift or MCP issue, suggest the next step (*"run `/collaborate` mount-existing flow to refresh"*, *"install the missing MCP via `mcps/setup.sh`"*, etc.).

No write operations. Pure diagnostic.

## Substrate adapters

Each substrate implements the same abstract operations: `find_folder`, `ensure_folder`, `apply_access`, `write_doc`, `read_doc`, `append_to_table`, `read_existing_context`. Adding a substrate = registering its adapter.

### URL pattern detection (mount-existing flow step 2)

| URL pattern | Detected substrate |
|---|---|
| `drive.google.com/drive/folders/...` | drive |
| `docs.google.com/document/...` | drive (single-doc — ambiguous; ask user) |
| `github.com/{owner}/{repo}` (or `git@github.com:{owner}/{repo}.git`) | github |
| Absolute filesystem path (`/...`) | local |
| Anything else | ask user explicitly |

### Currently registered adapters

**Drive** (recommended for knowledge spaces — collaborator UX is best with Google Docs):
- **Substrate-native artifact type:** Google Docs **named with `.md` extension** (e.g. `collaborate.md`). The `.md` is a visual signal of markdown-source-of-truth; Drive treats the file as `application/vnd.google-apps.document` regardless. In-browser editing/comments/suggestions all work.
- `list_root_artifacts(folder_id)` → `mcp__google-workspace__list_drive_items` (returns name + mimeType for each item; used in mount-existing flow to find `collaborate.md` and `space-*.md`). Match by both `space-*.md` and legacy `space-*.md` (no extension) for backward compatibility.
- `find_folder` (cross-substrate existence check at step 2.2) → `mcp__google-workspace__search_drive_files` (mimeType=folder, name match across user's whole Drive).
- **`/spaces/` convention check (step 2.6 default):** `mcp__google-workspace__search_drive_files(query="name='spaces' and mimeType='application/vnd.google-apps.folder' and 'root' in parents")`.
- `ensure_folder` → `mcp__google-workspace__create_drive_folder` (with `parent_id` from step 2.6) or use existing if found.
- `apply_access` → **`mcp__google-workspace__manage_drive_access(action='grant', share_with={email}, role='writer', share_type='user', send_notification=true)`**. (Pilot finding 2026-05-09: `set_drive_file_permissions` is link-sharing only — wrong tool. `manage_drive_access` is the per-user grant.)
- `write_doc` (markdown content → Google Doc with .md filename) → `mcp__google-workspace__import_to_google_doc(file_name='{name}.md', folder_id={parent}, content={markdown}, source_format='md')`. **NOTE:** `import_to_google_doc`'s description says "extension will be ignored," and the Doc gets created without .md in the name. **Two-step pattern required:** (1) `import_to_google_doc(file_name='{name}', ...)` to create the Doc; (2) `update_drive_file(file_id={new_id}, name='{name}.md')` to add the .md extension as the visible name. Both confirmed working in pilot 2026-05-09.
- `read_doc` (Google Doc → markdown) → `mcp__google-workspace__get_doc_as_markdown`. **Caveat:** content-identical only, not byte-identical. Frontmatter, HTML comments, blockquotes are LOST in round-trip. Use `read_doc` for human-meaningful body content, NOT for parsing structured metadata — metadata lives in the local mirror.
- `append_to_table` (for `space-{slug}.md` Projects table updates) — **validated working pattern as of 2026-05-09 pilot.** Three-step sequence:
  1. `mcp__google-workspace__inspect_doc_structure(detailed=true, tab_id='t.0')` to enumerate tables. Convention: Projects table is the **3rd table (index 2)** in the standard `space-{slug}.md` Doc structure — order is Current State, Active Collaborators, Projects.
  2. `batch_update_doc(operations=[{type: 'insert_table_row', table_start_index, row_index: <last-row-index>, insert_below: true}])` to extend the table with an empty row.
  3. `batch_update_doc(operations=[insert_text...])` to fill the 4 cells. **Use REVERSE order** (last cell first, working backwards) so earlier indices stay valid through the batch. Cell positions of an empty row, derived from row_marker math: for a 4-column row, cells are at positions `table_end_before_insert + 1, +3, +5, +7` (each empty cell is 2 chars wide). E.g. table ended at 2128 before the insert, so the 4 cells are insertable at indices 2129, 2131, 2133, 2135.
  - **Why reverse-order works:** `insert_text` shifts only indices ≥ the inserted position. Inserting at 2135 first shifts only 2135+ (which we don't touch again); inserting at 2133 next is unaffected; etc. Single batch, all cells filled, no index drift.
  - **Caveat:** `mcp__google-workspace__append_table_rows` is the **Sheets** API, NOT Docs (pilot finding 2026-05-09). Don't use it. HTML-comment markers (`<!-- table:projects -->`) are stripped by Drive — can't anchor by comment text. Structural-position (3rd table) + row-marker math is the working strategy.
- `read_existing_context` → `mcp__google-workspace__list_drive_items` + `get_doc_as_markdown` per matched file (for Drive-source context). **For LOCAL-source context** (e.g. a path inside the user's vault that gets imported as a project artifact): the Google Workspace MCP sandboxes file paths to `~/.workspace-mcp/attachments/`. Two-step pattern: (1) `cp {vault-path} ~/.workspace-mcp/attachments/{name}.md`; (2) `import_to_google_doc(file_path='~/.workspace-mcp/attachments/{name}.md', ...)`. Pilot finding 2026-05-09: `import_to_google_doc(file_path='/path/inside/vault')` fails with "path is outside permitted directories". Always copy to allowed dir first, OR use `content` parameter inline (works for files small enough to fit context window)..
- Read-back access verification: `mcp__google-workspace__get_drive_file_permissions`.
- **Round-trip caveats** (pilot finding 2026-05-09): `import_to_google_doc` + `get_doc_as_markdown` is content-identical, NOT byte-identical:
  - YAML frontmatter (`---` blocks) breaks — `---` becomes section divider, YAML body becomes malformed H2 heading. **Frontmatter only lives in the local mirror.**
  - HTML comments stripped (`<!-- table:projects -->` doesn't survive). Use structural position or named ranges instead of text markers.
  - Blockquote `>` markers lost — paragraphs become plain.
  - Cosmetic: table headers auto-bolded; emails/URLs auto-linked.
  - Drift detection (`--status`) must use normalized-content comparison, not byte-hash.
- **Local mirror is source-of-truth markdown, NOT a re-read of substrate.** When writing the local mirror after scaffold, write the original markdown content directly (the same content sent to `import_to_google_doc`), not the result of `get_doc_as_markdown` on the freshly-imported Doc. This preserves frontmatter validity for Obsidian. The substrate Doc is for human collaborator UX; the local mirror is the machine-readable layer.

**GitHub** (recommended for code-adjacent collaborations or public templates):
- **Substrate-native artifact type:** `.md` files (git-native; byte-identical mirror works)
- `list_root_artifacts(repo)` → `gh api repos/{owner}/{repo}/contents/` (returns root file/dir listing; used in mount-existing to find `collaborate.md` and `space-*.md`)
- `find_folder` — context-dependent:
  - **Cross-substrate existence check (step 2.2)** — owner unknown: `gh repo list --json name,nameWithOwner --limit 200` then filter by name match across all repos the user has access to.
  - **Specific repo check (steps 4.1+)** — owner known: `gh api repos/{owner}/{repo}` (returns 404 if not exists).
- `ensure_folder` → `gh repo create {owner}/{space} --private --add-readme=false` (or use existing if found)
- `apply_access` → `gh api repos/{owner}/{space}/collaborators/{user} -X PUT -f permission={pull|push}` — read-only default (`pull`); push requires explicit approval
- `write_doc` → local clone + write `{name}.md` file + commit + push. **For multi-file scaffolds (e.g. step 4.3 + 4.6 writing 4+ files), batch into a single commit-push cycle:** one clone, all writes, single commit (`Scaffold {space}`), single push. Avoid per-file commit-push churn.
- `read_doc` → `gh api repos/.../contents/{name}.md` (returns base64-decoded content)
- `append_to_table` → read the `.md` file, append a markdown table row, write back
- `read_existing_context` → `gh api repos/.../contents/...` recursively
- Read-back access verification: `gh api repos/{owner}/{space}/collaborators/{user}/permission`

**Local** (when shared-via-cloud-sync-folder, e.g. iCloud or local-Drive-mount):
- **Substrate-native artifact type:** `.md` files (filesystem-native; byte-identical mirror works)
- `list_root_artifacts(path)` → `ls {path}` (returns filenames; used in mount-existing to find `collaborate.md` and `space-*.md`)
- `find_folder` → check if `{path}/{slug}` directory exists. Skipped at step 2.2 (cross-substrate existence check) — no canonical default path to enumerate.
- `ensure_folder` → `mkdir -p {path}/{space}`
- `apply_access` → N/A (filesystem permissions only — flag for user)
- `write_doc` → write `{name}.md` file directly
- `read_doc` → read `{name}.md` file directly
- `append_to_table` → read file, append row, write back
- `read_existing_context` → read filesystem
- Read-back access verification: N/A

**Adding a new substrate** = creating an adapter that implements the abstract operations above using the substrate's native MCP / CLI / API. Declare the substrate-native artifact type explicitly (Doc-equivalent? raw markdown? other?). Once registered, the new substrate appears as an option in step 1 of the command flow whenever its underlying capability is active on the user's machine.

## Templates

> **Note on materialization:** the templates below show source-of-truth markdown content. The adapter materializes this per substrate — Google Doc on Drive (frontmatter preserved as plain text at the top); `.md` file on GitHub/local. Where the templates reference filenames like `space-{slug}.md`, the local-mirror side is always `.md`; the substrate side is per-adapter (Google Doc named `space-{slug}.md` on Drive; file `space-{slug}.md` elsewhere).

### Space `README.md` (welcome page — Doc on Drive; `README.md` on GitHub/local)

```markdown
# {Space display name}

{Brief description from /collaborate input — 1-2 sentences. What this shared workspace is for, who it serves, what success looks like at a high level.}

**Collaborators:** {collaborator names}

**To mount this in your vault:** run `/collaborate` and pick "mount an existing space" — paste this folder's URL when asked. Your AI session will read `collaborate.md` and copy `space-{slug}.md` to your vault as `vault/00 - notes/projects/space-{slug}.md` (a content-identical mirror of the substrate version).

**What's here:**
- `collaborate.md` — how we work here (read this first if you're new)
- `space-{slug}.md` — shared metadata: collaborators, projects, status (this is the artifact your local mirror tracks)
- `projects/` — active and past collaborative projects
- {add other top-level folders only if they're actually used}

**What's NOT here:**
- Personal observations, growth notes, antifragile rules — those live in each collaborator's own vault
- Confidential venture content — stays in respective venture vaults

**Source of truth:** this folder. All collaborators treat the contents here as canonical.

---
Created: {YYYY-MM-DD} via /collaborate
```

### `collaborate.md` (operating protocol — Doc on Drive; `collaborate.md` on GitHub/local)

```markdown
---
collaborate-version: 1
created: {YYYY-MM-DD}
updated: {YYYY-MM-DD}
---
# collaborate — How We Work Here

## Collaborators
- {Name} ({email}) — {what they bring to this space}
- {Name} ({email}) — {what they bring to this space}

## Purpose
{One paragraph — why this collaboration space exists, what it produces, what success looks like.}

## Decision authority (INTENT)
- Default: consensus
- {Name} owns: {topic / domain}
- {Name} owns: {topic / domain}
- Disagreements: {how resolved — escalate? sleep on it? coin flip?}

> Each collaborator's individual `INTENT.md` (in their own vault) governs their personal autonomy levels. This section is the *interpersonal* contract layered on top.

## Communication norms
- Async first: {substrate-native comments / voice notes / shared doc threads}
- Sync cadence: {e.g. weekly 30-min, ad-hoc when needed}
- Response expectation: {e.g. within 48h on async, same-day on urgent flags}

## AI behavior in this space
- All collaborators' AI sessions can read and write here
- Drafts land in `projects/{slug}/notes/` (or similar) for review before being moved to canonical artifacts
- Personal observed-context never writes here

## Mount instructions (auto-managed — your AI session runs this when reading this file)

When an AI session reads this file as part of working on this Collaboration Space, it should:

1. **Check** whether `vault/00 - notes/projects/space-{space-slug}.md` exists in the user's local vault.
2. **If not exists (first-time mount):** read this folder's `space-{space-slug}.md` artifact (Google Doc on Drive; `.md` file on GitHub/local) via the substrate's adapter, and write the markdown content to `vault/00 - notes/projects/space-{space-slug}.md`. On Drive substrate, accept lossy round-trip artifacts as a one-time tax (frontmatter may be malformed; subsequent `/collaborate --add-project` ops will replace the lossy local with clean source-of-truth markdown). Confirm to the user: *"Mounted Collaboration Space '{space}' at vault/00 - notes/projects/space-{space-slug}.md."*
3. **If exists (re-mount) — apply option-2 preservation:**
   - Read substrate's `space-{space-slug}.md` → `substrate_content`
   - Read local's existing `space-{space-slug}.md` → `local_content`
   - Parse both for well-known section headings: `## Quick navigation`, `## Working in this space (AI session guide)`, `## Current State`, `## Active Collaborators`, `## Projects`, `## Overview`, `## Links`
   - **Merge:** for AI-nav sections (`## Quick navigation`, `## Working in this space`) use LOCAL's clean source-of-truth version. For canonical-content sections (Current State, Active Collaborators, Projects, Overview, Links) use SUBSTRATE's version (carries any collaborator edits made via Drive UI).
   - Reconstruct: existing local frontmatter + title + 📜 callout + merged sections.
   - If the merge produces no meaningful canonical-content changes (substrate sections match local's at the content layer): no-op silently.
   - If meaningful changes exist (e.g., Active Collaborators table updated, Projects table extended): write merged result to local; surface a one-line summary (*"Pulled substrate changes: Active Collaborators role description updated"*).

**Slug-collision guard:** if `vault/00 - notes/projects/space-{space-slug}.md` already exists locally pointing to a *different* substrate URL, surface the conflict and ask the user before overwriting (suffixed name / overwrite / cancel).

**Edge case (rare):** if AI-nav sections (Quick navigation, Working in this space) were edited directly via Drive UI on substrate, those edits are LOST in option-2 merge (we use local's source-of-truth version). **Convention: AI-nav sections should be edited via `/collaborate` command, not via direct Drive UI editing.** Direct edits to those sections aren't preserved across re-mounts.

**The local file is a content-identical mirror at the section layer.** Don't edit the local file's canonical-content sections directly — those edits will be overwritten on next re-mount when substrate has fresher content. To change shared content (collaborators, projects, status), edit the substrate's `space-{space-slug}.md` artifact directly OR run `/collaborate --add-project` to add a new collaborative project (which updates both substrate and local in one op).

Want private notes about this collaboration? Use existing vault tools — daily notes, `00 - notes/ideas/`, `00 - notes/reflections/`, or personal observed-context. The local mirror doesn't host private content.

## Five rules for shared content
1. **Described** — every artifact has a short header explaining what it is
2. **No hardcoded personal context** — references are wiki-link or label, not "my OS path"
3. **Dependencies documented** — if an artifact depends on another, say so
4. **No secrets** — API keys, credentials, private data live in personal vaults, not here
5. **Testable by someone else** — a collaborator should be able to use the artifact without asking

## What's NOT here
- Personal observed-context (each person's `growth.md` / `patterns.md` / `antifragile.md`)
- Each collaborator's confidential venture content
- {add specific exclusions for this collaboration}

## Lifecycle
- Status: Active
- Started: {YYYY-MM-DD}
- Cadence-review: {e.g. quarterly} — are we still doing the right work the right way?
- Archive criteria: {when do we wind this down}

---
Updated: {YYYY-MM-DD}
```

### `projects/{slug}/README` (collaborative project context stub — Doc on Drive; `README.md` on GitHub/local)

```markdown
# {Project Name}

## What this is
{Brief description from /collaborate input — 1-2 sentences. What this collaborative project is, why it exists, what success looks like.}

## Current state
{Where this stands today. Updated as the project evolves.}

## Artifacts in this folder
{List the artifacts actually here — start with just this README; add lines as artifacts are added. Avoid pre-listing artifacts that don't exist yet.}

## Open questions
- {populate as they emerge}

---
Created: {YYYY-MM-DD}
```

### Substrate `space-{slug}.md` (canonical shared metadata — also the local mirror's content)

This is the **same content** that ends up at `vault/00 - notes/projects/space-{slug}.md` (content-identical mirror). The substrate version is canonical; the local version is a synced cache. No private sections — pure shared content.

```markdown
---
tags: [project, active, shared, collaboration, collaboration-space]
stakeholders: [external, {collaborator-slugs}]
created: YYYY-MM-DD
status: active
shared-substrate: {drive | github | local}
shared-space-url: {URL or path}
---
# Collaboration Space — {Space display name}

> **📜 Operating protocol — read first:** [`collaborate.md`]({collaborate-doc-URL}) on the substrate is the rules document for this space. Decision authority, communication norms, AI behavior, mount instructions — all there. Any AI session working in this space (yours, your collaborators', or future sessions) reads it before acting.

## Quick navigation

Direct URLs to space-root artifacts (substrate-side). Project-level artifacts live inside each project folder and are listed in that project's own `README.md`.

- 📜 **Operating protocol:** [`collaborate.md`]({collaborate-doc-URL}) — rules, decision authority, communication norms, AI behavior
- 📖 **Welcome page:** [`README.md`]({readme-doc-URL}) — for new collaborators landing in the space
- 📊 **Canonical metadata (this file's substrate twin):** [`space-{slug}.md`]({space-slug-doc-URL})
- 📁 **All projects:** [`projects/`]({projects-folder-URL}) — each project is a subfolder with its own `README.md` listing artifacts inside

## Current State

| Key | Value |
|---|---|
| Type | Collaboration Space (shared collaboration) |
| Source of truth | **REMOTE — {substrate}** ({URL or path}) |
| Substrate | {Google Drive / GitHub / local} |
| Status | Active |
| Operating protocol | [`collaborate.md`]({collaborate-doc-URL}) — go-to rules for this space |
| Orient | {one line: what this space is for — collaboration purpose, who's involved, what compounds here} |

## Active Collaborators

| Name | Role / Strength | Email | Access |
|---|---|---|---|
| {Name} | {what they bring} | {email} | editor |
| {Name} | {what they bring} | {email} | editor |

> **Use plain names in this table — no wikilinks.** Pilot finding 2026-05-09: Obsidian's auto-formatter mangles wikilinks (`[[name|Display]]`) inside markdown table cells, splitting them across columns. Plain names work on both substrate and local. If you want wiki-graph linkage to a person's vault note, do it in narrative paragraphs (Overview, Working in this space), not in tables.

> Auto-synced from substrate access list on `/collaborate` runs. Manual edits to the local mirror are overwritten on next sync; edits to the substrate version propagate to all collaborators.

## Projects

<!-- table:projects -->

| Project | Status | Folder | Last touched |
|---|---|---|---|
| {Project Name} | active | [`projects/{project-slug}/`]({URL}) | YYYY-MM-DD |

> One row per collaborative project. Project content lives in the substrate at `{shared-space-url}/projects/{project-slug}/`. Status values: `active` / `paused` / `archived`. Add a row when `/collaborate --add-project` creates a new project in this space. **No "Artifacts" column** — it would drift (collaborators add artifacts via Drive UI; the local note can't see those changes until next sync) and scale poorly (many artifacts → unreadable cell). Each project's own `README.md` is the canonical "what's in this folder" answer; or list-folder via the substrate's adapter when current state is needed.

## Working in this space (AI session guide)

Quick reference for any AI session — yours, your collaborators', or future — that lands in this space.

- **Need the rules?** → read [`collaborate.md`]({collaborate-doc-URL}) on the substrate (decision authority, communication norms, AI behavior, mount instructions all there)
- **Add a new project to this space?** → run `/collaborate --add-project` (picks this space, scaffolds the project folder + initial README, appends to Projects table, refreshes this mirror)
- **Check sync state across all mounted spaces?** → run `/collaborate --status`
- **Need to see what's in a project?** → list the project's substrate folder via the adapter, OR read the project's own `README.md` (canonical "what's here" per project)
- **Drafts vs canonical?** → drafts go in `projects/{slug}/notes/` (or similar) inside the substrate; promote to canonical artifacts when reviewed. See `collaborate.md` § "AI behavior in this space"
- **Personal observed-context never writes here** — `growth.md`, `patterns.md`, `antifragile.md` stay in each collaborator's own vault

> **Substrate and local mirror carry the same sections.** Both have Quick navigation, this Working guide, Current State, Active Collaborators, Projects, Overview, Links. Format-conversion artifacts diverge naturally: local keeps clean YAML frontmatter / HTML comments / blockquote markers; the substrate Drive Doc loses these in round-trip. Local is the source-of-truth for markdown; substrate is the Drive-rendered view. On re-mount (option-2 logic in § Mount-existing flow), well-known AI-nav sections are preserved from local (clean source) while canonical-content sections (Current State, Active Collaborators, Projects, Overview, Links) refresh from substrate (carries collaborator edits made via Drive UI).

## Overview

{Brief description from /collaborate input — 1-2 sentences. Same text as the welcome paragraph in README. Visible to all collaborators.}

## Links

- Shared space: {URL}
- collaborate: {URL}
- {one link per active project's substrate folder}
```

## Rules

- **Substrate-pluggable, not substrate-coupled.** Adapters are the plugin point. Adding a substrate doesn't change the command spec.
- **Substrate-native artifact types are per-adapter.** Drive: Google Docs (no extension). GitHub/local: `.md` files. Adapters handle materialization; spec stays artifact-agnostic where possible.
- **Local mirror is content-identical to substrate** (semantic equality at the canonical-content layer). Byte-equality only holds for `.md`-native substrates (GitHub/local). Drive's Google-Doc round-trip produces locally-different bytes for the same semantic content.
- **Substrate and local carry the SAME sections** including AI-navigation (`## Quick navigation`, `## Working in this space (AI session guide)`). Symmetric content, asymmetric format-conversion artifacts only (frontmatter / HTML comments / blockquotes survive in local; Drive's lossy round-trip mangles them in substrate). Local is source-of-truth markdown; substrate is the Drive-rendered view. **Both must be written together at scaffold time / `--add-project` time** — never one without the other.
- **No "Artifacts" column in the Projects table.** Tempting (would let an AI session see per-project artifact lists without a Drive trip) but rejected: drift (collaborators add artifacts via the substrate UI, local mirror can't see), scale (many artifacts → unreadable cell), redundancy (each project's own `README.md` is the canonical "what's in this folder" answer; list-folder via adapter is one cheap call when current state is needed). Keep the Projects table at: Project / Status / Folder URL / Last touched. Per-project content discovery happens via the project's own README or a list-folder call.
- **Compound-value path is preferred.** Many collaborative projects per space when collaborators are stable. Always check for an existing space before creating a sibling — and route `add-to-existing` choices through `--add-project`, not back through full scaffold.
- **Zero private sections in `space-{slug}.md`.** The local file is a pure cache. No merge logic, no section preservation.
- **Private notes about shared work go elsewhere.** Daily notes for tasks/narration. `00 - notes/ideas/` for half-formed thoughts. `00 - notes/reflections/` for longer riffs. Personal observed-context for behavioral patterns. The local mirror doesn't host these — keeps collaborator parity automatic.
- **Personal observed-context never writes to shared.** Structural, not policy. The vault's `00 - notes/context/observed/` files don't get scaffolded into the space, ever.
- **Project folder ships with `README.md` only.** Other artifacts exist only if pre-existing context was provided and the user opted in. Don't pre-stub `vision.md` / `mission.md` / `decisions.md` — those are project-specific shapes that should emerge from the work, not be imposed by the scaffold.
- **No people stub files.** Collaborator info lives in `space-{slug}.md`'s Active Collaborators table. Don't auto-create `vault/00 - notes/people/{name}.md` profiles.
- **Access behavior:**
  - Default: collaborators added at substrate's "editor" equivalent.
  - GitHub: read-only (`pull`) default; push requires explicit user approval. Outside-the-org collaborators start with safe permissions.
  - Always confirm access settings with user before applying.
  - Always read-back access after applying — silent no-ops are a known failure mode on some APIs.
- **Sync trigger is the substrate's `collaborate.md` artifact.** When any AI session reads it (per the host vault's project-focus protocol), it runs the Mount instructions inside — refreshes the local mirror from the substrate's `space-{slug}.md` artifact. No separate sync command needed.
- **`collaborate-version` marker enables idempotency.** Re-running `/collaborate` on a folder with `collaborate-version: 1` in `collaborate.md`'s frontmatter routes to mount-existing (or `--add-project` if user wants to extend). Never re-scaffolds a known space silently.
- **Mount-existing propagates filename, doesn't discover slug.** When mounting an existing space, the local mirror takes the same filename as the matched substrate `space-*.md` artifact (`space-{X}.md` → `vault/00 - notes/projects/space-{X}.md`). The slug is just *part of the filename* — there's no separate "slug discovery." This is the asymmetry between new-space (slug comes from user input) and mount-existing (slug already lives in the substrate's filename, just propagate it).
- **Partial-state on substrate routes to set-up flow, not silent recovery.** If `collaborate.md` or `space-*.md` is missing on substrate, the folder isn't properly set up. Don't try to "regenerate from collaborators table" or paper over the gap. Honest answer: surface what's missing and offer to set it up (routes to new-space flow with substrate pre-supplied; user confirms before any existing content is overwritten).
- **Concurrent `--add-project` against the same space is a known limit.** Two collaborators running `--add-project` simultaneously can race on the substrate's `space-{slug}.md` Projects table. If the adapter's `append_to_table` truly appends (Drive's `append_table_rows` does), both rows land — fine. If a stale-read-then-write pattern is used, last-writer-wins and one row is lost. At pilot scale (2–3 collaborators), probability is low and the failure mode is recoverable (manually re-add the lost project). Mitigation (optimistic locking, etag check, retry-on-conflict) deferred until observed in practice.
- **No pre-write probe.** The first real op (`ensure_folder`) is the natural fail-fast signal. Probes duplicate information and (on Drive) clutter the user's root.
- **Rollback log on partial failure.** All persistent ops are logged with undo. On failure, prompt for rollback or manual investigation. Don't leave partial state silently.
- **Web-only fallback only applies to publicly-readable substrates.** Most Drive shares and private GitHub repos are invite-based — WebFetch can't reach them. Don't promise the fallback for invite-based shares; tell the user the truth (install the MCP).
- **`co-create` is a recognized casual synonym in natural-language requests.** The canonical verb and command name are `collaborate.md`; `co-create` only exists as an inbound-language alias for routing.
- **Don't auto-spawn agents.** Suggest at the end with generic phrasing; never reference specific agent names in the command spec.
- **Don't reference specific projects, ventures, or substrates** in templates beyond placeholders. Templates must scale across users and use cases.

# LICENSE-AUDIT — the open-core boundary, per repo and per subtree

> **What this is.** A single reference for *which license governs what* across the AIOS surface, and *where the open-core line falls* — what ships open, what stays the operator's private core, and what a company distributes under its own terms. It complements (does not replace) `LICENSE` (the GPL text), `NOTICE`, and the [Licensing section of `CONTRIBUTING.md`](./CONTRIBUTING.md#licensing). When those and this doc disagree, `LICENSE` + the manifests win — file an issue so this doc is corrected.
>
> **Audit cadence.** Re-verify on any new vendored subtree, license-manifest change, or new repo in the family. `/aios:housekeeping` Bucket 18 (upstream source freshness) is the natural trigger to re-check vendored licenses.

---

## 1. The open-core model in one picture

AIOS is **open-core**: the *framework* is open source; the operator's *content* is their private core; a *company's* distributed infra is licensed at the company's discretion.

| Layer | Repo | Open or closed | License |
|---|---|---|---|
| **Framework infra** | `The-AIOS/aios` (this repo) | **Open** | GPL-2.0-or-later (+ vendored upstreams under their own licenses — §3) |
| **Operator's vault** | operator's private repo (e.g. a personal `obsidian` repo) | **Closed** — never distributed | Operator-owned; not licensed for redistribution |
| **Company-distributed infra** | a company's `*-context` repo (mounted via `/aios:company`) | **Closed by default** — private to mounters | Company's discretion (§4) |
| **Company scaffold** | `The-AIOS/company-template` (separate repo — not in this tree) | Open (presumed) | **CONFIRM** — see §4 flag |

The line: **the framework is the open commons; the operator's second brain is the private core.** Open-core here is not a feature paywall — it's a *data* boundary. The code that makes AIOS work is fully open; what stays private is the operator's declared/observed context, projects, calendar, and exports.

---

## 2. This repo (`The-AIOS/aios`) — GPL-2.0-or-later, uniformly

The framework is **GPL-2.0-or-later** across the board. Four sources agree and must stay in sync:

- `LICENSE` — GNU GPL v2 text
- `NOTICE` — copyright + "version 2 … or (at your option) any later version"
- `.claude-plugin/marketplace.json` — `"license": "GPL-2.0-or-later"`
- `plugins/aios/.claude-plugin/plugin.json` — plugin manifest (keep `version` + `description` in sync with the marketplace entry)

Contributions to canonical are accepted under the same license (see `CONTRIBUTING.md` → Licensing).

**AIOS-authored subtrees (all GPL-2.0-or-later):** `agents/aios/`, `skills/aios/`, `plugins/aios/`, `templates/aios/`, `hooks/` (framework hooks), and the AIOS-built MCPs (§3). All docs at repo root (`README`, `SETUP`, `CLAUDE.md`, `CHEATSHEET`, `TOOLS`, `FORTRESS`, `START-HERE`, `CONTRIBUTING`, this file).

---

## 3. Vendored third-party subtrees — keep their upstream license

Vendored open-source work ships under **its own** upstream license, preserved in-folder. Never relicense by absorption; never add an upstream incompatible with GPL-2.0-or-later distribution.

### Skills

| Subtree | Origin | License | Attribution / provenance |
|---|---|---|---|
| `skills/aios/` | This framework | GPL-2.0-or-later | — |
| `skills/anthropic/` | [anthropics/skills](https://github.com/anthropics/skills) | **Apache-2.0** | Per-skill `LICENSE.txt` in each folder; `.upstream-sync` records HEAD |
| `skills/superpowers/` | [obra/superpowers](https://github.com/obra/superpowers) | **MIT** | `.upstream-sync` records HEAD |
| `skills/custom/` | Operator | Operator's choice | Survives `/aios:update`; operator owns |

> **Anthropic skills not vendored** (per `skills/anthropic/.upstream-sync`): `docx`, `pdf`, `pptx`, `xlsx` are **proprietary** (redistribution prohibited) — operators get them via the `document-skills@anthropic-agent-skills` plugin, not from this repo. `brand-guidelines` (Anthropic-specific) and `canvas-design` (Apache-2.0 but 5.5 MB of fonts) are likewise plugin-only, not vendored. **The proprietary skills are the one place "don't redistribute" bites — never copy them into this tree.**

### MCPs (per `mcps/_index.md`)

| Subtree | Origin | License |
|---|---|---|
| Google Workspace, Slack, Atlassian, GitHub, NotebookLM (`mcps/*-mcp/`) | Vendored upstream | **MIT** (each has an in-folder `LICENSE` + `.upstream-sync`) |
| Nano Banana, PDF Generator, Spotify DJ, Playwright (`mcps/*-mcp/`) | AIOS-built | **GPL-2.0-or-later** |
| `mcps/custom/` | Operator | Operator's choice |

**Rule when vendoring:** preserve the upstream `LICENSE`, attribute it in the folder, record provenance in `.upstream-sync` (`repo=`, `hash=`, `date=`), and confirm GPL-compatibility before adding.

---

## 4. Beyond this repo

### Operator's vault — the private core

The operator's Obsidian vault (declared/observed context, projects, calendar, ideas, exports) is **closed and never distributed**. It is the "core" of open-core. `CONTRIBUTING.md` → *Personal hygiene* makes the hard rule explicit: **anything that leaves the vault (a canonical PR, or company-distributed infra) must contain ZERO operator data** — no personal names in narrative, no secrets (ship `.template` + `.gitignore` the reals). Observed context is private and never committed to a shared repository.

### Company-distributed infra — company's discretion

Infra a company ships to operators who mount it (via `/aios:company --sync`) lands at namespaced paths (`agents/{company}/`, `plugins/{company}/`, `skills/{company}/`, etc.). It is **not** part of canonical and **not** GPL by default — it is licensed at the distributing company's discretion and is private to mounters. The same zero-operator-data rule applies to anything a company distributes to others.

### `company-template` — separate repo (FLAG)

`/aios:company --create` scaffolds from **`The-AIOS/company-template`**, which is a **separate repo not present in this tree**. Its license could not be verified from here.
- **Presumed:** GPL-2.0-or-later (it is framework infra published under the same org).
- **To confirm:** check that repo's `LICENSE` + manifests and record the result here. Until confirmed, treat the presumption as unverified.

---

## 5. Quick audit checklist

- [ ] `LICENSE`, `NOTICE`, `marketplace.json`, and `plugin.json` all still say GPL-2.0-or-later.
- [ ] Every vendored subtree still has its in-folder upstream `LICENSE` + `.upstream-sync`.
- [ ] No proprietary Anthropic skill (`docx`/`pdf`/`pptx`/`xlsx`/`brand-guidelines`/`canvas-design`) has been copied into `skills/anthropic/`.
- [ ] No new upstream added that is GPL-2.0-incompatible.
- [ ] `The-AIOS/company-template` license confirmed and recorded in §4.
- [ ] No operator data in any file destined to leave the vault.

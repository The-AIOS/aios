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
| **Surfaces** (how you use it) | `The-AIOS/aios-app` (desktop) · `The-AIOS/aios-glass` (editor extension) | **Open** | GPL-2.0-or-later — same terms as the framework they surface. Each carries its own `LICENSE-AUDIT.md` for its dependency tree; neither vendors third-party source |
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
| Slack, Atlassian, GitHub, NotebookLM (`mcps/*-mcp/`) | Vendored upstream | **MIT** (each has an in-folder `LICENSE` + `.upstream-sync`) |
| Google Workspace (`mcps/google-workspace-mcp/`) | **Upstream, NOT vendored** — installed from PyPI at runtime (`uvx workspace-mcp`); the folder holds only AIOS-authored config + docs | Upstream is **MIT**, but we redistribute **none** of it, so no in-folder upstream `LICENSE`/`.upstream-sync` applies. Our files in that folder: **GPL-2.0-or-later** |
| Nano Banana, PDF Generator, Spotify DJ, Playwright (`mcps/*-mcp/`) | AIOS-built | **GPL-2.0-or-later** |
| `mcps/custom/` | Operator | Operator's choice |

**Rule when vendoring:** preserve the upstream `LICENSE`, attribute it in the folder, record provenance in `.upstream-sync` (`repo=`, `hash=`, `date=`), and confirm GPL-compatibility before adding.

---

## 4. Beyond this repo

### Operator's vault — the private core

The operator's Obsidian vault (declared/observed context, projects, calendar, ideas, exports) is **closed and never distributed**. It is the "core" of open-core. `CONTRIBUTING.md` → *Personal hygiene* makes the hard rule explicit: **anything that leaves the vault (a canonical PR, or company-distributed infra) must contain ZERO operator data** — no personal names in narrative, no secrets (ship `.template` + `.gitignore` the reals). Observed context is private and never committed to a shared repository.

### Company-distributed infra — company's discretion

Infra a company ships to operators who mount it (via `/aios:company --sync`) lands at namespaced paths (`agents/{company}/`, `plugins/{company}/`, `skills/{company}/`, etc.). It is **not** part of canonical and **not** GPL by default — it is licensed at the distributing company's discretion and is private to mounters. The same zero-operator-data rule applies to anything a company distributes to others.

### `company-template` — separate repo (CONFIRMED 2026-07-30)

`/aios:company --create` scaffolds from **`The-AIOS/company-template`**, a separate repo not present in this tree. The earlier presumption is now **verified**: its `LICENSE` is **byte-identical** to this repo's GPL text (same `sha256`), and its `NOTICE` carries the *"or (at your option) any later version"* grant.

- **The template repo:** **GPL-2.0-or-later.** Framework infra, same terms as canonical. Confirmed by direct comparison, not inference.
- **A repo scaffolded FROM it:** **NOT GPL.** Its substance is the company's private business context, which falls under *Company-distributed infra — company's discretion* above. The framework does not license it and never did.

**The split, and why it needed enforcing.** Those two lines were in tension, and the tension shipped: the template's CI required a root `LICENSE`, and `/aios:company --create` cloned the repo wholesale — CI and all. So a scaffolded company repo either kept the framework's GPL at its root, **silently declaring a company's private brand/pricing/positioning material GPL-2.0 while passing CI**, or deleted it and failed the build. Compliant-and-green was unreachable. Resolved 2026-07-30 (`company-template@3003833c`):

- The template marks itself with **`.aios-template-repo`**; its CI branches on that file (not on the repo name, which would misjudge every legitimate fork).
- A scaffolded repo keeps the GPL text as **`LICENSE-TEMPLATE`** — moved, not deleted, so the scaffolding it received stays licensed and attributed — and its CI **fails** if the framework's GPL is found at the root. The root `LICENSE` slot belongs to the company: their terms, or none.
- `/aios:company --create` (Step 5) performs that rename, drops the marker, and starts a fresh git history so the GPL-at-root never enters the company's log.

*Reported by an operator reviewing the licence boundary; the contradiction was real and is the reason this entry moved from FLAG to CONFIRMED rather than just recording a licence name.*

---

## 5. Quick audit checklist

- [ ] `LICENSE`, `NOTICE`, `marketplace.json`, and `plugin.json` all still say GPL-2.0-or-later.
- [ ] Every vendored subtree still has its in-folder upstream `LICENSE` + `.upstream-sync`.
- [ ] No proprietary Anthropic skill (`docx`/`pdf`/`pptx`/`xlsx`/`brand-guidelines`/`canvas-design`) has been copied into `skills/anthropic/`.
- [ ] No new upstream added that is GPL-2.0-incompatible.
- [x] `The-AIOS/company-template` license confirmed and recorded in §4 — **GPL-2.0-or-later, verified 2026-07-30** (`LICENSE` byte-identical to this repo's). Permanently answered; the live check is the next line.
- [ ] The **template/company split** is still enforced: `company-template` ships `.aios-template-repo` + a role-aware LICENSE check, and `/aios:company --create` still renames `LICENSE` → `LICENSE-TEMPLATE`. A scaffolded company repo must never carry the framework's GPL at its root (§4).
- [ ] No operator data in any file destined to leave the vault.

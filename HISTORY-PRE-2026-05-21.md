# Pre-extraction history

The AIOS infrastructure (`commands/`, `hooks/`, `mcps/`, `plugins/`, `skills/`, `templates/`, `agents/`) evolved inside [chuycepeda/obsidian](https://github.com/chuycepeda/obsidian) from March 2026 through May 21, 2026 — before being extracted as a standalone public framework under [The-AIOS/aios](https://github.com/The-AIOS/aios) on 2026-05-21.

## Why this file exists

The extraction used a **squash-initial-commit strategy**: the first commit on `The-AIOS/aios/main` contains the entire codebase as a single snapshot, rather than replaying every historical commit. This keeps the public repo's git history clean and starting from a coherent v1.0 state.

The **full development history** — every commit, every PR, every Co-Authored-By trail — is preserved at:

> **`chuycepeda/obsidian`** (private) — original substrate from March → May 21, 2026
> **`chuycepeda/aios`** (public, archiving post-migration) — earlier public mirror that diverged into separate evolution from late April 2026
> **`sovrahq/internal-vault`** (private, archiving post-migration) — team-shared mirror used at Sovra from late April 2026

If you need to trace the lineage of a specific file or feature in this repo back to its origins, those repos hold the commit-by-commit record.

## Two predecessor repos, one canonical home

Pre-2026-05-21, AIOS infrastructure was synced across three repos in lockstep:

| Repo | Role |
|---|---|
| `chuycepeda/obsidian` | Source of truth — where infrastructure was authored |
| `chuycepeda/aios` | Public mirror — where external operators could clone |
| `sovrahq/internal-vault` | Team mirror — where Sovra teammates synced from |

The byte-identical-sync invariant across the three was load-bearing. Operationally this meant every infrastructure change shipped 3x (once per repo), with CHANGELOG entries pinned to the appropriate per-repo hash.

The 2026-05-21 migration consolidated this. The-AIOS/aios is now the **single canonical home**. The two predecessor public-facing repos (`chuycepeda/aios`, `sovrahq/internal-vault`) remain alive in read-only state pending operator confirmation of migration completion, after which they will be archived. The original substrate (`chuycepeda/obsidian`) continues to evolve as Chuy Cepeda's personal vault — extending AIOS with personal context, project notes, and addons that don't belong in the public distribution.

## Migration playbook for existing operators

If your previous `/vault-update` (now `/aios:update`) origin pointed at `chuycepeda/aios` or `sovrahq/internal-vault`, see the [first CHANGELOG entry](./CHANGELOG.md) (`2026-05-21 — Initial public release`) for the full migration playbook — `USER.md` edits + `/aios:update` re-sync against this repo.

## Post-2026-05-21 lineage

Going forward, this repo's git log is the canonical record. AIOS evolves under [The-AIOS](https://github.com/The-AIOS) with two repos as the public surface:

- **The-AIOS/aios** — the AIOS framework (this repo)
- **The-AIOS/company-template** — scaffold for mounting a company's venture context (used by `/aios:company --create`)

Plus the org profile at [The-AIOS/.github](https://github.com/The-AIOS/.github).

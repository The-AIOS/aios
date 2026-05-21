# sovrahq/internal-vault archive — pre-flight checklist

> **Sarah cannot execute this** — per SARAH.md, sarah has no access to team org repos. Buddai or Chuy runs this checklist during Thursday's Phase 1 cutover, before invoking `gh repo archive sovrahq/internal-vault`.

---

## Why this exists

The AIOS deployment plan's Phase 1 collapses three-repo sync into two-repo. `sovrahq/internal-vault` was the company-context layer; its product-infra moves to `The-AIOS/aios`, and (per current scope) its company-context folds into per-user `addons/` until Zurda's team-scope deployment forces a separate company-scope repo.

Before archive: every external reference to internal-vault needs to be redirected or accepted-as-frozen.

---

## Checklist

### 1. CI/CD references (production-blocker if missed)

- [ ] Search `sovrahq/*` repos for workflow files referencing `internal-vault`:
  ```bash
  gh search code "sovrahq/internal-vault" --owner sovrahq --extension yml,yaml --json repository,path
  ```
- [ ] Verify no GitHub Actions in `sovrahq/internal-vault` itself are queued / scheduled to fire post-archive
- [ ] Verify no external CI (e.g., Vercel deploys, Sentry source-maps uploads) authenticates against internal-vault as a secret source
- [ ] Confirm Diego + Alecs have no in-progress integration referencing internal-vault

### 2. Team-member access + in-flight work

- [ ] Announce archive in `#tech` with **24hr window** for any teammate to flag in-progress PRs / branches
- [ ] List all open PRs on internal-vault: `gh pr list -R sovrahq/internal-vault --state open`
- [ ] List all open issues on internal-vault: `gh issue list -R sovrahq/internal-vault --state open`
- [ ] If any of the above, route to closure or migration before archive
- [ ] Verify no contributor has an unpushed branch they'd lose visibility on (announcement covers this)

### 3. Forensic-recovery tags

- [ ] Capture the final pre-archive commit SHA:
  ```bash
  gh api repos/sovrahq/internal-vault --jq '.default_branch as $b | "Final SHA on \($b): " + (.commit_sha // "fetch separately")'
  cd ~/code/sovrahq/internal-vault && git log -1 --format="%H %s"
  ```
- [ ] Tag the final state for forensic-recovery purposes:
  ```bash
  cd ~/code/sovrahq/internal-vault
  git tag -a "final-pre-archive-2026-05-21" -m "Last state of sovrahq/internal-vault before archive. Successor: The-AIOS/aios."
  git push origin "final-pre-archive-2026-05-21"
  ```
- [ ] Verify the tag landed: `gh api repos/sovrahq/internal-vault/tags --jq '.[0]'`

### 4. Cross-repo reference updates

Every doc that mentions `sovrahq/internal-vault` needs review. Search across:

- [ ] `~/obsidian` (chuy's vault) — `grep -rl "sovrahq/internal-vault" ~/obsidian`
- [ ] `~/code/chuycepeda/aios` (if it exists locally on MacBook — sarah confirms it doesn't on GitHub)
- [ ] Top-level docs in `~/obsidian`: CLAUDE.md, SARAH.md, USER.md, FORTRESS.md, README.md, CHANGELOG.md
- [ ] `commands/` files that reference `.vault-update` tracker — confirm tracker URL updated to The-AIOS/aios

After replacement, run a verification grep:
```bash
grep -r "sovrahq/internal-vault" ~/obsidian --exclude-dir=.git | grep -v "_archived/" | grep -v "CHANGELOG"
# Allow CHANGELOG references — historical record
```

### 5. The `.vault-update` tracker rewire

- [ ] Update tracker URL in chuy's personal vault to `git@github.com:The-AIOS/aios.git`
- [ ] Run `/aios:update` once to verify the new sync path works
- [ ] Communicate to Zineb (and any other external user with a fork) that the upstream changed — they update their fork's tracker
- [ ] Document the URL change in CHANGELOG.md

### 6. External fork notifications (if any)

- [ ] List forks of `sovrahq/internal-vault`: `gh api repos/sovrahq/internal-vault/forks`
- [ ] If any non-Sovra forks exist, post a notification in the README of the to-be-archived repo with the new home: `The-AIOS/aios`
- [ ] Update the `chuycepeda/obsidian` README (if it surfaces internal-vault) to point to the new product repo

### 7. The archive itself

Once all above are checked:

```bash
gh repo archive sovrahq/internal-vault --yes
gh api repos/sovrahq/internal-vault --jq '{archived, archived_at, html_url}'
```

The repo becomes read-only. Forensic recovery is possible via the `final-pre-archive-2026-05-21` tag.

### 8. Post-archive validation

- [ ] Verify no team workflow broke: monitor `#tech` for 24-48hr post-archive
- [ ] Verify `/aios:update` continues working for chuy + sarah + Zineb after the rewire
- [ ] Verify the team-vault team-member list is captured (export `gh api orgs/sovrahq/teams/...members` if any team granted access via internal-vault)

---

## Rollback procedure (if archive needs to be reversed)

GitHub archive IS reversible:
```bash
gh repo unarchive sovrahq/internal-vault --yes
```

But once external references have been rewired to The-AIOS/aios, rollback re-creates the divergence. Don't unarchive lightly — only if something post-archive truly breaks that can't be fixed forward.

---

**Authored by sarah 2026-05-20 → 21 as part of AIOS deployment plan pre-flight scaffolding.**
**Executes:** buddai or chuy during Thu 2026-05-21 Phase 1 cutover.

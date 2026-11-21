---
tags:
  - aios
  - command
  - on-demand
description: Remove AIOS from this machine, guided and verifiable — inventory first, every removal shown and confirmed, the vault last, provider revocation as a checklist
allowed-tools: Read, Bash
---

# /uninstall — Remove AIOS, guided

> **Before executing:** read `USER.md` → `## Command personalizations` → `### /uninstall`.

The steps and their order are `SECURITY.md` § Uninstall; this command walks them on this machine. **It never removes anything the operator has not seen and said yes to**, and it cannot revoke anything: only each provider can.

## Rules (they outrank every step below)

1. **Read before you remove.** Step 1 only looks. Nothing is deleted until the operator has seen the full inventory.
2. **One yes per item, never a sweep.** Show the exact command for each removal, ask, run it, show the result. A yes to one item is not a yes to the next. *"Remove everything"* gets the list read back once and still a yes per group.
3. **The vault is last and separate.** `~/aios` and its remote hold the operator's notes. Never touch them without a second, explicit confirmation that names the folder, and only after a backup (step 4).
4. **No messages, no spawns.** This command never sends, posts, spawns or resumes anything, and never opens a provider page on the operator's behalf.
5. **Trash before delete** where the platform has one (`trash`, or moving into `~/.Trash` on macOS); say which you used.
6. **This session is part of what is being removed.** Plugin and hook removals take effect at the next session start; say so, and keep going in this session.

## 1. Inventory (read-only)

Detect the platform once (`uname -s`; Windows = MSYS/MINGW). Then check each item and print **present / absent** with its path. Run nothing that writes.

- **App:** `/Applications/AIOS.app` and `~/Library/Application Support/AIOS` (macOS); on Windows and Linux, say where to look rather than guessing. **Glass:** `code --list-extensions 2>/dev/null | grep -i aios`.
- **Claude Code wiring:** in `~/.claude/settings.json`, the hook commands containing `aios/hooks/`, a `statusLine` running `context-monitor.py`, and `cleanupPeriodDays`; the `settings.json.bak-aios-*` backups; `claude plugin list` for `aios@the-aios`; the links in `~/.claude/skills/` pointing into the AIOS checkout's `skills/`; `claude mcp list` for the servers AIOS registered; the `~/.aios/run` entry in `~/.claude.json`.
- **Transcripts:** count the files under `~/.claude/projects/` and their total size. Never print their contents.
- **Shell:** the `# ==== claude-spawn-wrappers` and `# ==== claude-primary-session` blocks in `~/.zshrc` / `~/.bashrc` (Windows: `$PROFILE`); exported keys there, by **name only**, never value; `~/.local/bin/aios-commit` (Windows `~/bin/aios-commit.cmd`); a `~/aios` link.
- **Background jobs:** `launchctl list | grep claude-quota-watch` (macOS), `systemctl --user list-timers | grep aios` (Linux), the `AIOS Claude Quota Watch` task (Windows); any Slack token-refresh job.
- **Local state:** `~/.aios/`.
- **Credentials on disk**, by path only, never content: `~/.google_workspace_mcp/`, `~/.workspace-mcp/`, `~/.slack-mcp-tokens.json`, `~/.slack-mcp-meta.json`, `~/.slack-mcp-workflows.json`, macOS Keychain items named `slack-mcp-server` (`security find-generic-password -s slack-mcp-server >/dev/null 2>&1`, existence only), `~/.config/aios-secrets/`, `~/.notebooklm/`, `~/.claude/spotify-cache.json`, `~/.stitch-mcp/`, `~/.claude/identities/`, `~/.claude-acct-*`, and `mcps/playwright-mcp/auth/` inside the vault.
- **The vault:** `~/aios` (real path, size, `git remote -v`, whether the working tree is clean).

Print the inventory as one list grouped like the above, absent items folded into one line per group.

## 2. Dry run

For every **present** item, print the exact command that would remove it, in `SECURITY.md`'s order, numbered. Nothing runs. Ask: *"Go through these one by one?"* Stop here on anything but yes.

## 3. Remove, one at a time

Walk the dry-run list in order. For each: show the command, ask, run on yes, show what changed (re-check present/absent). Skip on no and keep going. For `settings.json`, show the exact JSON keys being removed and write a backup beside it first. For the shell rc, remove only between the markers and show the diff.

## 4. The vault (separate confirmation)

Only after step 3, and only if the operator wants it gone. First commit or stash nothing on their behalf: say whether the tree is clean. **Back up before anything else** (`tar -czf ~/aios-backup-{date}.tar.gz -C ~ aios` with the real path), show the backup's size, then ask: *"Delete `{real path}`? It holds your notes; the backup is at {path}."* The remote is the operator's to delete on their git host; never run anything that deletes a remote.

## 5. Revoke at every provider (the operator's checklist)

Print the checklist from `SECURITY.md` § Uninstall step 8, limited to the providers the inventory found traces of. Say plainly: *until each of these is done, a copied token or cookie keeps working.* Do not open the pages; give their names.

## 6. Verify

Re-run the step 1 inventory and print what is still present, each with why (declined, failed, or the operator's to do). **Present nothing as removed that the re-check did not confirm.**

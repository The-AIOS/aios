# Spawn Wrapper — Troubleshooting (Claude-facing runbook)

> This file is for a **Claude session** diagnosing a broken `spawn`. The operator should never have to edit the wrapper — read this, identify the failure class, and fix it for them.

## How the IDE spawn works (so you can reason about failures)

When `spawn <name>` runs inside an IDE (Antigravity / VS Code / Cursor), the wrapper drives the IDE via AppleScript to: **(1)** force the IDE frontmost, **(2)** open the Command Palette (`⌘⇧P`), **(3)** *paste* `Terminal: Create New Terminal` + Enter to create a terminal, **(4)** a defensive Enter to dismiss any shell-picker, **(5)** *paste* the launcher path + Enter to run it. The launcher (`/tmp/spawn-launch-<name>.sh`) sources the shell, `cd`s to the vault, and starts `_claude_with_respawn`.

**Two deliberate design choices — do not "simplify" them back:**
- **Paste, never type, the command + launcher.** `keystroke "<text>"` mis-maps on non-US keyboard layouts (Spanish LA/ES and others): the backtick chord doesn't fire and symbols/spaces garble. Clipboard paste (`⌘V` — a letter chord) delivers bytes intact on *any* layout. Validated US/ABC + Latin American + Spanish-ISO (2026-06-14). See antifragile #73.
- **`set frontmost to true` before keystrokes.** `activate` alone loses the race when another window/app holds focus at spawn time (operator typing in another terminal, or in Chrome) — keystrokes then leak into the wrong place. The forced frontmost guarantees the IDE catches them.

The wrapper saves + restores the operator's clipboard around the spawn, so spawning doesn't eat what they had copied.

Glass-shell spawns **natively** (node-pty) and never uses this AppleScript path — none of this applies there.

## Symptom → diagnosis

**"My active tab got renamed to the agent name and the launcher text spilled into my session; no new terminal/session appeared."**
This is the leak signature — keystrokes landed in the wrong place. Check, in order:
1. **Stale wrapper.** Did the operator's `~/.zshrc` predate the palette+paste fix? Run `grep -c "Terminal: Create New Terminal" ~/.zshrc` (expect ≥1) and `grep -c 'control down, shift down' ~/.zshrc` (expect 0 — a hit means the legacy keystroke-create is still installed). Fix: re-run `bash ~/aios/hooks/claude-identity/install-wrappers.sh`, open a new terminal.
2. **Focus race / wrong IDE detected.** Inspect the generated `/tmp/spawn-script-<name>.applescript` — does the bundle ID match the running IDE? Antigravity's System-Events process name is stock `Electron`, so it must be addressed by bundle id (`com.google.antigravity-ide`), not name. If the operator runs a different IDE, confirm detection in the wrapper's `pgrep` block.
3. **Keyboard layout (legacy wrapper only).** If they're on a stale wrapper AND a non-US layout, that's the original bug — the palette+paste version is immune. Re-install (step 1) resolves it.

**"Nothing happened at all — no terminal, no leak."**
Usually focus: the IDE wasn't frontmost and `set frontmost to true` couldn't pull it (rare — e.g. a modal dialog open, or Accessibility permission missing). Check **System Settings → Privacy & Security → Accessibility** — the terminal/IDE running the spawn needs permission to control the computer (System Events). Without it, AppleScript keystrokes silently no-op.

**"Spawn works when I run it, fails when Claude spawns from a background session."**
Same focus class — fixed by `set frontmost to true`. If still failing, the Accessibility-permission check above is the next suspect.

## Verifying a fix
Run a throwaway spawn and confirm a named session launched, then kill it:
```bash
spawn difftest "Reply 'ok' then stop."
sleep 11 && pgrep -fl "remote-control --name difftest"   # a PID line = success
spawn-kill difftest
```
Test on the operator's *actual* keyboard layout — that's where layout bugs surface (don't validate only on US/ABC).

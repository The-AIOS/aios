#!/bin/bash
# install-wrappers.sh — idempotent installer for the spawn / _claude_with_respawn wrappers
#
# What this does:
# 1. Detects rc file ($HOME/.zshrc or $HOME/.bashrc)
# 2. Backs it up with a timestamped filename
# 3. Strips old _claude_with_respawn(), buddai(), spawn() function definitions
# 4. Appends the canonical wrapper block (resilient version with circuit-breaker,
#    parallel-spawn lock, $ide_app fix, launcher-script pattern)
# 5. Sources the rc file in-place verification
# 6. Verifies via declare -f
#
# Safe to re-run. If an old version exists, it's stripped before reinstall —
# no duplicate function definitions. The backup file lets you roll back.
#
# Updated: 2026-05-06 — see CHANGELOG.md "spawn / _claude_with_respawn:
# kill the silent-session-loss bug" for the rationale.

set -e  # Exit on any error (except where we explicitly check)

# ---- Detect rc file ----
# Use $SHELL (the user's LOGIN shell) not $BASH_VERSION (which reflects the
# script's runtime shell — always bash here because of the #!/bin/bash shebang).
# This script may be invoked via bash even on a zsh user's machine.
case "$(basename "${SHELL:-/bin/zsh}")" in
  zsh)  RC="$HOME/.zshrc"  ;;
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="$HOME/.zshrc"  ;;  # macOS default; safer than .profile
esac

if [ ! -f "$RC" ]; then
  echo "⚠️  No rc file at $RC — but \$SHELL says you use $(basename "${SHELL:-zsh}")." >&2
  echo "    This is unusual. Aborting to avoid creating an empty $RC." >&2
  echo "    If you really want to create $RC, touch it first then re-run." >&2
  exit 1
fi

# ---- Backup ----
BACKUP="${RC}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$RC" "$BACKUP"
echo "✓ Backup: $BACKUP"

# ---- Strip old wrapper content ----
# Two patterns covered to handle both first-time install (inline function
# definitions) AND re-runs (banner-wrapped blocks from a previous install):
#   1. Banner block: `# ==== claude-spawn-wrappers …` through `# ==== END …`
#   2. Inline function defs: matched function-name { ... }
# Uses awk because sed range patterns are fragile across BSD/GNU implementations.
awk '
  /^# ==== claude-spawn-wrappers/,/^# ==== END claude-spawn-wrappers/ { next }
  /^_claude_with_respawn[[:space:]]*\(\)[[:space:]]*\{/,/^\}$/        { next }
  /^buddai[[:space:]]*\(\)[[:space:]]*\{/,/^\}$/                      { next }
  /^spawn[[:space:]]*\(\)[[:space:]]*\{/,/^\}$/                       { next }
  { print }
' "$RC" > "${RC}.tmp"

# Trim trailing blank lines so the appended banner block starts cleanly.
# (BSD sed compatible — chains delete-empty-tail until no change.)
awk 'NF { p = 1 } p { lines[++n] = $0 } END {
  while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
  for (i = 1; i <= n; i++) print lines[i]
}' "${RC}.tmp" > "${RC}.tmp2"
mv "${RC}.tmp2" "$RC"
rm -f "${RC}.tmp"
echo "✓ Stripped old wrapper content (banner blocks + inline functions, if any)"

# ---- Append new wrapper block ----
cat >> "$RC" << 'WRAPPER'

# ==== claude-spawn-wrappers (managed by hooks/claude-identity/install-wrappers.sh) ====
# Re-run that script to update. Don't hand-edit between this banner and the
# matching END banner — your changes will be wiped on the next install.
_claude_with_respawn() {
  local name="${1:?Usage: _claude_with_respawn <name> [bootstrap] [initial-session-id]}"
  local bootstrap="${2:-}"
  local initial_sid="${3:-}"
  # Use ARRAY for resume args (portable bash + zsh). Unquoted string $resume_flag
  # would word-split in bash but NOT in zsh (default) — zsh would pass the whole
  # "--resume <uuid>" as ONE option-name, and claude would error with
  # "unknown option '--resume <uuid>'". Array expansion "${resume_args[@]}"
  # is portable across both shells.
  local -a resume_args
  [ -n "$initial_sid" ] && resume_args=(--resume "$initial_sid")

  # Model selection — AIOS defaults to 1M-context Opus because the framework
  # leans heavily on context engineering (full vault + observed context +
  # command spec + personalization per /aios:today ≈ 125k chars; max-context
  # is the right default). Override via $CLAUDE_MODEL env var for cheaper
  # Sonnet sessions, 3P providers (Bedrock/Vertex), or non-1M Opus.
  # Examples:
  #   (default — no setup needed)                 # claude-opus-4-7[1m] — 1M context Opus
  #   export CLAUDE_MODEL='claude-sonnet-4-6'     # cheaper Sonnet sessions
  #   export CLAUDE_MODEL='opus'                  # alias for latest base Opus (no [1m])
  #   export CLAUDE_MODEL='sonnet'                # alias for latest Sonnet
  # Why hardcoded default + env override (not just env-only): /config and
  # /model are session-scoped — they don't persist to settings.json or
  # propagate to spawned children. Without an explicit --model flag, every
  # spawn falls back to whatever ~/.claude/settings.json `model` key says,
  # which is often base Opus even when the operator wants 1M.
  local model_to_use="${CLAUDE_MODEL:-claude-opus-4-7[1m]}"
  local -a model_args=(--model "$model_to_use")

  export CLAUDE_AGENT_NAME="$name"
  export CLAUDE_RESPAWN_CAPABLE=1
  local marker="/tmp/swap-respawn-$name.flag"
  local sid_file="/tmp/swap-respawn-$name.session"
  local consecutive_failures=0

  while true; do
    if [ -n "$bootstrap" ]; then
      claude "${model_args[@]}" "${resume_args[@]}" --remote-control --name "$name" "$bootstrap"
    else
      claude "${model_args[@]}" "${resume_args[@]}" --remote-control --name "$name"
    fi
    local exit_code=$?

    # Branch 1: account-swap-triggered respawn (marker file present).
    if [ -f "$marker" ]; then
      local sid="$(cat "$sid_file" 2>/dev/null)"
      rm -f "$marker" "$sid_file"
      if [ -z "$sid" ]; then
        echo ""
        echo "⚠️  Account swap fired but session-id was empty/missing."
        echo "    Falling back to fresh start — terminal preserved."
        resume_args=()
        bootstrap=""
        consecutive_failures=$((consecutive_failures + 1))
      else
        echo ""
        echo "🔄 Account swap detected. Resuming session $sid in 3s…"
        resume_args=(--resume "$sid")
        bootstrap="Read /tmp/resume-prompt-$name.md and follow the instructions inside."
        consecutive_failures=0
      fi
      sleep 3
      continue
    fi

    # Branch 2: clean exit, no swap marker (user typed /exit, exit, or Ctrl+D).
    if [ $exit_code -eq 0 ]; then
      break
    fi

    # Branch 3: unexpected non-zero exit, no swap marker.
    consecutive_failures=$((consecutive_failures + 1))
    echo ""
    echo "⚠️  Claude exited with code $exit_code (no swap marker)."
    echo "    Last command: claude ${model_args[*]} ${resume_args[*]} --remote-control --name $name"
    echo "    Likely: auth issue, malformed session-id, network, or transient error."
    echo "    Consecutive failures: $consecutive_failures"
    echo ""
    if [ $consecutive_failures -ge 3 ]; then
      echo "    🛑 Three consecutive failures. Stopping respawn loop to avoid runaway."
      echo "       Manual recovery: claude --remote-control --name $name"
      break
    fi
    echo "    Press Enter to retry FRESH (clears resume flag),"
    echo "    'r' + Enter to retry SAME (keeps current resume flag),"
    echo "    'q' + Enter to exit, or wait 60s for auto-fresh-retry."
    local response=""
    read -t 60 response
    if [ "$response" = "q" ]; then
      break
    elif [ "$response" = "r" ]; then
      :  # keep resume_args + bootstrap as-is
    else
      resume_args=()
      bootstrap=""
    fi
    sleep 2
  done
}

buddai() {
  _claude_with_respawn buddai
}

_spawn_adj_animal() {
  local adjs="amber bold calm clever fierce gentle jolly nimble swift wise"
  local animals="badger eagle falcon fox lynx otter owl raven sparrow wolf"
  local num_adj=$(echo "$adjs" | wc -w | tr -d ' ')
  local num_animal=$(echo "$animals" | wc -w | tr -d ' ')
  # Use /dev/urandom for true entropy. $RANDOM's auto-seed (PID+time) can collide
  # across rapid shell launches — same first value across fresh shells.
  local rand_adj=$(od -An -N2 -d /dev/urandom | tr -d ' ')
  local rand_animal=$(od -An -N2 -d /dev/urandom | tr -d ' ')
  local adj=$(echo "$adjs" | tr ' ' '\n' | sed -n "$((rand_adj % num_adj + 1))p")
  local animal=$(echo "$animals" | tr ' ' '\n' | sed -n "$((rand_animal % num_animal + 1))p")
  echo "${adj}-${animal}"
}

spawn() {
  local name="$1"
  local task="${2:-Start session.}"

  # Empty name → generate adj-animal handle + print onboarding tip
  if [ -z "$name" ]; then
    name=$(_spawn_adj_animal)
    echo "[spawn] No name given — using handle: $name"
    echo "[spawn] Tip: name a specific agent for matched expertise (e.g. \`spawn accountant\`)."
    echo "[spawn] See agents/_index.md for the full list."
    echo "[spawn] Opening session: $name"
  fi

  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "⚠️  spawn: invalid session name '$name'. Use only letters, digits, _, -" >&2
    return 1
  fi

  local task_file="/tmp/spawn-task-$name.md"
  printf '%s\n' "$task" > "$task_file"

  local launcher="/tmp/spawn-launch-$name.sh"
  cat > "$launcher" <<LAUNCHER
#!/bin/zsh
[ -f ~/.zshrc ] && source ~/.zshrc
cd ~/aios 2>/dev/null
_claude_with_respawn '$name' 'Read $task_file and follow the instructions inside.'
LAUNCHER
  chmod +x "$launcher"

  if [ -n "$CLAUDECODE" ]; then
    (
      local lockdir="/tmp/spawn.lock.d"
      local waited=0
      while ! mkdir "$lockdir" 2>/dev/null; do
        sleep 0.5
        waited=$((waited + 1))
        if [ $waited -gt 60 ]; then
          echo "⚠️  spawn: stale lock detected (>30s); reclaiming." >&2
          rm -rf "$lockdir"
        fi
      done
      trap "rmdir '$lockdir' 2>/dev/null" EXIT

      local ide_app=""
      # Antigravity IDE (post-2026-05 update — new app bundle "Antigravity IDE.app") takes
      # precedence over legacy "Antigravity.app" (now an empty shell on updated machines).
      # pgrep -q "Antigravity" matches BOTH names by substring, so we must check the more
      # specific name first or the AppleScript targets the wrong app.
      # Use `pgrep -x` (exact match) for Antigravity + Cursor — `-q`
      # was substring-matching the macOS text-input helper
      # `CursorUIViewService` and (potentially) any process containing
      # "Antigravity" as a substring. Fix originally landed Apr 22 in
      # legacy claude-identity (commit c4b89bd) — never ported when the
      # wrapper consolidated into install-wrappers.sh; regression caught
      # 2026-05-22 on sarah. VS Code keeps `-qf` because "Visual Studio
      # Code" lives in args, not in the process name.
      pgrep -xq "Antigravity IDE" && ide_app="Antigravity IDE"
      [ -z "$ide_app" ] && pgrep -xq "Antigravity" && ide_app="Antigravity"
      [ -z "$ide_app" ] && pgrep -qf "Visual Studio Code" && ide_app="Visual Studio Code"
      [ -z "$ide_app" ] && pgrep -xq "Cursor" && ide_app="Cursor"

      if [ -n "$ide_app" ]; then
        # AppleScript pattern: Ctrl+Shift+\` to create a new terminal, then
        # Cmd+Shift+P → "Terminal: Rename" to rename. This is the proven
        # April 25 → early May pattern that worked across all spawned tabs.
        #
        # Why Ctrl+Shift+\` works: in VS Code / Antigravity / Cursor, this
        # shortcut is bound to the workbench command "workbench.action.terminal.new"
        # — i.e. CREATE new terminal. It is workbench-level (focus-independent),
        # which means it fires correctly even when the chat panel has focus.
        # NOTE: Ctrl+\` (without Shift) is "toggle terminal panel" — different
        # action; do not substitute.
        #
        # After step 1, focus is in the just-created terminal, so Cmd+Shift+P
        # opens the command palette reliably from terminal-focus state.
        #
        # Menu-bar invocation (\`click menu item "New Terminal"\`) doesn't work
        # on Antigravity — the menu bar has no "Terminal" menu with that item.
        # The keystroke shortcut is more portable across VS Code-family IDEs.
        local applescript_file="/tmp/spawn-script-$name.applescript"
        cat > "$applescript_file" <<APPLESCRIPT
tell application "$ide_app" to activate
delay 0.5
tell application "System Events"
  tell process "$ide_app"
    -- Step 1: Create a NEW terminal via Ctrl+Shift+\` (workbench shortcut,
    -- focus-independent — workbench.action.terminal.new in VS Code-family IDEs).
    keystroke "\`" using {control down, shift down}
    delay 0.8
    -- Defensive: if Antigravity shows a shell-picker on first terminal creation,
    -- Enter selects the default. Harmless if no picker appears (just emits an
    -- empty newline at the fresh terminal's prompt).
    keystroke return
    delay 1

    -- Step 2: Rename the new terminal via command palette. Focus is now in
    -- the just-created terminal, so Cmd+Shift+P opens the palette reliably.
    keystroke "P" using {command down, shift down}
    delay 0.5
    keystroke "Terminal: Rename"
    delay 0.5
    keystroke return
    delay 0.3
    keystroke "$name"
    keystroke return
    delay 1

    -- Step 3: Run the launcher (short path → safe to keystroke once we're
    -- in the just-created, named terminal).
    keystroke "$launcher"
    delay 0.3
    keystroke return
  end tell
end tell
APPLESCRIPT
        osascript "$applescript_file"
      else
        osascript -e "tell application \"Terminal\" to do script \"$launcher\""
      fi
    )
  else
    _claude_with_respawn "$name" "Read $task_file and follow the instructions inside."
  fi
}

spawn-kill() {
  # Kill a spawned worker session cleanly.
  #
  # Why process-group kill (not single-PID kill): the spawn wrapper runs
  # _claude_with_respawn inside a parent zsh that lives in the spawned tab.
  # That zsh is the respawn loop body — if you SIGKILL only the named claude
  # process, the loop respawns a fresh claude (defeating the kill), and if you
  # close the window mid-loop, Terminal pops a "terminate running processes?"
  # modal because the launcher zsh is still alive. If you click "Terminate" on
  # that modal it kills the zsh but leaves claude as an orphan reparented to
  # launchd — silent leak.
  #
  # Killing the process GROUP (PGID) takes down launcher-zsh + claude +
  # recovery prompt + any descendants atomically. No respawn, no modal, no
  # orphan. Per antifragile #50 (May 17) + #53 (May 18 — three-step plugin
  # uninstall) — runtime state requires explicit teardown, not just a PID kill.
  local name="${1:?Usage: spawn-kill <session-name>}"
  local claude_pid pgid tty

  # NOTE: ".*" between "claude" and "--remote-control" tolerates flags injected
  # between them (e.g. "--model claude-opus-4-7[1m]" from the model-selection
  # block above). Without the wildcard, this pgrep silently fails to find any
  # spawn launched after the model flag landed — leaving orphan processes.
  # Caught 2026-05-22 during testing-day end-to-end run.
  claude_pid=$(pgrep -f "claude .*--remote-control --name $name" | head -1)
  if [ -z "$claude_pid" ]; then
    echo "[spawn-kill] no claude process found for '$name'" >&2
    rm -f "/tmp/spawn-task-$name.md" "/tmp/spawn-launch-$name.sh" "/tmp/spawn-script-$name.applescript" 2>/dev/null
    return 1
  fi

  pgid=$(ps -o pgid= -p "$claude_pid" | tr -d ' ')
  tty=$(ps -o tty= -p "$claude_pid" | tr -d ' ')

  kill -KILL -- -"$pgid" 2>/dev/null
  sleep 0.3

  # macOS only: close the Terminal.app window for this TTY (modal-free now
  # that the process group is gone). No-op on Linux or when the session ran
  # inside an IDE-integrated terminal (the IDE manages tab lifecycle).
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "tell application \"Terminal\"
      set wList to every window
      repeat with w in wList
        try
          set t_tty to tty of (first tab of w)
          if t_tty contains \"$tty\" then close w saving no
        end try
      end repeat
    end tell" 2>/dev/null
  fi

  # Clean tmp artifacts so the next \`spawn $name\` starts fresh
  rm -f "/tmp/spawn-task-$name.md" "/tmp/spawn-launch-$name.sh" "/tmp/spawn-script-$name.applescript" 2>/dev/null

  echo "[ok] killed '$name' (PID $claude_pid, PGID $pgid, $tty)"
}
# ==== END claude-spawn-wrappers ====
WRAPPER

echo "✓ Appended new wrapper block to $RC"

# ---- Verify by inspecting rc file content ----
# Why we don't use `declare -f` here: this installer runs in bash (per the
# shebang), but $RC is the user's LOGIN shell rc — typically zsh. zsh-specific
# syntax in zshrc (autoload, compinit, [[ ... = (...) ]] glob pattern matching)
# triggers parse errors when bash tries to source it, aborting before the
# wrapper definitions at the bottom of the file are reached. Result: previous
# verification gave false negatives even when the wrapper was correctly written.
# Verifying file content side-steps the cross-shell-sourcing problem entirely.
RESPAWN_OK=0
SPAWN_OK=0
grep -q "consecutive_failures" "$RC" && RESPAWN_OK=1
grep -q "spawn.lock.d" "$RC" && SPAWN_OK=1
grep -q "^_claude_with_respawn[[:space:]]*\(\)" "$RC" && RESPAWN_FN_OK=1 || RESPAWN_FN_OK=0
grep -q "^spawn[[:space:]]*\(\)" "$RC" && SPAWN_FN_OK=1 || SPAWN_FN_OK=0

echo ""
echo "Verification (rc-content check):"
echo "  _claude_with_respawn() defined: $RESPAWN_FN_OK (expect 1)"
echo "  spawn() defined: $SPAWN_FN_OK (expect 1)"
echo "  consecutive_failures circuit-breaker present: $RESPAWN_OK (expect 1)"
echo "  spawn.lock.d parallel-spawn lock present: $SPAWN_OK (expect 1)"
echo ""

if [ "$RESPAWN_FN_OK" = "1" ] && [ "$SPAWN_FN_OK" = "1" ] && [ "$RESPAWN_OK" = "1" ] && [ "$SPAWN_OK" = "1" ]; then
  echo "✓ Wrappers installed successfully."
  echo ""
  echo "Next steps:"
  echo "  • In any EXISTING terminal you want to keep, run: source $RC"
  echo "  • New terminals pick up the new wrappers automatically."
  echo "  • Backup at $BACKUP if you need to roll back."
  exit 0
else
  echo "⚠️  Verification failed. Restoring backup and exiting." >&2
  cp "$BACKUP" "$RC"
  echo "    Restored $RC from $BACKUP" >&2
  exit 1
fi

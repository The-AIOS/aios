# install-wrappers.ps1 -- idempotent installer for spawn / Invoke-ClaudeWithRespawn (Windows port)
#
# Parallel to install-wrappers.sh (macOS / Linux). Same shape, same safety
# properties: timestamped backup, strip prior wrapper block, append canonical
# version, content-verify, auto-rollback on failure.
#
# What this does:
# 1. Detects $PROFILE (pwsh -> Documents\PowerShell\..., Windows PowerShell 5.1
#    -> Documents\WindowsPowerShell\...). Resolves automatically per shell.
# 2. Backs it up with a timestamped filename.
# 3. Strips any prior wrapper block (banner-wrapped block + inline function defs).
# 4. Appends the canonical wrapper block (Invoke-ClaudeWithRespawn + spawn).
# 5. Dot-sources the profile in-place to apply.
# 6. Verifies by content check (looks for canonical markers in the profile).
# 7. Auto-rolls back to backup on verification failure.
#
# Safe to re-run. The wrapper logic itself is byte-identical to what's been
# stable since the W19 cross-platform expansion bundle (b3bbb05), so re-running
# on a working Windows environment is a no-op -- the strip-then-append produces
# the same final content.
#
# Usage:
#   pwsh -File hooks\claude-identity\install-wrappers.ps1
#   # or, from Windows PowerShell 5.1:
#   powershell -ExecutionPolicy Bypass -File hooks\claude-identity\install-wrappers.ps1
#
# ASCII-only on purpose. Windows PowerShell 5.1 reads .ps1 files in the
# system ANSI codepage when no BOM is present, so a UTF-8 glyph like a
# checkmark U+2713 (bytes E2 9C 93) gets misread as a smart-quote and
# breaks string parsing on this and following lines. Use plain ASCII in
# Write-Host strings and comments. If you must add a non-ASCII char,
# save the file with a UTF-8 BOM.

$ErrorActionPreference = 'Stop'

# ---- Detect primary session name ----
# Read from USER.md ## Identity table (first session-name row). If USER.md
# doesn't exist yet OR has no identity entries (fresh-clone pre-cold-start),
# fall back to "aios" -- the framework's own name, a non-colliding placeholder.
# (NOT "claude": a claude() shell function would shadow the Claude Code CLI
# binary at the user prompt, so typing `claude` would launch a named session
# instead of bare Claude Code -- and a kill could take down a plain claude
# session. Naming the fallback "aios" keeps bare `claude` always-plain.)
# Operator can re-run this script after personalizing USER.md.
function Get-PrimarySessionName {
    $userMd = Join-Path $HOME 'aios\USER.md'
    if (-not (Test-Path $userMd)) { return 'aios' }
    $inSection = $false
    foreach ($line in Get-Content $userMd) {
        if ($line -match '^## Identity') { $inSection = $true; continue }
        if ($inSection -and $line -match '^## ') { break }
        # Backtick-OPTIONAL: matches both | `name` | (vault format) and | name |
        # (README example format). A strict backtick-required match silently fell
        # back to the placeholder for operators who followed the README's plain
        # format -- see CHANGELOG "install-wrappers: backtick-optional USER.md parse."
        if ($inSection -and $line -match '^\|\s*`?([^`|]+?)`?\s*\|') {
            $candidate = $Matches[1].Trim()
            # Skip header/separator rows (| Name | / | --- |)
            if ($candidate -and $candidate -notmatch '^(Name|[\s\-]+)$') {
                return $candidate
            }
        }
    }
    return 'aios'
}

$PRIMARY_NAME = Get-PrimarySessionName
$primarySource = if ($PRIMARY_NAME -eq 'aios') { 'fallback -- set in USER.md to customize, then re-run' } else { 'from USER.md' }
Write-Host "[ok] Primary session name: $PRIMARY_NAME ($primarySource)"

# ---- Detect profile ----
# $PROFILE auto-resolves to the right path for the current PowerShell edition
# (pwsh = Documents\PowerShell\Microsoft.PowerShell_profile.ps1,
#  Windows PowerShell 5.1 = Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1).
$RC = $PROFILE
if (-not (Test-Path $RC)) {
    New-Item -Path $RC -ItemType File -Force | Out-Null
    Write-Host "[ok] Created $RC (didn't exist)"
} else {
    Write-Host "[ok] Profile: $RC"
}

# ---- Backup ----
$BACKUP = "$RC.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Path $RC -Destination $BACKUP -Force
Write-Host "[ok] Backup: $BACKUP"

# ---- Strip old wrapper content ----
# Two patterns covered: banner-wrapped block (from previous installer runs),
# and inline function defs (from first-time manual install).
$content = Get-Content $RC -Raw -ErrorAction SilentlyContinue
if (-not $content) { $content = '' }

# Strip banner block: # ==== claude-spawn-wrappers ... # ==== END claude-spawn-wrappers
$content = [regex]::Replace(
    $content,
    '(?s)# ==== claude-spawn-wrappers.*?# ==== END claude-spawn-wrappers ====\r?\n?',
    ''
)

# Strip banner block: # ==== claude-primary-session ... # ==== END claude-primary-session
# Banner-wrapping the dynamic primary-session function lets re-installs cleanly
# strip it regardless of the previous primary-session name -- handles rename
# N->N+1 without leaving orphan function definitions in the profile.
$content = [regex]::Replace(
    $content,
    '(?s)# ==== claude-primary-session.*?# ==== END claude-primary-session ====\r?\n?',
    ''
)

# Strip inline function defs (no banner) -- only matches well-formed function blocks.
# These are the legacy-strip pass for any old installs that didn't use banners
# yet. Safe no-op if not present.
$stripFns = @('Invoke-ClaudeWithRespawn', 'spawn', 'spawn-kill')
foreach ($fn in $stripFns) {
    $content = [regex]::Replace(
        $content,
        "(?sm)^function\s+$fn\s*\{.*?^\}\r?\n?",
        ''
    )
}

# Trim trailing blank lines so the appended banner block starts cleanly.
$content = $content -replace '(\r?\n)+$', "`n"
Set-Content -Path $RC -Value $content -NoNewline -Encoding UTF8
Write-Host "[ok] Stripped old wrapper content (banner blocks + inline functions, if any)"

# ---- Append new wrapper block ----
$WRAPPER = @'

# ==== claude-spawn-wrappers (managed by hooks/claude-identity/install-wrappers.ps1) ====
# Re-run that script to update. Don't hand-edit between this banner and the
# matching END banner -- your changes will be wiped on the next install.

# Invoke-ClaudeWithRespawn -> run claude with auto-respawn after quota swaps.
# When the autopilot rotates accounts, it terminates claude and writes
# $env:TEMP/swap-respawn-<Name>.{flag,session}. The loop sees the marker and
# re-launches `claude --resume <uuid>` in the SAME terminal tab.
# CLAUDE_RESPAWN_CAPABLE=1 tells _resume.py to use the in-place path
# instead of legacy keystroke routing.
function Invoke-ClaudeWithRespawn {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $BootstrapFile = '',
        [string] $InitialSessionId = ''
    )
    $env:CLAUDE_AGENT_NAME = $Name
    $env:CLAUDE_RESPAWN_CAPABLE = '1'
    # A spawned worker is an INDEPENDENT named session, not a sub-agent child. Clear any
    # inherited CLAUDE_CODE_CHILD_SESSION marker (which turns off transcript saving AND the
    # session-registry entry that AIOS Glass's Running card reads) and force persistence, so
    # every worker is a first-class, resumable, Glass-visible session. (2026-07-23)
    $env:CLAUDE_CODE_CHILD_SESSION = $null
    $env:CLAUDE_CODE_FORCE_SESSION_PERSIST = '1'
    $marker  = Join-Path $env:TEMP "swap-respawn-$Name.flag"
    $sidFile = Join-Path $env:TEMP "swap-respawn-$Name.session"
    $resumeArgs = @()
    if ($InitialSessionId -eq '--continue') { $resumeArgs = @('--continue') }
    elseif ($InitialSessionId) { $resumeArgs = @('--resume', $InitialSessionId) }
    # Model selection — AIOS default is 1M-context Opus (see install-wrappers.sh
    # comment for the why). Override via $env:CLAUDE_MODEL (Sonnet, 3P, etc.).
    $modelToUse = if ($env:CLAUDE_MODEL) { $env:CLAUDE_MODEL } else { 'claude-opus-4-8[1m]' }
    $modelArgs = @('--model', $modelToUse)
    # Resolve the claude EXECUTABLE explicitly (not via function lookup) to
    # avoid recursion if the operator NAMES their session "claude" in USER.md —
    # then `function claude { Invoke-ClaudeWithRespawn ... }` is defined and a
    # bare `& claude` would re-resolve to the function. (The default fallback is
    # now "aios", which never shadows the CLI — see Get-PrimarySessionName;
    # this guard now covers only the explicit "claude" session-name edge case.)
    # Get-Command -CommandType Application forces PATH-binary resolution.
    # Mirrors the `command claude` guard in install-wrappers.sh.
    # CAUTION: npm on Windows installs BOTH claude.cmd AND an extensionless
    # Unix shim 'claude' into %AppData%\Roaming\npm\ — Get-Command matches
    # both, .Source becomes a 2-element array, and `& $claudeExe` collapses
    # it into one bogus path -> CommandNotFoundException (spawn/zai dead).
    # Resolve deterministically: prefer .cmd, then .exe, then .bat; fall
    # back to first match. (Reported via internal review 2026-06-02.)
    $claudeCmds = @(Get-Command -Name 'claude' -CommandType Application -ErrorAction Stop)
    $claudeExe = $null
    foreach ($ext in @('\.cmd$', '\.exe$', '\.bat$')) {
        $hit = $claudeCmds | Where-Object { $_.Source -match $ext } | Select-Object -First 1
        if ($hit) { $claudeExe = $hit.Source; break }
    }
    if (-not $claudeExe) { $claudeExe = $claudeCmds[0].Source }
    while ($true) {
        $claudeArgs = @() + $modelArgs + $resumeArgs + @('--remote-control', '--name', $Name)
        if ($BootstrapFile -and (Test-Path $BootstrapFile)) {
            $claudeArgs += "Read $BootstrapFile and follow the instructions inside."
        }
        & $claudeExe @claudeArgs
        if (Test-Path $marker) {
            $sid = ''
            if (Test-Path $sidFile) { $sid = (Get-Content $sidFile -Raw).Trim() }
            Remove-Item $marker, $sidFile -Force -ErrorAction SilentlyContinue
            if (-not $sid) { break }
            $resumeArgs    = @('--resume', $sid)
            $BootstrapFile = Join-Path $env:TEMP "resume-prompt-$Name.md"
            Start-Sleep -Seconds 3
        } else {
            break
        }
    }
}

# spawn [Name] [Task] -> named worker session with optional task assignment.
# Inside an active Claude session: opens a new Windows Terminal tab named after
# the worker (falls back to a plain pwsh/powershell window if wt.exe is missing).
# In a clean terminal: runs in place. Either way the new shell calls
# Invoke-ClaudeWithRespawn so it survives quota swaps without losing its tab.
#
# IDE-integrated tabs (the macOS osascript path that opens a tab inside
# VS Code/Cursor) are intentionally not implemented on Windows: SendKeys
# is focus-bound and IDE chat panels eat workbench shortcuts, so the
# keystroke trick is unreliable. External Windows Terminal is the deliberate
# Windows tradeoff -- with foreground-stealing handled below.
function Get-SpawnAdjAnimal {
    $adjs = 'amber','bold','calm','clever','fierce','gentle','jolly','nimble','swift','wise'
    $animals = 'badger','eagle','falcon','fox','lynx','otter','owl','raven','sparrow','wolf'
    # Guid-based seed for true entropy. Get-Random's default tick-count seed
    # can collide across rapid PowerShell launches.
    $rng = [System.Random]::new([System.Guid]::NewGuid().GetHashCode())
    $adj = $adjs[$rng.Next($adjs.Length)]
    $animal = $animals[$rng.Next($animals.Length)]
    return "$adj-$animal"
}

function spawn {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)] [string] $Name,
        [Parameter(Position=1)] [string] $Task = 'Start session.',
        # -Tier mechanical|judgment. mechanical routes to the SECOND-BEST model
        # (cheaper; "always aim second-best" auto-tracks the lineup). judgment/none
        # keeps the frontier default (Invoke-ClaudeWithRespawn's CLAUDE_MODEL fallback).
        # ValidateSet rejects unknown tiers for free.
        [ValidateSet('mechanical','judgment')] [string] $Tier,
        # -Model <id> overrides -Tier; pins an explicit/specialist model (e.g.
        # claude-fable-5) per-spawn with NO global env mutation (set for the call
        # only, then restored below).
        [string] $Model
    )

    # Tier -> model id. $null = no override -> frontier default. Second-best = Sonnet 4.6.
    $spawnModel = if ($Tier -eq 'mechanical') { 'claude-sonnet-4-6' } else { $null }
    # -Model overrides -Tier: pin an explicit model outside the tier ladder.
    if ($Model) { $spawnModel = $Model }

    # Empty name -> generate adj-animal handle + print onboarding tip
    if ([string]::IsNullOrEmpty($Name)) {
        $Name = Get-SpawnAdjAnimal
        Write-Host "[spawn] No name given -- using handle: $Name"
        Write-Host "[spawn] Tip: name a specific agent for matched expertise (e.g. ``spawn accountant``)."
        Write-Host "[spawn] Tip: add ``-Tier mechanical`` for cheap/mechanical work (ingests, sweeps); omit it for judgment work."
        Write-Host "[spawn] Tip: add ``-Model <id>`` to pin a specific model (e.g. ``-Model claude-fable-5``) -- no global env hack."
        Write-Host "[spawn] See agents/_index.md for the full list."
        Write-Host "[spawn] Opening session: $Name"
    }

    # Arg-pass / stale-shell guard (mirror of the bash wrapper). A parent shell
    # running an OLDER spawn() can bind a flag as the name or a bare tier word as
    # the task, silently producing a junk worker. Surface it loudly; the fix is
    # to reload the profile ( . $PROFILE ) or open a fresh shell, then re-spawn.
    if ($Name -like '-*') {
        Write-Host "[spawn] session name '$Name' looks like a flag (leading '-')." -ForegroundColor Yellow
        Write-Host "[spawn] Likely a STALE shell running an old spawn(). Run '. `$PROFILE' (or open a fresh shell), then re-spawn." -ForegroundColor Yellow
        return
    }
    if ($Task -in 'mechanical','judgment') {
        Write-Host "[spawn] task is the bare word '$Task' — a stale shell likely dropped your real task ('$Task' is a -Tier value, not a task)." -ForegroundColor Yellow
        Write-Host "[spawn] Run '. `$PROFILE' (or open a fresh shell), then re-spawn." -ForegroundColor Yellow
        return
    }

    $taskFile = Join-Path $env:TEMP "spawn-task-$Name.md"
    Set-Content -Path $taskFile -Value $Task -Encoding UTF8

    # In-process (in-shell) when NOT inside a Claude Code session, OR when this is an
    # AIOS-Glass-made terminal ($env:AIOS_GLASS_TERM). Glass created the terminal natively
    # (e.g. fulfilling a spawn-inbox request), so boot the worker in-place rather than
    # opening a redundant Windows Terminal window. The $env:CLAUDECODE check alone isn't
    # enough — a Glass terminal inherits it when the IDE was launched from a Claude session.
    if ((-not $env:CLAUDECODE) -or $env:AIOS_GLASS_TERM) {
        # In-process path: set CLAUDE_MODEL for the call only, then restore (no leak).
        if ($spawnModel) {
            $prevModel = $env:CLAUDE_MODEL
            $env:CLAUDE_MODEL = $spawnModel
            try { Invoke-ClaudeWithRespawn -Name $Name -BootstrapFile $taskFile }
            finally { $env:CLAUDE_MODEL = $prevModel }
        } else {
            Invoke-ClaudeWithRespawn -Name $Name -BootstrapFile $taskFile
        }
        return
    }

    # Build the script the new shell will run. Pass via -EncodedCommand because
    # wt.exe treats unescaped semicolons as tab separators -- a -Command string
    # with multiple statements would be split across phantom tabs.
    # Open the SAME PowerShell edition the wrapper was installed under — not
    # just "pwsh if it exists". The wrapper lives in this edition's $PROFILE;
    # opening the other edition would dot-source a different (wrapper-less)
    # profile → Invoke-ClaudeWithRespawn: command not found. Match the running
    # edition (Core = pwsh, Desktop = Windows PowerShell 5.1).
    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    # Inject the model into the new shell's env before it launches (mirrors the
    # in-process path). Empty when no --tier override -> frontier default.
    $modelStmt = if ($spawnModel) { "`$env:CLAUDE_MODEL = '$spawnModel'" } else { '' }
    $inner = @"
. `$PROFILE
$modelStmt
Set-Location '$($PWD.Path)'
Invoke-ClaudeWithRespawn -Name '$Name' -BootstrapFile '$taskFile'
"@
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($inner))

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (-not $wt) {
        Start-Process $shell -ArgumentList @('-NoExit', '-EncodedCommand', $encoded)
        return
    }
    Start-Process wt.exe -ArgumentList @('new-tab', '--title', $Name, $shell, '-NoExit', '-EncodedCommand', $encoded)

    # Force the new WT window to foreground. Start-Process from a child of the
    # IDE doesn't get foreground rights on Windows, so the tab opens hidden
    # behind the IDE. The HWND_TOPMOST/HWND_NOTOPMOST toggle bypasses this.
    Start-Sleep -Milliseconds 600
    if (-not ([System.Management.Automation.PSTypeName]'SpawnUtil.Win').Type) {
        Add-Type -Namespace SpawnUtil -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr hWnd, System.IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
"@
    }
    $wtProc = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
              Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
              Sort-Object StartTime -Descending |
              Select-Object -First 1
    if ($wtProc) {
        $h = $wtProc.MainWindowHandle
        [SpawnUtil.Win]::ShowWindow($h, 9) | Out-Null            # SW_RESTORE
        [SpawnUtil.Win]::SetWindowPos($h, [IntPtr]-1, 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null  # HWND_TOPMOST
        [SpawnUtil.Win]::SetWindowPos($h, [IntPtr]-2, 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null  # HWND_NOTOPMOST
        [SpawnUtil.Win]::SetForegroundWindow($h) | Out-Null
    }
}

function spawn-kill {
    # Kill a spawned worker session cleanly on Windows.
    #
    # Windows has no POSIX process groups, so the bash trick of `kill -KILL -- -PGID`
    # doesn't translate. Strategy: kill the PARENT process (the launcher pwsh that
    # holds the _claude_with_respawn loop) to take down the respawn cycle, then
    # kill claude itself to mop up any orphan that didn't cascade.
    #
    # Note: Windows Terminal doesn't expose a per-tab close API — the tab will
    # remain visible after the agent process exits. The tab can be closed
    # manually (Ctrl+Shift+W). The agent process itself is dead — that's the
    # part that matters for stopping work.
    #
    # Needs Windows validation on PS 5.1 + PS 7+. Untested on Windows as of
    # 2026-05-18; bash version on macOS is the proven path.
    [CmdletBinding()]
    param([Parameter(Mandatory, Position=0)] [string] $Name)

    # PowerShell doesn't expose process command lines via Get-Process — use CIM.
    # claude.exe on Windows is the Claude Code binary; node.exe is a possible
    # fallback for some install paths.
    $claudeProc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                  Where-Object {
                    ($_.Name -eq 'claude.exe' -or $_.Name -eq 'node.exe') -and
                    $_.CommandLine -like "*--remote-control*--name*$Name*"
                  } | Select-Object -First 1

    if (-not $claudeProc) {
        Write-Warning "[spawn-kill] no claude process found for '$Name'"
        Remove-Item -Force -ErrorAction SilentlyContinue "$env:TEMP\spawn-task-$Name.md","$env:TEMP\spawn-launch-$Name.ps1"
        return
    }

    $parentPid = $claudeProc.ParentProcessId
    if ($parentPid) {
        Stop-Process -Id $parentPid -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $claudeProc.ProcessId -Force -ErrorAction SilentlyContinue

    Remove-Item -Force -ErrorAction SilentlyContinue "$env:TEMP\spawn-task-$Name.md","$env:TEMP\spawn-launch-$Name.ps1"

    Write-Host "[ok] killed '$Name' (PID $($claudeProc.ProcessId), parent $parentPid)"
    Write-Host "      Windows Terminal tab will remain open; close manually with Ctrl+Shift+W"
}
# ==== END claude-spawn-wrappers ====
'@

Add-Content -Path $RC -Value $WRAPPER -Encoding UTF8

# ---- Append the dynamic primary-session function ----
# Operators get a shell function matching their declared primary session
# name (from USER.md). For fresh-clone operators without a session name yet,
# falls back to `claude` as a generic-safe placeholder. Re-running this
# script after personalizing USER.md swaps the placeholder for their name.
#
# **Wrapped in its own banner** so re-installs cleanly strip it regardless of
# the previous primary-session name -- handles rename N->N+1 without leaving
# orphan function definitions in the profile.
$PRIMARY_FN = @"

# ==== claude-primary-session (managed by hooks/claude-identity/install-wrappers.ps1) ====
# Primary-session shorthand -- runs ``$PRIMARY_NAME`` as a named, respawn-capable
# session. Re-run install-wrappers.ps1 after editing USER.md to rename this
# function to your actual session name.
function $PRIMARY_NAME {
    if (`$args[0] -eq '-c' -or `$args[0] -eq '--continue') { Invoke-ClaudeWithRespawn -Name '$PRIMARY_NAME' -InitialSessionId '--continue' }
    elseif (`$args[0] -eq '-r' -or `$args[0] -eq '--resume') { Invoke-ClaudeWithRespawn -Name '$PRIMARY_NAME' -InitialSessionId `$args[1] }
    else { Invoke-ClaudeWithRespawn -Name '$PRIMARY_NAME' }
}
# ==== END claude-primary-session ====
"@

Add-Content -Path $RC -Value $PRIMARY_FN -Encoding UTF8

Write-Host "[ok] Appended new wrapper block + $PRIMARY_NAME() shorthand to $RC"

# ---- Verify by inspecting profile content ----
# Why we don't use Get-Command here: this installer runs in the parent shell,
# but the profile is dot-sourced INTO the parent shell. If sourcing fails for
# any reason (parse error, missing prerequisite), the verification gives a
# false negative even when the wrapper was correctly written. Verifying file
# content (mirroring install-wrappers.sh's content-check approach) avoids
# this entire class of false-negative.
$profileText = Get-Content $RC -Raw
$RESPAWN_FN_OK  = if ($profileText -match 'function\s+Invoke-ClaudeWithRespawn') { 1 } else { 0 }
$SPAWN_FN_OK    = if ($profileText -match 'function\s+spawn\s*\{') { 1 } else { 0 }
$RESPAWN_LOOP_OK = if ($profileText -match 'CLAUDE_RESPAWN_CAPABLE') { 1 } else { 0 }
$SPAWN_WT_OK    = if ($profileText -match 'WindowsTerminal') { 1 } else { 0 }

Write-Host ""
Write-Host "Verification (profile-content check):"
Write-Host "  Invoke-ClaudeWithRespawn defined: $RESPAWN_FN_OK (expect 1)"
Write-Host "  spawn defined:                    $SPAWN_FN_OK (expect 1)"
Write-Host "  CLAUDE_RESPAWN_CAPABLE present:   $RESPAWN_LOOP_OK (expect 1)"
Write-Host "  WindowsTerminal foreground logic: $SPAWN_WT_OK (expect 1)"
Write-Host ""

if ($RESPAWN_FN_OK -eq 1 -and $SPAWN_FN_OK -eq 1 -and $RESPAWN_LOOP_OK -eq 1 -and $SPAWN_WT_OK -eq 1) {
    Write-Host "[ok] Wrappers installed successfully."
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  - In your CURRENT PowerShell, dot-source the profile to pick up the new wrapper:"
    Write-Host "      . `$PROFILE"
    Write-Host "  - New PowerShell windows pick up the new wrappers automatically."
    Write-Host "  - Backup at $BACKUP if you need to roll back."
    exit 0
} else {
    Write-Host "[warn] Verification failed. Restoring backup and exiting." -ForegroundColor Yellow
    Copy-Item -Path $BACKUP -Destination $RC -Force
    Write-Host "    Restored $RC from $BACKUP" -ForegroundColor Yellow
    exit 1
}

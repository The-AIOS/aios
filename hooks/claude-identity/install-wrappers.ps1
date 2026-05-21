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

# Strip inline function defs (no banner) -- only matches well-formed function blocks
foreach ($fn in 'Invoke-ClaudeWithRespawn', 'spawn') {
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
    $marker  = Join-Path $env:TEMP "swap-respawn-$Name.flag"
    $sidFile = Join-Path $env:TEMP "swap-respawn-$Name.session"
    $resumeArgs = @()
    if ($InitialSessionId) { $resumeArgs = @('--resume', $InitialSessionId) }
    while ($true) {
        $claudeArgs = @() + $resumeArgs + @('--remote-control', '--name', $Name)
        if ($BootstrapFile -and (Test-Path $BootstrapFile)) {
            $claudeArgs += "Read $BootstrapFile and follow the instructions inside."
        }
        & claude @claudeArgs
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
        [Parameter(Position=1)] [string] $Task = 'Start session.'
    )

    # Empty name -> generate adj-animal handle + print onboarding tip
    if ([string]::IsNullOrEmpty($Name)) {
        $Name = Get-SpawnAdjAnimal
        Write-Host "[spawn] No name given -- using handle: $Name"
        Write-Host "[spawn] Tip: name a specific agent for matched expertise (e.g. ``spawn accountant``)."
        Write-Host "[spawn] See agents/_index.md for the full list."
        Write-Host "[spawn] Opening session: $Name"
    }

    $taskFile = Join-Path $env:TEMP "spawn-task-$Name.md"
    Set-Content -Path $taskFile -Value $Task -Encoding UTF8

    if (-not $env:CLAUDECODE) {
        Invoke-ClaudeWithRespawn -Name $Name -BootstrapFile $taskFile
        return
    }

    # Build the script the new shell will run. Pass via -EncodedCommand because
    # wt.exe treats unescaped semicolons as tab separators -- a -Command string
    # with multiple statements would be split across phantom tabs.
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $inner = @"
. `$PROFILE
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
Write-Host "[ok] Appended new wrapper block to $RC"

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

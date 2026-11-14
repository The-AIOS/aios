# Skill registration (Windows) -- directory junctions into ~/.claude/skills so
# Claude Code auto-loads AIOS-origin skills. Junctions are used instead of
# symlinks because they do NOT require admin / Developer Mode. Idempotent.
# Usage:  pwsh skills/setup.ps1
#
# Mirrors skills/setup.sh: registers every source. superpowers/ is skipped only when
# a Superpowers plugin is installed (it provides those skills; linking the bundled
# copy would double them), checked at runtime (#313). anthropic/ is registered: no
# marketplace provides it (see setup.sh's header). Skips any name already present in
# ~/.claude/skills, and reports a plain-folder Superpowers copy as stale instead of
# touching it. Skills register standalone -- they do not touch the `aios` commands
# plugin. Restart Claude Code to pick up new links.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = Join-Path $HOME ".claude\skills"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Write-Host "Registering AIOS skills into $Dest ..."
Write-Host ""

# Installed, not merely available: Claude Code's own record of installed plugins, any
# "superpowers@<marketplace>" entry (see setup.sh).
$installed = Join-Path $HOME ".claude\plugins\installed_plugins.json"
$spPlugin = (Test-Path $installed) -and ((Get-Content -Raw -LiteralPath $installed) -match '"superpowers@')
$unlinked = 0

$linked = 0
$skipped = 0
$stale = @()
$skipSources = @()
if ($spPlugin) { $skipSources += 'superpowers' }

# A junction this script made before the plugin arrived would now double it: remove the
# junction itself (DirectoryInfo.Delete() on a junction never touches its target).
if ($spPlugin) {
  Get-ChildItem -Path (Join-Path $ScriptDir 'superpowers') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $t = Join-Path $Dest $_.Name
    if (Test-Path -LiteralPath $t) {
      $item = Get-Item -LiteralPath $t -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and ($item.Target -eq $_.FullName)) {
        $item.Delete()
        Write-Host "  - unlinked (its plugin provides it): $($_.Name)"
        $unlinked++
      }
    }
  }
}

Get-ChildItem -Path $ScriptDir -Directory |
  Where-Object { $skipSources -notcontains $_.Name } |
  ForEach-Object {
    $sourceName = $_.Name
    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
      $skillDir = $_.FullName
      if (Test-Path (Join-Path $skillDir 'SKILL.md')) {
        $name = $_.Name
        $target = Join-Path $Dest $name
        if (Test-Path $target) {
          $item = Get-Item -LiteralPath $target -Force
          if ($sourceName -eq 'superpowers' -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $stale += $name
            Write-Host "  ! old copy, left as it is: $name"
          }
          else {
            Write-Host "  - skip (already registered): $name"
          }
          $skipped++
        }
        else {
          New-Item -ItemType Junction -Path $target -Target $skillDir | Out-Null
          Write-Host "  + linked: $name"
          $linked++
        }
      }
    }
  }

Write-Host ""
Write-Host "Done - linked $linked, skipped $skipped."
Write-Host "Restart Claude Code to load newly-registered skills."
if ($spPlugin) {
  Write-Host ""
  $extra = ""; if ($unlinked -gt 0) { $extra = " (removed $unlinked earlier link(s))" }
  Write-Host "Superpowers comes from its installed plugin, so the bundled copy is not linked$extra."
}
if ($stale.Count -gt 0) {
  Write-Host ""
  Write-Host "$($stale.Count) Superpowers skill(s) in $Dest are plain folders: old copies that never update."
  Write-Host "  /aios:update offers to archive them. By hand: move them out of $Dest, then run this again."
}

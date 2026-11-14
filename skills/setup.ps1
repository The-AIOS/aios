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

# Active, not merely installed (see setup.sh): a user-wide "superpowers@<marketplace>"
# install that settings.json has not disabled, read by parsing the JSON, never by matching text.
$spPlugin = $false
try {
  $inst = Get-Content -Raw -LiteralPath (Join-Path $HOME ".claude\plugins\installed_plugins.json") -ErrorAction Stop | ConvertFrom-Json
  $enabled = $null
  try { $enabled = (Get-Content -Raw -LiteralPath (Join-Path $HOME ".claude\settings.json") -ErrorAction Stop | ConvertFrom-Json).enabledPlugins } catch { }
  foreach ($p in $inst.plugins.PSObject.Properties) {
    if (-not $p.Name.StartsWith('superpowers@')) { continue }
    if ($enabled -and ($enabled.PSObject.Properties.Name -contains $p.Name) -and ($enabled.($p.Name) -eq $false)) { continue }
    if (@($p.Value | Where-Object { $_.scope -eq 'user' }).Count -gt 0) { $spPlugin = $true }
  }
} catch { $spPlugin = $false }
$unlinked = 0
$spLinked = 0

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
      $tgt = @($item.Target)[0]
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $tgt -and
          ([IO.Path]::GetFullPath($tgt).TrimEnd('\') -eq [IO.Path]::GetFullPath($_.FullName).TrimEnd('\'))) {
        $item.Delete()
        Write-Host "  - unlinked (its plugin provides it): $($_.Name)"
        $unlinked++
      }
      elseif (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $stale += $_.Name
        Write-Host "  ! old copy, left as it is: $($_.Name)"
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
          if ($sourceName -eq 'superpowers') { $spLinked++ }
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
if ($spLinked -gt 0) {
  Write-Host ""
  Write-Host "Linked the bundled Superpowers ($spLinked skills). If you later install the Superpowers plugin,"
  Write-Host "  run this script again: it removes these links so the skills are not doubled."
}
if ($stale.Count -gt 0) {
  Write-Host ""
  Write-Host "$($stale.Count) Superpowers skill(s) in $Dest are plain folders: old copies that never update."
  Write-Host "  /aios:update offers to archive them. By hand: move them out of $Dest, then run this again."
}

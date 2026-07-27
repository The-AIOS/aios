# Skill registration (Windows) -- directory junctions into ~/.claude/skills so
# Claude Code auto-loads AIOS-origin skills. Junctions are used instead of
# symlinks because they do NOT require admin / Developer Mode. Idempotent.
# Usage:  pwsh skills/setup.ps1
#
# Mirrors skills/setup.sh: registers every source EXCEPT anthropic/ and
# superpowers/ (marketplace-provided), and skips any name already present in
# ~/.claude/skills. Skills register standalone -- they do not touch the `aios`
# commands plugin. Restart Claude Code to pick up new links.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = Join-Path $HOME ".claude\skills"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Write-Host "Registering AIOS skills into $Dest ..."
Write-Host ""

$linked = 0
$skipped = 0
$skipSources = @('anthropic', 'superpowers')

Get-ChildItem -Path $ScriptDir -Directory |
  Where-Object { $skipSources -notcontains $_.Name } |
  ForEach-Object {
    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
      $skillDir = $_.FullName
      if (Test-Path (Join-Path $skillDir 'SKILL.md')) {
        $name = $_.Name
        $target = Join-Path $Dest $name
        if (Test-Path $target) {
          Write-Host "  - skip (already registered): $name"
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

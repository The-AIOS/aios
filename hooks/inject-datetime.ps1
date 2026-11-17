# Moved to hooks/context/inject-datetime.ps1 (#309). This stub forwards for one release, then goes.
# Re-run through -File in the same PowerShell edition, so named switches (-Decline, -Json)
# bind as parameters: splatting @args would hand them over as plain strings.
$t = Join-Path $PSScriptRoot 'context/inject-datetime.ps1'
$exe = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
& $exe -NoProfile -ExecutionPolicy Bypass -File $t @args
exit $LASTEXITCODE

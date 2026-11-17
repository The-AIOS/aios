# Moved to hooks/context/inject-datetime.ps1 (#309). This stub forwards for one release, then goes.
& (Join-Path $PSScriptRoot 'context/inject-datetime.ps1') @args
exit $LASTEXITCODE

# Moved to hooks/pipeline/aios-star-check.ps1 (#309). This stub forwards for one release, then goes.
& (Join-Path $PSScriptRoot 'pipeline/aios-star-check.ps1') @args
exit $LASTEXITCODE

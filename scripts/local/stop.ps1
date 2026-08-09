$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

docker compose down
if ($LASTEXITCODE -ne 0) {
    throw "docker compose down fallo con codigo de salida $LASTEXITCODE."
}

Write-Host "OK: entorno local detenido. Los volumenes persistentes se conservaron."

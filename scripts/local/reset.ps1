$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

Write-Host "ADVERTENCIA: este comando elimina los volumenes locales de PostgreSQL, objetos y SMTP."
docker compose down --volumes --remove-orphans
if ($LASTEXITCODE -ne 0) {
    throw "docker compose down --volumes fallo con codigo de salida $LASTEXITCODE."
}

Write-Host "OK: entorno local eliminado junto con sus datos de desarrollo."

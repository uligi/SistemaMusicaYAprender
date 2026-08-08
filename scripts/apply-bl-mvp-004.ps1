$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

if (-not (Test-Path ".\MusicaAprender.sln")) {
    throw "Ejecute este script desde el repositorio SistemaMusicaYAprender."
}

Write-Host "BL-MVP-004: actualizando lockfiles por las dependencias de pruebas..."

dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Actualizacion de packages.lock.json"

Write-Host ""
Write-Host "Ejecutando puerta local con pruebas unitarias..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-004 preparado localmente."
Write-Host "Revise git status, confirme los packages.lock.json modificados y haga push para ejecutar GitHub Actions."

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "BL-MVP-010A: limpiando mensaje heredado de la puerta de calidad..."

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-010A aplicado."
Write-Host "La puerta de calidad ya no esta ligada a un numero de backlog."

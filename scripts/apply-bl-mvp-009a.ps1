$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "BL-MVP-009A: corrigiendo falsos positivos del escaneo de secretos..."

& "$PSScriptRoot/security/check-no-secrets.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-009A aplicado."
Write-Host "Ahora vuelva a ejecutar: .\scripts\apply-bl-mvp-009.ps1"

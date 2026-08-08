$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "BL-MVP-005A: corrigiendo lectura UTF-8 de las plantillas..."

& "$PSScriptRoot/governance/check-templates.ps1"

Write-Host ""
Write-Host "OK: correccion BL-MVP-005A aplicada."
Write-Host "Ahora ejecute: .\scripts\apply-bl-mvp-005.ps1"

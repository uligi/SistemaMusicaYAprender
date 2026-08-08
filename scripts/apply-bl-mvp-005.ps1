$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-005: validando plantillas de issue, PR y trazabilidad..."

& "$PSScriptRoot/governance/check-templates.ps1"

npm.cmd exec -- prettier .github docs/engineering/governance docs/engineering/traceability --write --ignore-unknown
Assert-LastExitCode "Formateo de plantillas y documentacion"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-005 preparado localmente."
Write-Host "Despues del push, cree un issue de prueba para confirmar que GitHub muestra el formulario requerido."

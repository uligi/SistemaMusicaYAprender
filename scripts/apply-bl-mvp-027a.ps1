[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "32a2cbdb5bf0102b3e527cb1998fb5a227a56294"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$TargetRelative = "apps/web/src/routes/public/PersonalAccountLoginPage.tsx"
$Target = Join-Path $RepoRoot $TargetRelative
$Prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"

Write-Host "BL-MVP-027A: corrigiendo exclusivamente el formato Prettier de UI-MVP-007..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-027A debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

if (-not (Test-Path $Target -PathType Leaf)) {
    throw "No se encontro $TargetRelative."
}

if (-not (Test-Path $Prettier -PathType Leaf)) {
    Write-Host "Prettier local no esta restaurado; ejecutando npm ci..."
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettierVersion = (& $Prettier --version).Trim()
Assert-LastExitCode "Consulta de version de Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Version de Prettier inesperada. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

Write-Host "Prettier local: $prettierVersion"
Write-Host "Aplicando formato canonico solo a $TargetRelative..."

& $Prettier --write $TargetRelative
Assert-LastExitCode "Prettier --write de PersonalAccountLoginPage.tsx"

& $Prettier --check $TargetRelative
Assert-LastExitCode "Prettier --check de PersonalAccountLoginPage.tsx"
Write-Host "OK: Prettier aprobó $TargetRelative."

npm.cmd run typecheck
Assert-LastExitCode "TypeScript despues de BL-MVP-027A"
Write-Host "OK: TypeScript aprobado."

git diff --check -- $TargetRelative
Assert-LastExitCode "git diff --check de BL-MVP-027A"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Diff del archivo corregido:"
git diff -- $TargetRelative
Assert-LastExitCode "Consulta del diff de BL-MVP-027A"

Write-Host ""
Write-Host "OK: BL-MVP-027A aplicado y validado."
Write-Host "No se ejecuto staging, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-027.ps1"

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "147e86ffe9b53435d7f277282f6c091aef3523d0"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$Targets = @(
    "docs/engineering/security/login-abuse-and-session-limits.md",
    "tests/E2ETests/personal-login-abuse.spec.ts"
)

Write-Host "BL-MVP-029A: corrigiendo exclusivamente el formato Prettier detectado por la puerta local..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-029A debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

foreach ($relativePath in $Targets) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "No se encontro $relativePath."
    }
}

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
if (-not (Test-Path $prettier -PathType Leaf)) {
    Write-Host "Prettier local no esta restaurado; ejecutando npm ci..."
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettierVersion = (& $prettier --version).Trim()
Assert-LastExitCode "Consulta de version de Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Version de Prettier inesperada. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

Write-Host "Prettier local: $prettierVersion"
Write-Host "Aplicando formato canonico solo a los dos archivos reportados por format:check..."

& $prettier --write @Targets
Assert-LastExitCode "Prettier --write de BL-MVP-029A"

& $prettier --check @Targets
Assert-LastExitCode "Prettier --check de BL-MVP-029A"
Write-Host "OK: Prettier aprobo los dos archivos afectados."

npm.cmd run typecheck:e2e
Assert-LastExitCode "TypeScript E2E despues de BL-MVP-029A"
Write-Host "OK: TypeScript E2E aprobado."

git diff --check -- @Targets
Assert-LastExitCode "git diff --check de BL-MVP-029A"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Diff de los dos archivos corregidos:"
git diff -- @Targets
Assert-LastExitCode "Consulta del diff de BL-MVP-029A"

Write-Host ""
Write-Host "OK: BL-MVP-029A aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-029.ps1"

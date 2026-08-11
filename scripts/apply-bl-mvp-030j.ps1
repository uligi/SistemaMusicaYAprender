[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "73fff5fe4982085ba090316c883587ef987e746f"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-030J: actualizando el mock E2E de logout al contrato de sesion BL-MVP-030..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030J debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$testRelative = "tests/E2ETests/personal-logout.spec.ts"
$testPath = Join-Path $RepoRoot $testRelative
$baseInstallerPath = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"

foreach ($path in @($testPath, $baseInstallerPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$testContent = [System.IO.File]::ReadAllText(
    $testPath,
    [System.Text.Encoding]::UTF8)

foreach ($required in @(
    "roles: ['STUDENT']",
    "capabilities: ['PROFILE.READ', 'CONTENT.READ', 'LEARNING.START']"
)) {
    if (-not $testContent.Contains($required)) {
        throw "El mock de sesion no contiene: $required"
    }
}

$baseContent = [System.IO.File]::ReadAllText(
    $baseInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030J.md",
    "README/BL-MVP-030J_README.md",
    "scripts/apply-bl-mvp-030j.ps1",
    "tests/E2ETests/personal-logout.spec.ts"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base no reconoce $artifact."
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

if (-not (Test-Path "node_modules" -PathType Container)) {
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

npm.cmd run typecheck:e2e
Assert-LastExitCode "TypeScript E2E BL-MVP-030J"
Write-Host "OK: TypeScript E2E aprobado."

npx.cmd playwright test `
    --config tests/E2ETests/playwright.config.ts `
    tests/E2ETests/personal-logout.spec.ts
Assert-LastExitCode "Playwright personal-logout BL-MVP-030J"
Write-Host "OK: regresion E2E BL-MVP-027 aprobada con el contrato de sesion BL-MVP-030."

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030J"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030J aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

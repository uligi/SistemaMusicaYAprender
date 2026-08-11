[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "73fff5fe4982085ba090316c883587ef987e746f"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-030K: corrigiendo formato Markdown de 030J..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030K debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$targets = @(
    "README/BL-MVP-030J_README.md",
    "README/BL-MVP-030K_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030K.md"
)

foreach ($relativePath in $targets) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "No se encontro $relativePath."
    }
}

$baseInstallerPath = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"
$baseContent = [System.IO.File]::ReadAllText(
    $baseInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030K.md",
    "README/BL-MVP-030K_README.md",
    "scripts/apply-bl-mvp-030k.ps1"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base no reconoce $artifact."
    }
}

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
if (-not (Test-Path $prettier -PathType Leaf)) {
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettierVersion = (& $prettier --version).Trim()
Assert-LastExitCode "Consulta de version Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Prettier inesperado. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

Write-Host "Prettier local: $prettierVersion"

& $prettier --write @targets
Assert-LastExitCode "Prettier --write Markdown 030J/030K"

& $prettier --check @targets
Assert-LastExitCode "Prettier --check Markdown 030J/030K"
Write-Host "OK: Markdown 030J/030K formateado y validado."

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030K"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030K aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-031B: corrigiendo formato Markdown del correctivo 031A..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-031B debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$targets = @(
    "README/BL-MVP-031A_README.md",
    "README/BL-MVP-031B_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031B.md"
)

foreach ($relativePath in $targets) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "No se encontro $relativePath."
    }
}

$mainInstallerPath = Join-Path $RepoRoot "scripts\apply-bl-mvp-031.ps1"
$mainContent = [System.IO.File]::ReadAllText(
    $mainInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031B.md",
    "README/BL-MVP-031B_README.md",
    "scripts/apply-bl-mvp-031b.ps1"
)) {
    if (-not $mainContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base BL-MVP-031 no reconoce $artifact."
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
Assert-LastExitCode "Prettier --write Markdown BL-MVP-031A/031B"

& $prettier --check @targets
Assert-LastExitCode "Prettier --check Markdown BL-MVP-031A/031B"
Write-Host "OK: Markdown 031A/031B formateado y validado."

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-031B"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-031B aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-031.ps1"

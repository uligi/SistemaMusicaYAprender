[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "32a2cbdb5bf0102b3e527cb1998fb5a227a56294"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$TargetRelative = "scripts/apply-bl-mvp-027.ps1"
$Target = Join-Path $RepoRoot $TargetRelative

Write-Host "BL-MVP-027B: validando inventario reconciliado de BL-MVP-027..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-027B debe aplicarse sobre main. Rama actual: '$currentBranch'."
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

$content = [System.IO.File]::ReadAllText($Target, [System.Text.Encoding]::UTF8)

$expectedPaths = @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027A.md",
    "README/BL-MVP-027A_README.md",
    "scripts/apply-bl-mvp-027a.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027B.md",
    "README/BL-MVP-027B_README.md",
    "scripts/apply-bl-mvp-027b.ps1"
)

foreach ($relativePath in $expectedPaths) {
    if (-not $content.Contains('"' + $relativePath + '"')) {
        throw "El instalador base no reconoce el artefacto correctivo requerido: $relativePath"
    }
}

if (-not $content.Contains('$allowedPaths = @($requiredFiles + $correctiveArtifacts + $historicalReadmeMoves)')) {
    throw "El instalador base no combina requiredFiles, correctiveArtifacts e historicalReadmeMoves."
}

$parseErrors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Target,
    [ref]$tokens,
    [ref]$parseErrors)

if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join " | "
    throw "El instalador base contiene errores de sintaxis: $messages"
}

Write-Host "OK: sintaxis PowerShell de apply-bl-mvp-027.ps1 aprobada."

git diff --check -- $TargetRelative
Assert-LastExitCode "git diff --check de BL-MVP-027B"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Artefactos correctivos reconocidos:"
foreach ($relativePath in $expectedPaths) {
    Write-Host "  + $relativePath"
}

Write-Host ""
Write-Host "OK: BL-MVP-027B aplicado y validado."
Write-Host "No se ejecuto staging, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-027.ps1"

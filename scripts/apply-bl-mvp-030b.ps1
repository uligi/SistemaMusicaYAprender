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

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($trackedPaths.Count -eq 0) {
        Write-Host "INFO: $relativePath no esta rastreado; no hay nada que restaurar."
        return
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "OK: $relativePath restaurado por ser salida incremental rastreada."
    }
    else {
        Write-Host "OK: $relativePath ya estaba limpio."
    }
}

Write-Host "BL-MVP-030B: restaurando salida incremental TypeScript y reconciliando la puerta base..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030B debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

Restore-GeneratedTypeScriptState

$baseInstaller = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"
$installerA = Join-Path $RepoRoot "scripts\apply-bl-mvp-030a.ps1"

foreach ($path in @($baseInstaller, $installerA)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$baseContent = [System.IO.File]::ReadAllText(
    $baseInstaller,
    [System.Text.Encoding]::UTF8)
$aContent = [System.IO.File]::ReadAllText(
    $installerA,
    [System.Text.Encoding]::UTF8)

if (-not $baseContent.Contains("Restore-GeneratedTypeScriptState")) {
    throw "La puerta base no contiene la restauracion del estado incremental."
}

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030B.md",
    "README/BL-MVP-030B_README.md",
    "scripts/apply-bl-mvp-030b.ps1"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base no reconoce el artefacto 030B: $artifact"
    }
}

if (-not $aContent.Contains("Restore-GeneratedTypeScriptState")) {
    throw "El correctivo 030A no fue reconciliado para restaurar tsbuildinfo."
}

git diff --check
Assert-LastExitCode "git diff --check de BL-MVP-030B"

$remaining = @(git status --porcelain=v1 -- apps/web/tsconfig.app.tsbuildinfo)
Assert-LastExitCode "Estado final de tsconfig.app.tsbuildinfo"
if ($remaining.Count -gt 0) {
    throw "apps/web/tsconfig.app.tsbuildinfo sigue modificado despues de la restauracion."
}

Write-Host ""
Write-Host "OK: BL-MVP-030B aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

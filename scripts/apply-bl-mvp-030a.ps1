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
        return
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

$Targets = @(
    "apps/web/src/app/router/route-manifest.ts",
    "docs/engineering/security/effective-authorization.md"
)

Write-Host "BL-MVP-030A: corrigiendo exclusivamente los dos archivos reportados por Prettier..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030A debe aplicarse sobre main. Rama actual: '$currentBranch'."
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
& $prettier --write @Targets
Assert-LastExitCode "Prettier --write de BL-MVP-030A"

& $prettier --check @Targets
Assert-LastExitCode "Prettier --check de BL-MVP-030A"
Write-Host "OK: Prettier aprobo los dos archivos afectados."

npm.cmd run typecheck
Assert-LastExitCode "TypeScript despues de BL-MVP-030A"
Write-Host "OK: TypeScript aprobado."

Restore-GeneratedTypeScriptState

git diff --check -- @Targets
Assert-LastExitCode "git diff --check de BL-MVP-030A"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030A aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

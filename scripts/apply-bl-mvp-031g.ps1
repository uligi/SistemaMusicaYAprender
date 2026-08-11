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

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $staged = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($staged.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $tracked = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($tracked.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de tsconfig.app.tsbuildinfo"
    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "OK: tsconfig.app.tsbuildinfo restaurado."
    }
}

Write-Host "BL-MVP-031G: corrigiendo adaptador onClick de Consultar asignaciones..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-031G debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$pageRelative = "apps/web/src/routes/administration/RoleManagementPage.tsx"
$testRelative = "tests/E2ETests/role-management.spec.ts"
$mainInstallerPath = Join-Path $RepoRoot "scripts\apply-bl-mvp-031.ps1"

foreach ($relativePath in @($pageRelative, $testRelative, "scripts/apply-bl-mvp-031.ps1")) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "No se encontro $relativePath."
    }
}

$pageContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $pageRelative),
    [System.Text.Encoding]::UTF8)

if ($pageContent.Contains("onClick={loadAssignments}")) {
    throw "El handler incompatible onClick={loadAssignments} sigue presente."
}

if (-not $pageContent.Contains("onClick={() => void loadAssignments()}")) {
    throw "No se encontro el adaptador onClick esperado."
}

$mainContent = [System.IO.File]::ReadAllText(
    $mainInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031G.md",
    "README/BL-MVP-031G_README.md",
    "scripts/apply-bl-mvp-031g.ps1"
)) {
    if (-not $mainContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base BL-MVP-031 no reconoce $artifact."
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

if (-not (Test-Path "node_modules" -PathType Container)) {
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$prettierVersion = (& $prettier --version).Trim()
Assert-LastExitCode "Consulta de version Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Prettier inesperado. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

$formatTargets = @(
    $pageRelative,
    $testRelative,
    "README/BL-MVP-031G_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031G.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-031G"

& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-031G"
Write-Host "OK: archivos 031G formateados."

npm.cmd run typecheck
Assert-LastExitCode "TypeScript web BL-MVP-031G"
Write-Host "OK: TypeScript web aprobado."

npm.cmd run typecheck:e2e
Assert-LastExitCode "TypeScript E2E BL-MVP-031G"
Write-Host "OK: TypeScript E2E aprobado."

npx.cmd playwright test `
    --config tests/E2ETests/playwright.config.ts `
    tests/E2ETests/role-management.spec.ts
Assert-LastExitCode "Playwright role-management BL-MVP-031G"
Write-Host "OK: E2E BL-MVP-031 aprobado tras el adaptador de evento."

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-031G"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-031G aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-031.ps1"

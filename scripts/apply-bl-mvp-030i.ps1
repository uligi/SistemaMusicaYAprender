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

    $staged = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice de tsbuildinfo"
    if ($staged.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $tracked = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsbuildinfo"
    if ($tracked.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de tsbuildinfo"
    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsbuildinfo"
        Write-Host "OK: tsconfig.app.tsbuildinfo restaurado."
    }
}

Write-Host "BL-MVP-030I: corrigiendo nombres de pruebas para CA1707..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030I debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$testRelative =
    "tests/UnitTests/Modules/Security/AuthorizationScopeMatcherTests.cs"
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

foreach ($legacyName in @(
    "Unscoped_assignment_grants_global_module_and_object_targets",
    "Module_assignment_is_not_a_global_grant",
    "Module_assignment_grants_only_its_module_and_objects",
    "Object_assignment_requires_exact_object",
    "Unknown_or_malformed_scope_fails_closed"
)) {
    if ($testContent.Contains($legacyName)) {
        throw "Sigue presente el nombre de test legacy: $legacyName"
    }
}

foreach ($requiredName in @(
    "UnscopedAssignmentGrantsGlobalModuleAndTargetScopes",
    "ModuleAssignmentIsNotGlobal",
    "ModuleAssignmentGrantsOnlyItsModuleAndTargets",
    "TargetAssignmentRequiresExactTarget",
    "UnknownOrMalformedScopeFailsClosed"
)) {
    if (-not $testContent.Contains($requiredName)) {
        throw "Falta el nombre de test corregido: $requiredName"
    }
}

if (-not $testContent.Contains("using Xunit;")) {
    throw "Falta using Xunit en AuthorizationScopeMatcherTests.cs."
}

$baseContent = [System.IO.File]::ReadAllText(
    $baseInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030I.md",
    "README/BL-MVP-030I_README.md",
    "scripts/apply-bl-mvp-030i.ps1"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base no reconoce $artifact."
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

dotnet restore MusicaAprender.sln --locked-mode
Assert-LastExitCode "Restore .NET locked"

dotnet format MusicaAprender.sln `
    --verify-no-changes `
    --no-restore
Assert-LastExitCode "dotnet format despues de BL-MVP-030I"
Write-Host "OK: dotnet format y analyzers aprobados."

dotnet build `
    tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-restore
Assert-LastExitCode "Build UnitTests BL-MVP-030I"
Write-Host "OK: proyecto UnitTests compila sin CA1707."

dotnet test `
    tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-build `
    --no-restore
Assert-LastExitCode "UnitTests BL-MVP-030I"
Write-Host "OK: pruebas unitarias aprobadas."

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030I"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030I aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

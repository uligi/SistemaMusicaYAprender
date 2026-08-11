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

Write-Host "BL-MVP-030G: corrigiendo CA1720 en el enum interno de alcance..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030G debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$scopeRelative = "src/Modules/Security/Infrastructure/Authorization/AuthorizationScope.cs"
$matcherRelative = "src/Modules/Security/Infrastructure/Authorization/AuthorizationScopeMatcher.cs"
$baseInstallerRelative = "scripts/apply-bl-mvp-030.ps1"

foreach ($relativePath in @(
    $scopeRelative,
    $matcherRelative,
    $baseInstallerRelative
)) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "No se encontro $relativePath."
    }
}

$scopeContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $scopeRelative),
    [System.Text.Encoding]::UTF8)
$matcherContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $matcherRelative),
    [System.Text.Encoding]::UTF8)

$scopeHasLegacyObject = $scopeContent.Contains(
    "AuthorizationScopeKind.Object")
$matcherHasLegacyObject = $matcherContent.Contains(
    "AuthorizationScopeKind.Object")

if ($scopeHasLegacyObject -or $matcherHasLegacyObject) {
    throw "La referencia interna AuthorizationScopeKind.Object sigue presente."
}

$scopeHasTarget = $scopeContent.Contains(
    "AuthorizationScopeKind.Target")
$matcherHasTarget = $matcherContent.Contains(
    "AuthorizationScopeKind.Target")

if (-not $scopeHasTarget -or -not $matcherHasTarget) {
    throw "No se encontro AuthorizationScopeKind.Target en los archivos esperados."
}

if (-not $matcherContent.Contains('"OBJECT"')) {
    throw "El matcher dejo de reconocer el scope_type fisico OBJECT."
}

$baseContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $baseInstallerRelative),
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030G.md",
    "README/BL-MVP-030G_README.md",
    "scripts/apply-bl-mvp-030g.ps1"
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
Assert-LastExitCode "dotnet format despues de BL-MVP-030G"
Write-Host "OK: dotnet format y analyzers aprobados."

dotnet build `
    src/Modules/Security/MusicaAprender.Modules.Security.csproj `
    --configuration Release `
    --no-restore
Assert-LastExitCode "Build Security BL-MVP-030G"
Write-Host "OK: modulo Security compila sin CA1720."

dotnet build `
    tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-restore
Assert-LastExitCode "Build UnitTests BL-MVP-030G"
Write-Host "OK: proyecto UnitTests compila."

dotnet test `
    tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-build `
    --no-restore
Assert-LastExitCode "UnitTests BL-MVP-030G"
Write-Host "OK: pruebas unitarias aprobadas."

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030G"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030G aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

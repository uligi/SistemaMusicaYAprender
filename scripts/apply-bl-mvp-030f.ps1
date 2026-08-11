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

Write-Host "BL-MVP-030F: corrigiendo import explicito de xUnit en la prueba de scopes..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030F debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$testRelative = "tests/UnitTests/Modules/Security/AuthorizationScopeMatcherTests.cs"
$testPath = Join-Path $RepoRoot $testRelative
$baseInstaller = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"

foreach ($path in @($testPath, $baseInstaller)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$testContent = [System.IO.File]::ReadAllText(
    $testPath,
    [System.Text.Encoding]::UTF8)

if (-not $testContent.Contains("using Xunit;")) {
    throw "AuthorizationScopeMatcherTests.cs no contiene el import explicito de Xunit."
}

if (-not $testContent.Contains("[Fact]")) {
    throw "AuthorizationScopeMatcherTests.cs no contiene pruebas Fact."
}

$baseContent = [System.IO.File]::ReadAllText(
    $baseInstaller,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030F.md",
    "README/BL-MVP-030F_README.md",
    "scripts/apply-bl-mvp-030f.ps1"
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
Assert-LastExitCode "dotnet format despues de BL-MVP-030F"
Write-Host "OK: dotnet format y analyzers aprobados."

dotnet build tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-restore
Assert-LastExitCode "Build UnitTests BL-MVP-030F"
Write-Host "OK: proyecto UnitTests compila."

dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj `
    --configuration Release `
    --no-build `
    --no-restore
Assert-LastExitCode "UnitTests BL-MVP-030F"
Write-Host "OK: pruebas unitarias aprobadas."

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030F"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-030F aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

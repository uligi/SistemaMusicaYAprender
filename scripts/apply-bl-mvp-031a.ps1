[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af"
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

Write-Host "BL-MVP-031A: corrigiendo el tipo de headers CSRF al contrato del cliente HTTP..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-031A debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$targetRelative = "apps/web/src/routes/administration/RoleManagementPage.tsx"
$targetPath = Join-Path $RepoRoot $targetRelative
$typesPath = Join-Path $RepoRoot "apps/web/src/data/http/types.ts"
$mainInstallerPath = Join-Path $RepoRoot "scripts/apply-bl-mvp-031.ps1"

foreach ($path in @($targetPath, $typesPath, $mainInstallerPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$typesContent = [System.IO.File]::ReadAllText(
    $typesPath,
    [System.Text.Encoding]::UTF8)

$expectedHttpContract = "headers?: Readonly<Record<string, string>>;"
if (-not $typesContent.Contains($expectedHttpContract)) {
    throw "El contrato HttpRequestOptions no coincide con el esperado: $expectedHttpContract"
}

$targetContent = [System.IO.File]::ReadAllText(
    $targetPath,
    [System.Text.Encoding]::UTF8)

$oldType = "async function csrfHeaders(): Promise<HeadersInit | null> {"
$newType = "async function csrfHeaders(): Promise<Readonly<Record<string, string>> | null> {"

if ($targetContent.Contains($newType)) {
    Write-Host "OK: tipo de headers CSRF ya estaba corregido."
}
elseif ($targetContent.Contains($oldType)) {
    $updated = $targetContent.Replace($oldType, $newType)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $targetPath,
        $updated,
        $utf8NoBom)
    Write-Host "OK: headers CSRF alineados con HttpRequestOptions."
}
else {
    throw "No se encontro la firma esperada de csrfHeaders."
}

$mainContent = [System.IO.File]::ReadAllText(
    $mainInstallerPath,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031A.md",
    "README/BL-MVP-031A_README.md",
    "scripts/apply-bl-mvp-031a.ps1"
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
& $prettier --write $targetRelative
Assert-LastExitCode "Prettier RoleManagementPage"

& $prettier --check $targetRelative
Assert-LastExitCode "Prettier check RoleManagementPage"
Write-Host "OK: RoleManagementPage formateado."

npm.cmd run typecheck
Assert-LastExitCode "TypeScript BL-MVP-031A"
Write-Host "OK: TypeScript aprobado."

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-031A"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-031A aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-031.ps1"

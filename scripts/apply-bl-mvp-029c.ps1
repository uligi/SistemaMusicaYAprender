[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "147e86ffe9b53435d7f277282f6c091aef3523d0"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$TargetRelative = "tests/E2ETests/personal-login-abuse.spec.ts"
$Target = Join-Path $RepoRoot $TargetRelative
$BaseInstaller = Join-Path $RepoRoot "scripts\apply-bl-mvp-029.ps1"
$Prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$Playwright = Join-Path $RepoRoot "node_modules\.bin\playwright.cmd"

Write-Host "BL-MVP-029C: corrigiendo la validacion del correctivo E2E en Windows PowerShell..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-029C debe aplicarse sobre main. Rama actual: '$currentBranch'."
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

if (-not (Test-Path $BaseInstaller -PathType Leaf)) {
    throw "No se encontro scripts/apply-bl-mvp-029.ps1."
}

$testContent = [System.IO.File]::ReadAllText(
    $Target,
    [System.Text.Encoding]::UTF8)

# ASCII-only structural checks. 029B failed because its validator embedded an accented
# literal in the .ps1 source, which Windows PowerShell 5.1 decoded using the legacy code page.
if ($testContent.Contains(
    "page.getByText(/cuenta limitada|")) {
    throw "La asercion global defectuosa sigue presente. Extraiga de nuevo BL-MVP-029C."
}

if (-not $testContent.Contains(
    "const waitState = page.locator('[data-state=`"UI-EST-06`"]');")) {
    throw "No se encontro la asercion acotada al StateMessage de HTTP 429."
}

if (-not $testContent.Contains(
    "await expect(waitState).not.toContainText(/cuenta|")) {
    throw "No se encontro el inicio de la comprobacion no enumerativa acotada."
}

if (-not $testContent.Contains(
    "|correo existe/i);")) {
    throw "No se encontro el cierre de la comprobacion no enumerativa acotada."
}

$baseContent = [System.IO.File]::ReadAllText(
    $BaseInstaller,
    [System.Text.Encoding]::UTF8)

foreach ($relativePath in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029C.md",
    "README/BL-MVP-029C_README.md",
    "scripts/apply-bl-mvp-029c.ps1"
)) {
    if (-not $baseContent.Contains('"' + $relativePath + '"')) {
        throw "El instalador base no reconoce el artefacto 029C: $relativePath"
    }
}

if (-not (Test-Path $Prettier -PathType Leaf)) {
    Write-Host "Dependencias Node no restauradas; ejecutando npm ci..."
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettierVersion = (& $Prettier --version).Trim()
Assert-LastExitCode "Consulta de version de Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Version de Prettier inesperada. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

& $Prettier --check $TargetRelative
Assert-LastExitCode "Prettier --check de personal-login-abuse.spec.ts"
Write-Host "OK: Prettier aprobado."

npm.cmd run typecheck:e2e
Assert-LastExitCode "TypeScript E2E de BL-MVP-029C"
Write-Host "OK: TypeScript E2E aprobado."

if (-not (Test-Path $Playwright -PathType Leaf)) {
    throw "No se encontro el binario local de Playwright."
}

& $Playwright test `
    $TargetRelative `
    --config tests/E2ETests/playwright.config.ts
Assert-LastExitCode "Playwright focalizado BL-MVP-029C"
Write-Host "OK: Playwright focalizado BL-MVP-029C aprobado."

git diff --check -- $TargetRelative "scripts/apply-bl-mvp-029.ps1"
Assert-LastExitCode "git diff --check de BL-MVP-029C"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-029C aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-029.ps1"

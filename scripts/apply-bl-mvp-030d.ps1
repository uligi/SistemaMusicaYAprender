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

Write-Host "BL-MVP-030D: completando aliases legacy omitidos por destino canonico repetido..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030D debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$routeRelative = "apps/web/src/app/router/route-manifest.ts"
$routePath = Join-Path $RepoRoot $routeRelative
if (-not (Test-Path $routePath -PathType Leaf)) {
    throw "No se encontro $routeRelative."
}

$replacements = @(
    @("requiredCapabilities: ['lyrics:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['timing:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['translation:edit', 'translation:review'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['analysis:edit', 'analysis:review'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['exercise:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],")
)

foreach ($replacement in $replacements) {
    $content = [System.IO.File]::ReadAllText(
        $routePath,
        [System.Text.Encoding]::UTF8)

    if ($content.Contains($replacement[0])) {
        $updated = $content.Replace(
            $replacement[0],
            $replacement[1])
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText(
            $routePath,
            $updated,
            $utf8NoBom)
        Write-Host "OK: reemplazado $($replacement[0])."
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

& $prettier --write $routeRelative
Assert-LastExitCode "Prettier --write route-manifest"

& $prettier --check $routeRelative
Assert-LastExitCode "Prettier --check route-manifest"
Write-Host "OK: route-manifest formateado con Prettier 3.9.6."

npm.cmd run typecheck
Assert-LastExitCode "TypeScript BL-MVP-030D"
Write-Host "OK: TypeScript aprobado."

Restore-GeneratedTypeScriptState

$content = [System.IO.File]::ReadAllText(
    $routePath,
    [System.Text.Encoding]::UTF8)

$legacy = @(
    @(
        "editorial:access",
        "catalog:edit",
        "rights:edit",
        "rights:review",
        "lyrics:edit",
        "timing:edit",
        "translation:edit",
        "translation:review",
        "analysis:edit",
        "analysis:review",
        "exercise:edit",
        "package:edit",
        "package:review",
        "publication:review",
        "publication:correct",
        "security:roles",
        "configuration:manage",
        "audit:read"
    ) | Where-Object { $content.Contains($_) }
)

if ($legacy.Count -gt 0) {
    throw "Aun quedan capacidades legacy: $($legacy -join ', ')."
}

foreach ($required in @(
    "EDITORIAL.DRAFT",
    "EDITORIAL.REVIEW",
    "EDITORIAL.PUBLISH",
    "EDITORIAL.CORRECT",
    "EDITORIAL.SUBMIT",
    "SECURITY.MANAGE_ROLES",
    "CONFIG.MANAGE",
    "SECURITY.READ_AUDIT"
)) {
    if (-not $content.Contains($required)) {
        throw "Falta capacidad canonica: $required"
    }
}

$baseInstaller = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"
$baseContent = [System.IO.File]::ReadAllText(
    $baseInstaller,
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030D.md",
    "README/BL-MVP-030D_README.md",
    "scripts/apply-bl-mvp-030d.ps1"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "La puerta base no reconoce $artifact."
    }
}

if (-not $baseContent.Contains(
    "capacidades UI canonicas reconciliadas sin falsos positivos por destino repetido.")) {
    throw "La puerta base no contiene la logica idempotente 030D."
}

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-030D"

Write-Host ""
Write-Host "OK: BL-MVP-030D aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

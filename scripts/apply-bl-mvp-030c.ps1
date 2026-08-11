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

Write-Host "BL-MVP-030C: reconciliando el route-manifest ya formateado con la puerta base..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030C debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$routePath = Join-Path $RepoRoot "apps\web\src\app\router\route-manifest.ts"
$baseInstaller = Join-Path $RepoRoot "scripts\apply-bl-mvp-030.ps1"

foreach ($path in @($routePath, $baseInstaller)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$routeContent = [System.IO.File]::ReadAllText(
    $routePath,
    [System.Text.Encoding]::UTF8)

$legacyMarkers = @(
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
)

$canonicalMarkers = @(
    "EDITORIAL.DRAFT",
    "EDITORIAL.REVIEW",
    "EDITORIAL.PUBLISH",
    "EDITORIAL.CORRECT",
    "EDITORIAL.SUBMIT",
    "SECURITY.MANAGE_ROLES",
    "CONFIG.MANAGE",
    "SECURITY.READ_AUDIT"
)

$legacyPresent = @(
    $legacyMarkers |
        Where-Object { $routeContent.Contains($_) }
)
if ($legacyPresent.Count -gt 0) {
    throw "Aun hay capacidades legacy en route-manifest: $($legacyPresent -join ', ')."
}

$canonicalMissing = @(
    $canonicalMarkers |
        Where-Object { -not $routeContent.Contains($_) }
)
if ($canonicalMissing.Count -gt 0) {
    throw "Faltan capacidades canonicas en route-manifest: $($canonicalMissing -join ', ')."
}

$baseContent = [System.IO.File]::ReadAllText(
    $baseInstaller,
    [System.Text.Encoding]::UTF8)

foreach ($marker in @(
    "capacidades UI canonicas ya estaban aplicadas y formateadas.",
    "legacyCapabilityMarkers",
    "canonicalCapabilityMarkers",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030C.md",
    "README/BL-MVP-030C_README.md",
    "scripts/apply-bl-mvp-030c.ps1"
)) {
    if (-not $baseContent.Contains($marker)) {
        throw "La puerta base no contiene el marcador 030C requerido: $marker"
    }
}

git diff --check
Assert-LastExitCode "git diff --check de BL-MVP-030C"

Write-Host "OK: route-manifest canonico validado sin depender del layout de Prettier."
Write-Host "OK: BL-MVP-030C aplicado y validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-030.ps1"

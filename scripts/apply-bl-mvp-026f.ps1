[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$TargetRelative = "scripts/apply-bl-mvp-026.ps1"
$Target = Join-Path $RepoRoot $TargetRelative

Write-Host "BL-MVP-026F: reconciliando el inventario del instalador base con los correctivos D, E y F..."

if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
    throw "No se encontro $TargetRelative."
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($Target, [System.Text.Encoding]::UTF8)

$pathsToAllow = @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026D.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026E.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026F.md",
    "README/BL-MVP-026D_README.md",
    "README/BL-MVP-026E_README.md",
    "README/BL-MVP-026F_README.md",
    "scripts/apply-bl-mvp-026d.ps1",
    "scripts/apply-bl-mvp-026e.ps1",
    "scripts/apply-bl-mvp-026f.ps1"
)

$anchorPattern = '(?m)^(?<indent>\s*)"scripts/apply-bl-mvp-026\.ps1",\r?$'
$matches = [regex]::Matches($content, $anchorPattern)

if ($matches.Count -ne 1) {
    throw "Se esperaba exactamente un ancla de inventario para scripts/apply-bl-mvp-026.ps1 y se encontraron $($matches.Count). No se modifico el archivo."
}

$missing = @()
foreach ($relativePath in $pathsToAllow) {
    $escaped = [regex]::Escape('"' + $relativePath + '"')
    if (-not [regex]::IsMatch($content, $escaped)) {
        $missing += $relativePath
    }
}

if ($missing.Count -eq 0) {
    Write-Host "OK: el inventario de BL-MVP-026 ya reconoce D, E y F."
}
else {
    $match = $matches[0]
    $indent = $match.Groups["indent"].Value
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }

    $insertLines = foreach ($relativePath in $missing) {
        "$indent`"$relativePath`","
    }

    $replacement = $match.Value.TrimEnd("`r", "`n") + $newline + ($insertLines -join $newline)
    $updated = $content.Substring(0, $match.Index) +
        $replacement +
        $content.Substring($match.Index + $match.Length)

    [System.IO.File]::WriteAllText($Target, $updated, $utf8NoBom)
    $content = $updated

    Write-Host "OK: inventario reconciliado. Rutas agregadas:"
    foreach ($relativePath in $missing) {
        Write-Host "  + $relativePath"
    }
}

# Validación sintáctica de PowerShell sin ejecutar el instalador base.
$parseErrors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Target,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join " | "
    throw "El instalador base quedo con errores de sintaxis: $messages"
}
Write-Host "OK: sintaxis PowerShell de apply-bl-mvp-026.ps1 aprobada."

git diff --check -- $TargetRelative
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check del instalador base fallo con codigo $LASTEXITCODE."
}
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Inventario correctivo reconocido por BL-MVP-026:"
foreach ($relativePath in $pathsToAllow) {
    $exists = Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf
    $state = if ($exists) { "presente" } else { "ausente" }
    Write-Host "  [$state] $relativePath"
}

Write-Host ""
Write-Host "OK: BL-MVP-026F instalado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-026.ps1"

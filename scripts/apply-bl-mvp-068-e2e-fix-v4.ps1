param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    throw "BL-MVP-068 E2E fix v4: $Message"
}

$root = (Resolve-Path $RepoRoot).Path
Set-Location $root

$path = Join-Path $root "tests/E2ETests/contextual-analysis-panel.spec.ts"
if (-not (Test-Path $path -PathType Leaf)) {
    Fail "no existe tests/E2ETests/contextual-analysis-panel.spec.ts"
}

$text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$original = $text

$detail = "            detail: 'No se mezclará otra revisión.',"
$code = "            code: 'content.public-analysis.incompatible',"

if (-not $text.Contains($code)) {
    if (-not $text.Contains($detail)) {
        Fail "no se encontro la linea detail del mock 409."
    }

    $text = $text.Replace(
        $detail,
        "$detail`n$code"
    )
    Write-Host "OK: stable code agregado al mock 409."
}
else {
    Write-Host "OK: stable code del mock 409 ya estaba aplicado."
}

$oldAssertion = "    await expect(page.getByText('Análisis contextual incompatible')).toBeVisible();"
$newAssertion = "    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();"

if (-not $text.Contains($newAssertion)) {
    if (-not $text.Contains($oldAssertion)) {
        Fail "no se encontro la asercion antigua del conflicto 409."
    }

    $text = $text.Replace($oldAssertion, $newAssertion)
    Write-Host "OK: asercion 409 alineada al contrato HTTP localizado."
}
else {
    Write-Host "OK: asercion 409 ya estaba corregida."
}

if ($text -ne $original) {
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $normalized, $utf8)
}

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detecto problemas."
}

Write-Host ""
Write-Host "OK: BL-MVP-068 E2E fix v4 completado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Todos los scripts apply-* BL068 siguen siendo temporales."

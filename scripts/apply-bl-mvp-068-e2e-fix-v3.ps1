param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    throw "BL-MVP-068 E2E fix v3: $Message"
}

function Write-Utf8Lf([string]$Path, [string]$Content) {
    $full = Join-Path $script:Root $Path
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $normalized, $utf8)
    Write-Host "OK: $Path"
}

function Replace-Or-Confirm(
    [string]$Path,
    [string]$Old,
    [string]$New,
    [string]$Description
) {
    $full = Join-Path $script:Root $Path
    if (-not (Test-Path $full -PathType Leaf)) {
        Fail "no existe $Path"
    }

    $text = [System.IO.File]::ReadAllText($full)
    $normalized = $text -replace "`r`n", "`n" -replace "`r", "`n"

    if ($normalized.Contains($New)) {
        Write-Host "OK: $Description ya aplicado."
        return
    }

    $count = ([regex]::Matches(
        $normalized,
        [regex]::Escape($Old)
    )).Count

    if ($count -ne 1) {
        Fail "se esperaba exactamente 1 bloque para $Description en $Path y se encontraron $count."
    }

    $updated = $normalized.Replace($Old, $New)
    Write-Utf8Lf $Path $updated
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$panel = "apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
$test = "tests/E2ETests/contextual-analysis-panel.spec.ts"

Write-Host "BL-MVP-068: completando correccion E2E parcial v2..."

# Reconfirma las cuatro correcciones; las ya aplicadas quedan intactas.
Replace-Or-Confirm `
    $panel `
    '          <section className="contextual-analysis__selection" aria-labelledby="analysis-selection">' `
    '          <div className="contextual-analysis__selection">' `
    "landmark redundante de selección"

Replace-Or-Confirm `
    $panel `
    @'
          </section>

          {!state.data.available ? (
'@ `
    @'
          </div>

          {!state.data.available ? (
'@ `
    "cierre semántico de selección"

Replace-Or-Confirm `
    $test `
    "    await expect(page.getByText('かいじゅう', { exact: true })).toBeVisible();" `
    "    await expect(`n      page.locator('.contextual-analysis__selection').getByText('かいじゅう', { exact: true }),`n    ).toBeVisible();" `
    "locator acotado de lectura contextual"

Replace-Or-Confirm `
    $test `
    @'
    await expect(
      page.getByText('nivel orientativo, no certificación oficial.', { exact: false }),
    ).toBeVisible();
'@ `
    @'
    await expect(
      page.getByText('nivel orientativo, no certificación oficial.', { exact: false }),
    ).toHaveCount(2);
'@ `
    "cardinalidad de avisos JLPT"

# El fallo de v2 ocurrió porque este bloque se buscó con saltos LF exactos
# sobre un archivo que Prettier había dejado con CRLF en Windows.
# v3 normaliza los saltos antes de reemplazar.
Replace-Or-Confirm `
    $test `
    @'
        body: JSON.stringify({
          title: 'Análisis contextual incompatible',
          status: 409,
          detail: 'No se mezclará otra revisión.',
        }),
'@ `
    @'
        body: JSON.stringify({
          title: 'Análisis contextual incompatible',
          status: 409,
          detail: 'No se mezclará otra revisión.',
          code: 'content.public-analysis.incompatible',
        }),
'@ `
    "stable code del mock 409"

Replace-Or-Confirm `
    $test `
    "    await expect(page.getByText('Análisis contextual incompatible')).toBeVisible();" `
    "    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();" `
    "mensaje localizado de conflicto 409"

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detecto problemas."
}

Write-Host ""
Write-Host "OK: BL-MVP-068 E2E fix v3 completado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Los scripts apply-* siguen siendo temporales y deben eliminarse antes del staging."

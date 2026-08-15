param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Fail([string]$Message) {
    throw "BL-MVP-068 E2E fix v2: $Message"
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

function Replace-Once(
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
    $first = $text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        Fail "no se encontro bloque esperado para $Description en $Path"
    }

    $second = $text.IndexOf(
        $Old,
        $first + $Old.Length,
        [System.StringComparison]::Ordinal
    )
    if ($second -ge 0) {
        Fail "el bloque para $Description aparece mas de una vez en $Path"
    }

    $updated = $text.Substring(0, $first) + $New + $text.Substring($first + $Old.Length)
    Write-Utf8Lf $Path $updated
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$panel = "apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
$test = "tests/E2ETests/contextual-analysis-panel.spec.ts"

Write-Host "BL-MVP-068: corrigiendo 3 aserciones E2E y 1 landmark duplicado..."

# 1) Axe: evitar que la selección del token cree otro landmark "region"
# con el mismo nombre accesible que el bloque de contenido propio.
Replace-Once `
    $panel `
    '          <section className="contextual-analysis__selection" aria-labelledby="analysis-selection">' `
    '          <div className="contextual-analysis__selection">' `
    "landmark duplicado de selección contextual"

Replace-Once `
    $panel `
    @'
          </section>

          {!state.data.available ? (
'@ `
    @'
          </div>

          {!state.data.available ? (
'@ `
    "cierre semántico de selección contextual"

# 2) La lectura aparece varias veces legítimamente (ruby, lectura contextual,
# ficha de vocabulario). La aserción debe comprobar la lectura dentro de la
# sección contextual, no usar un locator global estricto.
Replace-Once `
    $test `
    "    await expect(page.getByText('かいじゅう', { exact: true })).toBeVisible();" `
    "    await expect(`n      page.locator('.contextual-analysis__selection').getByText('かいじゅう', { exact: true }),`n    ).toBeVisible();" `
    "locator de lectura contextual"

# 3) El fixture tiene dos kanji y ambos son N1. Dos avisos JLPT idénticos son
# correctos; comprobar cardinalidad evita strict-mode violation.
Replace-Once `
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
    "avisos JLPT repetidos válidos"

# 4) El cliente HTTP no muestra title/detail remotos: para 409 usa su contrato
# localizado estable. Añadimos el stable code real al mock y verificamos el
# estado de conflicto del cliente + ausencia de contenido stale.
Replace-Once `
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

Replace-Once `
    $test `
    "    await expect(page.getByText('Análisis contextual incompatible')).toBeVisible();" `
    "    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();" `
    "contrato localizado de conflicto"

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detecto problemas."
}

Write-Host ""
Write-Host "OK: correcciones focales BL068 aplicadas."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Este script es temporal y debe eliminarse antes del staging."

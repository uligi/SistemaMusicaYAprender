[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$required = @(
    "package.json",
    "tests/E2ETests/playwright.config.ts",
    "tests/E2ETests/tsconfig.json",
    "tests/E2ETests/base-accessibility.spec.ts",
    "tests/E2ETests/README.md",
    "docs/engineering/frontend/e2e-accessibility-visual.md",
    "scripts/frontend/verify-e2e-harness.mjs",
    "BL-MVP-022_README.md"
)

foreach ($relativePath in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath))) {
        throw "Falta el archivo del parche BL-MVP-022: $relativePath"
    }
}

$workflowPath = Join-Path $RepoRoot ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)

if (-not $workflow.Contains("Verify Playwright, axe and visual test harness")) {
    $anchor = @'
      - name: Verify typed HTTP client and ProblemDetails
        run: node scripts/frontend/verify-http-client.mjs

      - name: Formatting check
'@

    $replacement = @'
      - name: Verify typed HTTP client and ProblemDetails
        run: node scripts/frontend/verify-http-client.mjs

      - name: Verify Playwright, axe and visual test harness
        run: node scripts/frontend/verify-e2e-harness.mjs

      - name: TypeScript strict check for E2E harness
        run: npm run typecheck:e2e

      - name: Formatting check
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla de verificadores frontend esperada en CI."
    }

    $workflow = $workflow.Replace($anchor, $replacement)
}

if (-not $workflow.Contains("Install Chromium for Playwright")) {
    $anchor = @'
      - name: Build frontend
        run: npm run build

      - name: Verify .NET formatting and analyzers
'@

    $replacement = @'
      - name: Build frontend
        run: npm run build

      - name: Install Chromium for Playwright
        run: npx playwright install --with-deps chromium

      - name: Run E2E accessibility and visual evidence
        run: npm run test:e2e

      - name: Verify .NET formatting and analyzers
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla de build frontend esperada en CI."
    }

    $workflow = $workflow.Replace($anchor, $replacement)
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($workflowPath, ($workflow.TrimEnd("`r", "`n") + "`n"), $utf8NoBom)

$qualityPath = Join-Path $RepoRoot "scripts/check-quality.ps1"
$quality = [System.IO.File]::ReadAllText($qualityPath)

if (-not $quality.Contains("verify-e2e-harness.mjs")) {
    # No usar un here-string como ancla exacta: en Windows Git puede materializar este
    # archivo con CRLF aunque el repositorio conserve LF. Buscamos la linea estable
    # del primer test y hacemos la insercion conservando el EOL local.
    $unitTestMarker = "dotnet test tests/UnitTests/MusicaAprender.UnitTests.csproj --no-build --no-restore"
    $markerIndex = $quality.IndexOf($unitTestMarker, [System.StringComparison]::Ordinal)

    if ($markerIndex -lt 0) {
        throw "No se encontro el marcador estable de pruebas unitarias en scripts/check-quality.ps1."
    }

    $prefix = $quality.Substring(0, $markerIndex)
    if (-not $prefix.Contains('& "$PSScriptRoot/restore-and-build.ps1"')) {
        throw "No se encontro restore-and-build.ps1 antes de las pruebas unitarias en scripts/check-quality.ps1."
    }

    $eol = if ($quality.Contains("`r`n")) { "`r`n" } else { "`n" }
    $insertion = @(
        'node scripts/frontend/verify-e2e-harness.mjs',
        'Assert-LastExitCode "Verificador BL-MVP-022"',
        '',
        'npm.cmd run typecheck:e2e',
        'Assert-LastExitCode "TypeScript E2E"',
        '',
        'npm.cmd run test:e2e',
        'Assert-LastExitCode "Playwright E2E"',
        ''
    ) -join $eol

    $quality = $prefix + $insertion + $quality.Substring($markerIndex)
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText(
        $qualityPath,
        ($quality.TrimEnd("`r", "`n") + $eol),
        $utf8Bom
    )
}

Write-Host "Actualizando package-lock.json con las dependencias E2E fijadas..."
npm.cmd install --package-lock-only --ignore-scripts
Assert-LastExitCode "Actualizacion package-lock"

Write-Host "Restaurando dependencias desde lockfile..."
npm.cmd ci
Assert-LastExitCode "npm ci"

Write-Host "Instalando Chromium de Playwright para la validacion local..."
npm.cmd run test:e2e:install
Assert-LastExitCode "Instalacion Chromium Playwright"

Write-Host "Formateando archivos..."
npm.cmd run format
Assert-LastExitCode "npm format"

Write-Host "Verificando regresiones frontend BL-MVP-018 a BL-MVP-021..."
node scripts/frontend/verify-design-tokens.mjs
Assert-LastExitCode "Verificador BL-MVP-018"
node scripts/frontend/verify-accessible-components.mjs
Assert-LastExitCode "Verificador BL-MVP-019"
node scripts/frontend/verify-app-shell.mjs
Assert-LastExitCode "Verificador BL-MVP-020"
node scripts/frontend/verify-http-client.mjs
Assert-LastExitCode "Verificador BL-MVP-021"

Write-Host "Verificando estructura del arnes BL-MVP-022..."
node scripts/frontend/verify-e2e-harness.mjs
Assert-LastExitCode "Verificador BL-MVP-022"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

Write-Host "Ejecutando puerta local de calidad, incluido Playwright E2E..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-022 preparado y puerta local E2E aprobada."
Write-Host "La evidencia de navegador queda bajo artifacts/e2e y esta ignorada por Git."
Write-Host "Siguiente: enviar la salida completa antes de revisar Git."

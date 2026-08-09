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
    "apps/web/src/data/http/types.ts",
    "apps/web/src/data/http/retry-policy.ts",
    "apps/web/src/data/http/read-cache.ts",
    "apps/web/src/data/http/problem-details.ts",
    "apps/web/src/data/http/request-state.ts",
    "apps/web/src/data/http/http-client.ts",
    "apps/web/src/data/http/index.ts",
    "apps/web/src/data/http/HttpClientContractFixture.ts",
    "infrastructure/containers/web/nginx.conf",
    "scripts/frontend/verify-http-client.mjs",
    "docs/engineering/frontend/http-data-client.md",
    "BL-MVP-021_README.md"
)

foreach ($relativePath in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath))) {
        throw "Falta el archivo del parche BL-MVP-021: $relativePath"
    }
}

$workflowPath = Join-Path $RepoRoot ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)

if (-not $workflow.Contains("Verify typed HTTP client and ProblemDetails")) {
    $anchor = @'
      - name: Verify app shell and route boundaries
        run: node scripts/frontend/verify-app-shell.mjs

      - name: Formatting check
'@

    $replacement = @'
      - name: Verify app shell and route boundaries
        run: node scripts/frontend/verify-app-shell.mjs

      - name: Verify typed HTTP client and ProblemDetails
        run: node scripts/frontend/verify-http-client.mjs

      - name: Formatting check
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla esperada de CI para BL-MVP-021."
    }

    $workflow = $workflow.Replace($anchor, $replacement)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($workflowPath, ($workflow.TrimEnd("`r", "`n") + "`n"), $utf8)
}

Write-Host "Formateando archivos..."
npm.cmd run format
Assert-LastExitCode "npm format"

Write-Host "Verificando tokens visuales heredados..."
node scripts/frontend/verify-design-tokens.mjs
Assert-LastExitCode "Verificador BL-MVP-018"

Write-Host "Verificando componentes accesibles heredados..."
node scripts/frontend/verify-accessible-components.mjs
Assert-LastExitCode "Verificador BL-MVP-019"

Write-Host "Verificando app shell y rutas heredadas..."
node scripts/frontend/verify-app-shell.mjs
Assert-LastExitCode "Verificador BL-MVP-020"

Write-Host "Verificando cliente HTTP tipado y ProblemDetails..."
node scripts/frontend/verify-http-client.mjs
Assert-LastExitCode "Verificador BL-MVP-021"

Write-Host "Validando TypeScript..."
npm.cmd run typecheck
Assert-LastExitCode "TypeScript"

Write-Host "Construyendo frontend..."
npm.cmd run build
Assert-LastExitCode "Build frontend"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

Write-Host "Ejecutando puerta local de calidad..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-021 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "No hay una pantalla nueva: BL-MVP-021 es un habilitador del cliente de datos."

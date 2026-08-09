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
    "apps/web/src/app/App.tsx",
    "apps/web/src/app/access/AccessContext.tsx",
    "apps/web/src/app/access/AccessBoundary.tsx",
    "apps/web/src/app/router/AppRouter.tsx",
    "apps/web/src/app/router/route-manifest.ts",
    "apps/web/src/app/router/match-route.ts",
    "apps/web/src/app/router/navigation.tsx",
    "apps/web/src/app/shell/AppShell.tsx",
    "apps/web/src/app/shell/PublicHeader.tsx",
    "apps/web/src/app/shell/StudentNav.tsx",
    "apps/web/src/app/shell/BackofficeShell.tsx",
    "apps/web/src/app/shell/shell.css",
    "apps/web/src/routes/shared/RoutePlaceholder.tsx",
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/student/StudentArea.tsx",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/administration/AdministrationArea.tsx",
    "apps/web/src/components/ui/AccessibilityContractFixture.tsx",
    "scripts/frontend/verify-design-tokens.mjs",
    "scripts/frontend/verify-accessible-components.mjs",
    "scripts/frontend/verify-app-shell.mjs",
    "docs/engineering/frontend/design-tokens.md",
    "docs/engineering/frontend/accessible-components.md",
    "docs/engineering/frontend/app-shell-routing.md",
    "BL-MVP-020_README.md"
)

foreach ($relativePath in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath))) {
        throw "Falta el archivo del parche BL-MVP-020: $relativePath"
    }
}

$workflowPath = Join-Path $RepoRoot ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)

if (-not $workflow.Contains("Verify app shell and route boundaries")) {
    $anchor = @'
      - name: Verify accessible essential components
        run: node scripts/frontend/verify-accessible-components.mjs

      - name: Formatting check
'@

    $replacement = @'
      - name: Verify accessible essential components
        run: node scripts/frontend/verify-accessible-components.mjs

      - name: Verify app shell and route boundaries
        run: node scripts/frontend/verify-app-shell.mjs

      - name: Formatting check
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla esperada de CI para BL-MVP-020."
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

Write-Host "Verificando app shell, rutas y fronteras visibles..."
node scripts/frontend/verify-app-shell.mjs
Assert-LastExitCode "Verificador BL-MVP-020"

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
Write-Host "OK: BL-MVP-020 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    abrir http://localhost:5173 y validar rutas, fronteras y reflujo."

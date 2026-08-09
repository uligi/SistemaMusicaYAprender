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
    "apps/web/src/components/ui/Button.tsx",
    "apps/web/src/components/ui/Link.tsx",
    "apps/web/src/components/ui/Field.tsx",
    "apps/web/src/components/ui/SelectField.tsx",
    "apps/web/src/components/ui/Dialog.tsx",
    "apps/web/src/components/ui/DataTable.tsx",
    "apps/web/src/components/ui/Tabs.tsx",
    "apps/web/src/components/ui/Alert.tsx",
    "apps/web/src/components/ui/StateMessage.tsx",
    "apps/web/src/components/ui/ui.css",
    "scripts/frontend/verify-accessible-components.mjs",
    "docs/engineering/frontend/accessible-components.md",
    "BL-MVP-019_README.md"
)

foreach ($relativePath in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath))) {
        throw "Falta el archivo del parche BL-MVP-019: $relativePath"
    }
}

$workflowPath = Join-Path $RepoRoot ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)

if (-not $workflow.Contains("Verify accessible essential components")) {
    $anchor = @'
      - name: Verify versioned visual tokens
        run: node scripts/frontend/verify-design-tokens.mjs

      - name: Formatting check
'@

    $replacement = @'
      - name: Verify versioned visual tokens
        run: node scripts/frontend/verify-design-tokens.mjs

      - name: Verify accessible essential components
        run: node scripts/frontend/verify-accessible-components.mjs

      - name: Formatting check
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla esperada de CI para BL-MVP-019."
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

Write-Host "Verificando componentes accesibles..."
node scripts/frontend/verify-accessible-components.mjs
Assert-LastExitCode "Verificador BL-MVP-019"

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
Write-Host "OK: BL-MVP-019 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    abrir http://localhost:5173 y validar teclado, foco y reflujo."

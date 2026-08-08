$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$workflowPath = Join-Path $RepoRoot ".github\workflows\ci.yml"
if (-not (Test-Path $workflowPath)) {
    throw "No se encontro .github\workflows\ci.yml."
}

$content = Get-Content $workflowPath -Raw

$expected = @(
    "actions/checkout@v7",
    "actions/setup-dotnet@v6",
    "actions/setup-node@v7",
    "actions/upload-artifact@v7"
)

foreach ($action in $expected) {
    if (-not $content.Contains($action)) {
        throw "El workflow no contiene la version esperada: $action"
    }
}

if ($content -match "actions/(checkout|setup-dotnet|setup-node|upload-artifact)@v4") {
    throw "Todavia existe una Action principal en v4."
}

Write-Host "OK: GitHub Actions principales actualizadas a runtimes modernos."

npm.cmd exec -- prettier .github/workflows/ci.yml --write
Assert-LastExitCode "Prettier de ci.yml"

npm.cmd run format:check
Assert-LastExitCode "Verificacion de formato"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-004C validado localmente."
Write-Host "Haga commit y push para confirmar que desaparece la advertencia de Node.js 20."

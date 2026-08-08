$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$IssueTemplate = Join-Path $Root ".github\ISSUE_TEMPLATE\implementation.yml"
$IssueConfig = Join-Path $Root ".github\ISSUE_TEMPLATE\config.yml"
$PrTemplate = Join-Path $Root ".github\pull_request_template.md"

$requiredFiles = @($IssueTemplate, $IssueConfig, $PrTemplate)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        throw "Falta archivo de gobierno requerido: $file"
    }
}

# Windows PowerShell 5.1 no interpreta siempre UTF-8 sin BOM correctamente con Get-Content.
# Leemos explicitamente como UTF-8 para conservar textos como "Revision/Revisión".
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$issue = [System.IO.File]::ReadAllText($IssueTemplate, $Utf8)
$pr = [System.IO.File]::ReadAllText($PrTemplate, $Utf8)

$issueMarkers = @(
    "id: backlog_id",
    "id: phase",
    "id: epic",
    "id: traceability",
    "id: acceptance",
    "id: data_permissions",
    "id: dependencies",
    "id: data_risk",
    "id: security_risk",
    "id: evidence",
    "id: done"
)

foreach ($marker in $issueMarkers) {
    if (-not $issue.Contains($marker)) {
        throw "La plantilla de issue no exige el campo: $marker"
    }
}

$requiredCount = ([regex]::Matches($issue, "required:\s*true")).Count
if ($requiredCount -lt 11) {
    throw "La plantilla de issue tiene menos campos obligatorios de los esperados ($requiredCount < 11)."
}

$prMarkers = @(
    "## Issue / backlog",
    "## Trazabilidad",
    "## Datos y permisos",
    "## Riesgos",
    "## Pruebas ejecutadas",
    "## Evidencia",
    "## Revisión requerida",
    "## Definition of Done"
)

foreach ($marker in $prMarkers) {
    if (-not $pr.Contains($marker)) {
        throw "La plantilla de PR no contiene la seccion requerida: $marker"
    }
}

Write-Host "OK: plantillas de issue, PR y trazabilidad BL-MVP-005 verificadas."

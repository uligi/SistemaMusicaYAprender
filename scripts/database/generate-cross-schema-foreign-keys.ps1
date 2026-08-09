$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Get-DotEnvValue([string]$Name, [string]$DefaultValue) {
    if (-not (Test-Path ".env")) {
        return $DefaultValue
    }

    $match = Get-Content ".env" |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

$dbAdmin = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"

if ($dbAdmin -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$' -or
    $dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "Configuracion PostgreSQL local no cumple el formato seguro esperado."
}

$targetDirectory = Join-Path $Root "database\postgresql\ef-model"
$targetPath = Join-Path $targetDirectory "cross-schema-foreign-keys.json"

New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null

Write-Host "Generando manifiesto de FK transversales desde pg_catalog..."

$output = & docker compose exec -T postgres `
    psql -X -A -t -U $dbAdmin -d $dbName -v ON_ERROR_STOP=1 `
    -f /workspace/database/postgresql/ef-model/query_cross_schema_foreign_keys.sql

if ($LASTEXITCODE -ne 0) {
    throw "No se pudo generar el manifiesto de FK transversales."
}

$json = ($output -join "`n").Trim()

if ([string]::IsNullOrWhiteSpace($json)) {
    throw "PostgreSQL no devolvio el manifiesto de FK transversales."
}

try {
    $parsed = $json | ConvertFrom-Json
}
catch {
    throw "El manifiesto de FK transversales no es JSON valido: $($_.Exception.Message)"
}

if ($parsed.backlogItem -ne "BL-MVP-014") {
    throw "El manifiesto generado no pertenece a BL-MVP-014."
}

[System.IO.File]::WriteAllText(
    $targetPath,
    $json + "`n",
    (New-Object System.Text.UTF8Encoding($false)))

Write-Host "OK: manifiesto generado en database/postgresql/ef-model/cross-schema-foreign-keys.json."

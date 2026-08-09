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

$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"

& "$PSScriptRoot/prepare-database-access.ps1" -Database $dbName

Write-Host "Verificando modelos EF Core contra pg_catalog..."

dotnet run `
    --project tools/DatabaseModelVerifier/MusicaAprender.DatabaseModelVerifier.csproj `
    -- `
    --host 127.0.0.1 `
    --port $dbPort `
    --database $dbName `
    --secret-directory (Join-Path $Root "secrets\local") `
    --repository-root $Root `
    --summary (Join-Path $Root "artifacts\postgres\ef-model-summary.txt")

if ($LASTEXITCODE -ne 0) {
    throw "DatabaseModelVerifier fallo con codigo de salida $LASTEXITCODE."
}

Write-Host "OK: BL-MVP-014 validado localmente contra PostgreSQL 18."

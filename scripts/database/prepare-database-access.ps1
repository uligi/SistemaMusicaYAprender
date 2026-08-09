param(
    [Parameter(Mandatory = $true)]
    [string]$Database
)

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

if ($Database -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "Database no cumple el formato seguro esperado."
}

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_USER local no cumple el formato seguro esperado."
}

$sqlPath = "/workspace/database/postgresql/security/02_database_access.sql"

Write-Host "Aplicando minimo privilegio sobre la base '$Database'..."
docker compose exec -T postgres `
    psql -U $dbUser -d $Database -v ON_ERROR_STOP=1 `
    -v "database_name=$Database" -f $sqlPath

if ($LASTEXITCODE -ne 0) {
    throw "No se pudo preparar el acceso minimo de '$Database'."
}

Write-Host "OK: acceso minimo de base preparado para '$Database'."

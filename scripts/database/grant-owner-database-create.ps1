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

function Assert-SafeIdentifier([string]$Value, [string]$Name) {
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "$Name no cumple el formato seguro esperado."
    }
}

Assert-SafeIdentifier $Database "Database"

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
Assert-SafeIdentifier $dbUser "POSTGRES_USER"

$sql = "GRANT CREATE ON DATABASE `"$Database`" TO jp_owner;"

Write-Host "Concediendo a jp_owner CREATE sobre la base '$Database'..."

docker compose exec -T postgres `
    psql -U $dbUser -d postgres -v ON_ERROR_STOP=1 -c $sql

if ($LASTEXITCODE -ne 0) {
    throw "No se pudo conceder CREATE ON DATABASE a jp_owner."
}

Write-Host "OK: jp_owner puede crear los esquemas fisicos en '$Database'."

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

$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"
$dbMigrator = "jp_login_migrator"

Assert-SafeIdentifier $dbName "POSTGRES_DB"
Assert-SafeIdentifier $dbMigrator "Database migrator login"

$secretPath = Join-Path $Root "secrets\local\postgres_migrator_password"
if (-not (Test-Path $secretPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_migrator_password."
}

& "$PSScriptRoot/apply-login-identities.ps1"
& "$PSScriptRoot/prepare-database-access.ps1" -Database $dbName

Write-Host "Aplicando migracion EF Core embebida con identidad separada '$dbMigrator'..."

dotnet run `
    --project tools/DatabaseMigrator/MusicaAprender.DatabaseMigrator.csproj `
    -- `
    --host 127.0.0.1 `
    --port $dbPort `
    --database $dbName `
    --username $dbMigrator `
    --password-file $secretPath

if ($LASTEXITCODE -ne 0) {
    throw "DatabaseMigrator fallo con codigo de salida $LASTEXITCODE."
}

# Normaliza ownership de __EFMigrationsHistory tambien en instalaciones nuevas.
& "$PSScriptRoot/prepare-database-access.ps1" -Database $dbName

Write-Host "OK: migracion inicial aplicada con identidad de migracion separada."

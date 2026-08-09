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

$dbAdmin = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"
$dbMigrator = "jp_login_migrator"
$tempDb = "musica_aprender_bl_mvp_011"

Assert-SafeIdentifier $dbAdmin "POSTGRES_USER"
Assert-SafeIdentifier $dbMigrator "Database migrator login"
Assert-SafeIdentifier $tempDb "Base temporal"

$migratorSecretPath = Join-Path $Root "secrets\local\postgres_migrator_password"
if (-not (Test-Path $migratorSecretPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_migrator_password."
}

docker compose up --detach postgres
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo iniciar PostgreSQL."
}

try {
    Write-Host "Creando base PostgreSQL 18 vacia para regresion BL-MVP-011/012..."

    $dropSql = "DROP DATABASE IF EXISTS `"$tempDb`" WITH (FORCE);"
    $createSql = "CREATE DATABASE `"$tempDb`" OWNER `"$dbAdmin`";"

    docker compose exec -T postgres `
        psql -U $dbAdmin -d postgres -v ON_ERROR_STOP=1 -c $dropSql -c $createSql

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo crear la base temporal vacia."
    }

    Write-Host "Aplicando bootstrap DBA a la base temporal..."
    docker compose exec -T postgres `
        psql -U $dbAdmin -d $tempDb -v ON_ERROR_STOP=1 `
        -f /docker-entrypoint-initdb.d/00_bootstrap_roles_extensions.sql

    if ($LASTEXITCODE -ne 0) {
        throw "El bootstrap fallo en la base temporal."
    }

    & "$PSScriptRoot/apply-login-identities.ps1"
    & "$PSScriptRoot/prepare-database-access.ps1" -Database $tempDb

    $beforeCount = docker compose exec -T postgres `
        psql -U $dbAdmin -d $tempDb -tA -v ON_ERROR_STOP=1 `
        -c "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname IN ('identity','security','catalog','content','learning','progress','editorial','configuration','ops');"

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo comprobar que la base temporal estuviera vacia."
    }

    if ($beforeCount.Trim() -ne "0") {
        throw "La base temporal no esta vacia antes de migrar. Tablas: $($beforeCount.Trim())."
    }

    Write-Host "Ejecutando InitialPhysicalSchema como '$dbMigrator'..."
    dotnet run `
        --project tools/DatabaseMigrator/MusicaAprender.DatabaseMigrator.csproj `
        -- `
        --host 127.0.0.1 `
        --port $dbPort `
        --database $tempDb `
        --username $dbMigrator `
        --password-file $migratorSecretPath

    if ($LASTEXITCODE -ne 0) {
        throw "La migracion EF Core fallo con la identidad separada."
    }

    & "$PSScriptRoot/prepare-database-access.ps1" -Database $tempDb

    Write-Host "Verificando 109 tablas, invariantes fisicos y semillas..."
    docker compose exec -T postgres `
        psql -U $dbAdmin -d $tempDb -v ON_ERROR_STOP=1 `
        -f /workspace/database/postgresql/tests/verify_initial_migration.sql

    if ($LASTEXITCODE -ne 0) {
        throw "La verificacion fisica de regresion fallo."
    }

    Write-Host "OK: una base vacia se migra con jp_login_migrator y conserva BL-MVP-011."
}
finally {
    Write-Host "Eliminando base temporal de verificacion..."
    $dropSql = "DROP DATABASE IF EXISTS `"$tempDb`" WITH (FORCE);"

    docker compose exec -T postgres `
        psql -U $dbAdmin -d postgres -v ON_ERROR_STOP=1 -c $dropSql *> $null
}

Write-Host "OK: regresion de migracion vacia aprobada con identidad separada."

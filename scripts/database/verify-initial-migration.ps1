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

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbPort = Get-DotEnvValue "POSTGRES_PORT" "5432"
$tempDb = "musica_aprender_bl_mvp_011"

Assert-SafeIdentifier $dbUser "POSTGRES_USER"
Assert-SafeIdentifier $tempDb "Base temporal"

$secretPath = Join-Path $Root "secrets\local\postgres_password"
if (-not (Test-Path $secretPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

docker compose up --detach postgres
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo iniciar PostgreSQL."
}

try {
    Write-Host "Creando base PostgreSQL 18 vacia para BL-MVP-011..."

    $dropSql = "DROP DATABASE IF EXISTS `"$tempDb`" WITH (FORCE);"
    $createSql = "CREATE DATABASE `"$tempDb`" OWNER `"$dbUser`";"

    docker compose exec -T postgres `
        psql -U $dbUser -d postgres -v ON_ERROR_STOP=1 -c $dropSql -c $createSql

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo crear la base temporal vacia."
    }

    Write-Host "Aplicando bootstrap DBA a la base temporal..."
    docker compose exec -T postgres `
        psql -U $dbUser -d $tempDb -v ON_ERROR_STOP=1 `
        -f /docker-entrypoint-initdb.d/00_bootstrap_roles_extensions.sql

    if ($LASTEXITCODE -ne 0) {
        throw "El bootstrap fallo en la base temporal."
    }

    # 01_initial_schema.sql ejecuta SET LOCAL ROLE jp_owner antes de crear
    # los nueve esquemas. El rol propietario necesita CREATE sobre la base.
    & "$PSScriptRoot/grant-owner-database-create.ps1" -Database $tempDb

    $beforeCount = docker compose exec -T postgres `
        psql -U $dbUser -d $tempDb -tA -v ON_ERROR_STOP=1 `
        -c "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname IN ('identity','security','catalog','content','learning','progress','editorial','configuration','ops');"

    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo comprobar que la base temporal estuviera vacia."
    }

    if ($beforeCount.Trim() -ne "0") {
        throw "La base temporal no esta vacia antes de migrar. Tablas: $($beforeCount.Trim())."
    }

    Write-Host "Ejecutando InitialPhysicalSchema usando recursos embebidos..."
    dotnet run `
        --project tools/DatabaseMigrator/MusicaAprender.DatabaseMigrator.csproj `
        -- `
        --host 127.0.0.1 `
        --port $dbPort `
        --database $tempDb `
        --username $dbUser `
        --password-file $secretPath

    if ($LASTEXITCODE -ne 0) {
        throw "La migracion EF Core fallo en la base temporal."
    }

    Write-Host "Verificando 109 tablas, invariantes fisicos y semillas..."
    docker compose exec -T postgres `
        psql -U $dbUser -d $tempDb -v ON_ERROR_STOP=1 `
        -f /workspace/database/postgresql/tests/verify_initial_migration.sql

    if ($LASTEXITCODE -ne 0) {
        throw "La verificacion BL-MVP-011 fallo."
    }

    Write-Host "OK: una base vacia termina con la linea base fisica y semillas esperadas."
}
finally {
    Write-Host "Eliminando base temporal de verificacion..."
    $dropSql = "DROP DATABASE IF EXISTS `"$tempDb`" WITH (FORCE);"

    docker compose exec -T postgres `
        psql -U $dbUser -d postgres -v ON_ERROR_STOP=1 -c $dropSql *> $null
}

Write-Host "OK: BL-MVP-011 validado sobre una base PostgreSQL 18 creada desde cero."

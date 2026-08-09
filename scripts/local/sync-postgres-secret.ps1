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

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
$dbName = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"

if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_USER local no cumple el formato seguro esperado."
}

if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_DB local no cumple el formato seguro esperado."
}

$secretPath = Join-Path $Root "secrets\local\postgres_password"
if (-not (Test-Path $secretPath)) {
    throw "Falta secrets/local/postgres_password."
}

$password = [System.IO.File]::ReadAllText($secretPath).Trim()
if ($password -notmatch '^[A-Za-z0-9_-]{24,256}$') {
    throw "El secreto PostgreSQL local contiene un formato no permitido."
}

Write-Host "Asegurando que PostgreSQL este iniciado..."
docker compose up --detach postgres
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo iniciar PostgreSQL."
}

$ready = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    docker compose exec -T postgres pg_isready -U $dbUser -d $dbName *> $null

    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $ready) {
    throw "PostgreSQL no quedo listo a tiempo."
}

$sql = "ALTER ROLE `"$dbUser`" WITH PASSWORD '$password';"

$sql | docker compose exec -T postgres `
    psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo sincronizar la contrasena PostgreSQL con el secret store local."
}

Write-Host "OK: credencial PostgreSQL sincronizada con el secret store local."

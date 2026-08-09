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

function Read-DatabaseSecret([string]$Name) {
    $path = Join-Path $Root "secrets\local\$Name"

    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta secrets/local/$Name."
    }

    $value = [System.IO.File]::ReadAllText($path).Trim()

    if ($value -notmatch '^[A-Fa-f0-9]{48,256}$') {
        throw "El secreto '$Name' no cumple el formato seguro esperado."
    }

    return $value
}

$dbUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw "POSTGRES_USER local no cumple el formato seguro esperado."
}

$passwords = @{
    jp_login_migrator   = Read-DatabaseSecret "postgres_migrator_password"
    jp_login_api        = Read-DatabaseSecret "postgres_api_password"
    jp_login_backoffice = Read-DatabaseSecret "postgres_backoffice_password"
    jp_login_worker     = Read-DatabaseSecret "postgres_worker_password"
    jp_login_readonly   = Read-DatabaseSecret "postgres_readonly_password"
}

$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine("SET password_encryption = 'scram-sha-256';")

foreach ($roleName in @(
    "jp_login_migrator",
    "jp_login_api",
    "jp_login_backoffice",
    "jp_login_worker",
    "jp_login_readonly"
)) {
    [void]$sql.AppendLine(
        "ALTER ROLE `"$roleName`" WITH PASSWORD '$($passwords[$roleName])';")
}

$sql.ToString() | docker compose exec -T postgres `
    psql -U $dbUser -d postgres -v ON_ERROR_STOP=1 *> $null

if ($LASTEXITCODE -ne 0) {
    throw "No se pudieron sincronizar las credenciales LOGIN PostgreSQL."
}

Write-Host "OK: credenciales PostgreSQL separadas sincronizadas desde el secret store."

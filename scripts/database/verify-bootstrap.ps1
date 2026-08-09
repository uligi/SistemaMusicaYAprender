$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

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

Write-Host "Probando idempotencia: ejecutando el bootstrap una segunda vez..."
& "$PSScriptRoot/apply-bootstrap.ps1"

$containerVerify = "/workspace/database/postgresql/tests/verify_bootstrap.sql"

Write-Host "Verificando roles, extensiones, membresia y privilegios PUBLIC..."
docker compose exec -T `
    -w /workspace `
    postgres `
    psql -U $dbUser -d $dbName -v ON_ERROR_STOP=1 -f $containerVerify
Assert-LastExitCode "Verificacion del bootstrap PostgreSQL"

Write-Host "OK: BL-MVP-010 es idempotente y cumple el bootstrap esperado."

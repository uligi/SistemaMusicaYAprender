[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipConfigurationSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Correction
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Falta '$Name'. $Correction"
    }
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if (-not (Test-Path ".env" -PathType Leaf)) {
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

function Invoke-MinimumConfigurationSql {
    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"

    if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_USER local no cumple el formato seguro esperado."
    }

    if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_DB local no cumple el formato seguro esperado."
    }

    $verificationPath = Join-Path $RepoRoot "database/postgresql/tests/verify_minimum_effective_configuration.sql"
    Get-Content -Raw -Encoding UTF8 $verificationPath |
        docker compose exec -T postgres `
            psql `
            --username $dbUser `
            --dbname $dbName `
            --no-password `
            --set ON_ERROR_STOP=1 `
            --file=-
    Assert-LastExitCode "Publicacion minima en PostgreSQL"
}

function Test-MinimumConfiguration {
    $apiPort = Get-DotEnvValue -Name "API_PORT" -DefaultValue "5080"
    if ($apiPort -notmatch '^\d{1,5}$' -or [int]$apiPort -gt 65535) {
        throw "API_PORT local no es un puerto valido."
    }

    Invoke-MinimumConfigurationSql

    $dependencies = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$apiPort/health/dependencies" `
        -TimeoutSec 10
    $minimumCheck = @(
        $dependencies.checks |
            Where-Object { $_.name -eq "minimum-configuration" }
    )

    if ($minimumCheck.Count -ne 1) {
        throw "La API no publico exactamente un health check minimum-configuration."
    }

    if ($minimumCheck[0].status -ne "Healthy") {
        throw "minimum-configuration reporto $($minimumCheck[0].status), se esperaba Healthy."
    }

    Write-Host "OK: BL-MVP-035 verificado contra PostgreSQL y el health check real de API."
}

$requiredFiles = @(
    ".prettierignore",
    ".github/workflows/ci.yml",
    "apps/api/Health/MinimumConfigurationHealthCheck.cs",
    "apps/api/Program.cs",
    "database/postgresql/tests/verify_minimum_effective_configuration.sql",
    "docs/engineering/configuration/minimum-effective-configuration.md",
    "scripts/ci/configuration/verify-minimum-effective-configuration.sh",
    "scripts/ci/identity/verify-personal-registration.sh",
    "src/Modules/Configuration/Infrastructure/Publication/MinimumPublishedConfigurationReader.cs",
    "src/Modules/Security/Infrastructure/Authorization/MinimumRoleCatalogReader.cs",
    "BL-MVP-035_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-035.md"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-035: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

git merge-base --is-ancestor b8ec17b HEAD
Assert-LastExitCode "Comprobacion de la base publicada BL-MVP-023 (b8ec17b)"

& "$PSScriptRoot/check-toolchain.ps1"

docker version *> $null
Assert-LastExitCode "Docker Engine"
docker compose version *> $null
Assert-LastExitCode "Docker Compose"

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

if (-not $SkipBrowserInstall) {
    Write-Host "Instalando Chromium fijado por Playwright..."
    npm.cmd ci
    Assert-LastExitCode "npm ci"
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalacion Chromium Playwright"
}

if (-not $SkipQualityGate) {
    Write-Host "Ejecutando la puerta local completa de calidad..."
    & "$PSScriptRoot/check-quality.ps1"
}

if (-not $SkipStart) {
    Write-Host "Iniciando el entorno local reproducible..."
    & "$PSScriptRoot/local/start.ps1"
    & "$PSScriptRoot/local/verify-running.ps1"

    if (-not $SkipConfigurationSmoke) {
        Test-MinimumConfiguration
    }
}

$generatedTypeScriptState = git status --porcelain -- "apps/web/tsconfig.app.tsbuildinfo"
Assert-LastExitCode "Consulta del archivo incremental TypeScript"
if (-not [string]::IsNullOrWhiteSpace(($generatedTypeScriptState | Out-String))) {
    git restore -- "apps/web/tsconfig.app.tsbuildinfo"
    Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
    Write-Host "Restaurado apps/web/tsconfig.app.tsbuildinfo por ser salida incremental."
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short "--untracked-files=all"
Assert-LastExitCode "git status"
Write-Host ""
git diff --stat
Assert-LastExitCode "git diff --stat"
Write-Host ""
git diff --name-only
Assert-LastExitCode "git diff --name-only"

Write-Host ""
if ($SkipQualityGate -or $SkipStart -or $SkipConfigurationSmoke) {
    Write-Warning "BL-MVP-035 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-035 instalado y validado localmente con API, PostgreSQL y la puerta completa."
}
Write-Host "API readiness:    http://localhost:5080/health/ready"
Write-Host "API dependencies: http://localhost:5080/health/dependencies"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

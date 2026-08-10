[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipConsentSmoke
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

function Resolve-GitBash {
    $gitCommand = Get-Command "git.exe" -ErrorAction Stop
    $gitDirectory = Split-Path -Parent $gitCommand.Source
    $candidates = @(
        (Join-Path $gitDirectory "..\bin\bash.exe"),
        (Join-Path $gitDirectory "..\usr\bin\bash.exe"),
        (Join-Path $gitDirectory "bash.exe"),
        (Join-Path $gitDirectory "..\..\usr\bin\bash.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Git Bash no esta disponible junto a git.exe. Repare Git for Windows y vuelva a ejecutar el instalador."
}

function Invoke-VersionedConsentSmoke {
    param([Parameter(Mandatory = $true)][string]$BashPath)

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $apiPort = Get-DotEnvValue -Name "API_PORT" -DefaultValue "5080"

    if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_USER local no cumple el formato seguro esperado."
    }

    if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_DB local no cumple el formato seguro esperado."
    }

    if ($dbPort -notmatch '^\d{1,5}$' -or [int]$dbPort -gt 65535) {
        throw "POSTGRES_PORT local no es un puerto valido."
    }

    if ($apiPort -notmatch '^\d{1,5}$' -or [int]$apiPort -gt 65535) {
        throw "API_PORT local no es un puerto valido."
    }

    $postgresPasswordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
    if (-not (Test-Path $postgresPasswordPath -PathType Leaf)) {
        throw "Falta el secreto local postgres_password."
    }

    $environmentNames = @(
        "PGHOST",
        "PGPORT",
        "PGUSER",
        "PGDATABASE",
        "PGPASSWORD",
        "BL024_USE_RUNNING_API",
        "BL024_USE_DOCKER_PSQL",
        "BL024_API_URL"
    )
    $previousEnvironment = @{}

    foreach ($name in $environmentNames) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        $previousEnvironment[$name] = $value
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = $dbPort
        $env:PGUSER = $dbUser
        $env:PGDATABASE = $dbName
        $env:PGPASSWORD = [System.IO.File]::ReadAllText($postgresPasswordPath).Trim()
        $env:BL024_USE_RUNNING_API = "true"
        $env:BL024_USE_DOCKER_PSQL = "true"
        $env:BL024_API_URL = "http://127.0.0.1:$apiPort"

        & $BashPath "./scripts/ci/identity/verify-personal-registration.sh"
        Assert-LastExitCode "Consentimientos versionados contra API y PostgreSQL"
    }
    finally {
        foreach ($name in $environmentNames) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $previousEnvironment[$name],
                "Process")
        }
    }
}

$requiredFiles = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationRequest.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs",
    "apps/web/src/routes/public/PersonalAccountRegistrationPage.tsx",
    "apps/web/src/routes/public/public-area.css",
    "docs/engineering/privacy/versioned-registration-consents.md",
    "scripts/ci/identity/verify-personal-registration.sh",
    "src/Modules/Identity/Application/Consent/RequiredRegistrationConsentPolicy.cs",
    "src/Modules/Identity/Infrastructure/Registration/IdentityConsentRegistrationWriter.cs",
    "tests/E2ETests/base-accessibility.spec.ts",
    "BL-MVP-024_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-024.md"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-024: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."
$bashPath = Resolve-GitBash

git merge-base --is-ancestor 44d716e HEAD
Assert-LastExitCode "Comprobacion de la base publicada BL-MVP-035 (44d716e)"

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

    if (-not $SkipConsentSmoke) {
        Invoke-VersionedConsentSmoke -BashPath $bashPath
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
if ($SkipQualityGate -or $SkipStart -or $SkipConsentSmoke) {
    Write-Warning "BL-MVP-024 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-024 instalado y validado localmente con API, PostgreSQL y navegador."
}
Write-Host "Web:              http://localhost:5173/registro"
Write-Host "Consentimientos:  http://localhost:5080/api/v1/auth/registration-consents"
Write-Host "API readiness:    http://localhost:5080/health/ready"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

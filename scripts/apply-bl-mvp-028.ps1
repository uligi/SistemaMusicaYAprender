[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipRegistrationSmoke,
    [switch]$SkipVerificationSmoke
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

function Invoke-IdentitySmokes {
    param(
        [Parameter(Mandatory = $true)][string]$BashPath,
        [Parameter(Mandatory = $true)][bool]$RunRegistration,
        [Parameter(Mandatory = $true)][bool]$RunVerification
    )

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $apiPort = Get-DotEnvValue -Name "API_PORT" -DefaultValue "5080"
    $mailpitPort = Get-DotEnvValue -Name "MAILPIT_HTTP_PORT" -DefaultValue "8025"

    if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_USER local no cumple el formato seguro esperado."
    }

    if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_DB local no cumple el formato seguro esperado."
    }

    foreach ($port in @($dbPort, $apiPort, $mailpitPort)) {
        if ($port -notmatch '^\d{1,5}$' -or [int]$port -gt 65535) {
            throw "La configuracion local contiene un puerto no valido."
        }
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
        "BL028_USE_RUNNING_API",
        "BL028_USE_DOCKER_PSQL",
        "BL028_API_URL",
        "BL025_USE_RUNNING_SERVICES",
        "BL025_USE_DOCKER_PSQL",
        "BL025_API_URL",
        "BL025_MAILPIT_API_BASE"
    )
    $previousEnvironment = @{}

    foreach ($name in $environmentNames) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = $dbPort
        $env:PGUSER = $dbUser
        $env:PGDATABASE = $dbName
        $env:PGPASSWORD = [System.IO.File]::ReadAllText($postgresPasswordPath).Trim()

        if ($RunRegistration) {
            $env:BL028_USE_RUNNING_API = "true"
            $env:BL028_USE_DOCKER_PSQL = "true"
            $env:BL028_API_URL = "http://127.0.0.1:$apiPort"

            & $BashPath "./scripts/ci/identity/verify-personal-registration.sh"
            Assert-LastExitCode "Politica, Argon2id y persistencia contra API y PostgreSQL"
        }

        if ($RunVerification) {
            $env:BL025_USE_RUNNING_SERVICES = "true"
            $env:BL025_USE_DOCKER_PSQL = "true"
            $env:BL025_API_URL = "http://127.0.0.1:$apiPort"
            $env:BL025_MAILPIT_API_BASE = "http://127.0.0.1:$mailpitPort"

            & $BashPath "./scripts/ci/identity/verify-account-verification.sh"
            Assert-LastExitCode "Regresion de verificacion contra API, worker, SMTP y PostgreSQL"
        }
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
    "Directory.Packages.props",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationRequest.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs",
    "apps/api/Program.cs",
    "apps/api/packages.lock.json",
    "apps/web/src/routes/public/PersonalAccountRegistrationPage.tsx",
    "apps/worker/packages.lock.json",
    "compose.yml",
    "config/secrets/manifest.json",
    "docs/engineering/security/argon2id-password-policy.md",
    "scripts/apply-bl-mvp-028.ps1",
    "scripts/ci/identity/verify-account-verification.sh",
    "scripts/ci/identity/verify-personal-registration.sh",
    "scripts/ci/security/create-compose-secrets.sh",
    "scripts/local/ensure-local-secrets.ps1",
    "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs",
    "src/Modules/Security/Infrastructure/Credentials/Argon2idPasswordHasher.cs",
    "src/Modules/Security/Infrastructure/Credentials/PasswordPolicy.cs",
    "src/Modules/Security/Infrastructure/Credentials/PasswordRequestFingerprintService.cs",
    "src/Modules/Security/Infrastructure/Registration/SecurityAccountRegistrationWriter.cs",
    "src/Modules/Security/MusicaAprender.Modules.Security.csproj",
    "src/Modules/Security/packages.lock.json",
    "tests/E2ETests/base-accessibility.spec.ts",
    "tests/IntegrationTests/packages.lock.json",
    "tests/UnitTests/Modules/Security/Argon2idPasswordHasherTests.cs",
    "tests/UnitTests/Modules/Security/PasswordPolicyTests.cs",
    "tests/UnitTests/Modules/Security/PasswordRequestFingerprintServiceTests.cs",
    "tests/UnitTests/packages.lock.json",
    "tools/DatabaseModelVerifier/packages.lock.json",
    "BL-MVP-028_README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-028.md"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-028: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."
$bashPath = Resolve-GitBash

git merge-base --is-ancestor e77dfabd303628f7106167defdd2b3ca6f033b0b HEAD
Assert-LastExitCode "Comprobacion de la base publicada BL-MVP-025 (e77dfab)"

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

    if (-not $SkipRegistrationSmoke -or -not $SkipVerificationSmoke) {
        Invoke-IdentitySmokes `
            -BashPath $bashPath `
            -RunRegistration (-not $SkipRegistrationSmoke) `
            -RunVerification (-not $SkipVerificationSmoke)
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
if ($SkipBrowserInstall -or
    $SkipQualityGate -or
    $SkipStart -or
    $SkipRegistrationSmoke -or
    $SkipVerificationSmoke) {
    Write-Warning "BL-MVP-028 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-028 instalado y validado localmente con política, Argon2id, PostgreSQL, API y navegador."
}
Write-Host "Registro:      http://localhost:5173/registro"
Write-Host "Verificacion:  http://localhost:5173/verificar-cuenta"
Write-Host "Mailpit:       http://localhost:8025"
Write-Host "API readiness: http://localhost:5080/health/ready"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

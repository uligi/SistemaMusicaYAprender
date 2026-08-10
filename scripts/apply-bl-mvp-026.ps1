[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipRegistrationSmoke,
    [switch]$SkipVerificationSmoke,
    [switch]$SkipLoginSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "60e71775dd6e85769bd6d8ace6bf5d9b4f6dc1ea"
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

function Assert-PackageInventory {
    param([Parameter(Mandatory = $true)][string[]]$AllowedPaths)

    git diff --cached --quiet
    Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($path in $AllowedPaths) {
        [void]$allowed.Add($path.Replace("\", "/"))
    }

    $unexpected = [System.Collections.Generic.List[string]]::new()
    $statusLines = @(git status --porcelain=v1 --untracked-files=all)
    Assert-LastExitCode "Inventario Git previo"

    foreach ($line in $statusLines) {
        if ($line.Length -lt 4) {
            [void]$unexpected.Add($line)
            continue
        }

        $relativePath = $line.Substring(3).Replace("\", "/")
        if ($relativePath.Contains(" -> ")) {
            $relativePath = ($relativePath -split " -> ", 2)[1]
        }

        if (-not $allowed.Contains($relativePath)) {
            [void]$unexpected.Add($relativePath)
        }
    }

    if ($unexpected.Count -gt 0) {
        throw "Hay cambios ajenos al paquete BL-MVP-026: $($unexpected -join ', '). Restaure o respalde esos cambios antes de continuar."
    }
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($stagedPaths.Count -gt 0) {
        throw "No se restaurara $relativePath porque contiene cambios staged. Revise el indice antes de continuar."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($trackedPaths.Count -eq 0) {
        throw "$relativePath debe estar rastreado en la base publicada."
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -eq 0) {
        return
    }

    git restore --worktree -- $relativePath
    Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
    Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
}

function Invoke-IdentitySmokes {
    param(
        [Parameter(Mandatory = $true)][string]$BashPath,
        [Parameter(Mandatory = $true)][bool]$RunRegistration,
        [Parameter(Mandatory = $true)][bool]$RunVerification,
        [Parameter(Mandatory = $true)][bool]$RunLogin
    )

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $apiPort = Get-DotEnvValue -Name "API_PORT" -DefaultValue "5080"
    $webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"
    $mailpitPort = Get-DotEnvValue -Name "MAILPIT_HTTP_PORT" -DefaultValue "8025"

    if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_USER local no cumple el formato seguro esperado."
    }

    if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_DB local no cumple el formato seguro esperado."
    }

    foreach ($port in @($dbPort, $apiPort, $webPort, $mailpitPort)) {
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
        "BL025_MAILPIT_API_BASE",
        "BL026_USE_RUNNING_API",
        "BL026_USE_DOCKER_PSQL",
        "BL026_API_URL"
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
            Assert-LastExitCode "Regresion de politica, Argon2id y registro"
        }

        if ($RunVerification) {
            $env:BL025_USE_RUNNING_SERVICES = "true"
            $env:BL025_USE_DOCKER_PSQL = "true"
            $env:BL025_API_URL = "http://127.0.0.1:$apiPort"
            $env:BL025_MAILPIT_API_BASE = "http://127.0.0.1:$mailpitPort"

            & $BashPath "./scripts/ci/identity/verify-account-verification.sh"
            Assert-LastExitCode "Regresion de verificacion contra API, worker, SMTP y PostgreSQL"
        }

        if ($RunLogin) {
            $env:BL026_USE_RUNNING_API = "true"
            $env:BL026_USE_DOCKER_PSQL = "true"
            $env:BL026_API_URL = "http://localhost:$webPort"

            & $BashPath "./scripts/ci/identity/verify-personal-login.sh"
            Assert-LastExitCode "Login, cookie segura, CSRF, expiracion y revocacion"
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
    "apps/api/Endpoints/Identity/PersonalAccountLoginEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountLoginRequest.cs",
    "apps/api/Endpoints/Identity/PersonalAccountLoginResponse.cs",
    "apps/api/Endpoints/Identity/PersonalAccountLoginService.cs",
    "apps/api/Program.cs",
    "apps/api/Security/SecuritySessionCookiePostConfigure.cs",
    "apps/api/Security/SecuritySessionTicketStore.cs",
    "apps/api/Security/SessionAuthenticationDefaults.cs",
    "apps/web/src/app/access/AccessBoundary.tsx",
    "apps/web/src/app/access/AccessContext.tsx",
    "apps/web/src/routes/public/PersonalAccountLoginPage.tsx",
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/public/public-area.css",
    "compose.yml",
    "config/secrets/manifest.json",
    "database/postgresql/security/02_database_access.sql",
    "docs/engineering/security/same-origin-session.md",
    "infrastructure/containers/web/nginx.local.conf",
    "scripts/apply-bl-mvp-026.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026D.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026E.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026F.md",
    "README/BL-MVP-026E_README.md",
    "README/BL-MVP-026F_README.md",
    "scripts/apply-bl-mvp-026d.ps1",
    "scripts/apply-bl-mvp-026e.ps1",
    "scripts/apply-bl-mvp-026f.ps1",
    "scripts/ci/identity/verify-personal-login.sh",
    "scripts/ci/security/create-compose-secrets.sh",
    "scripts/local/ensure-local-secrets.ps1",
    "src/Modules/Security/Infrastructure/Authentication/ActivePasswordCredential.cs",
    "src/Modules/Security/Infrastructure/Authentication/SecurityLoginPersistence.cs",
    "src/Modules/Security/Infrastructure/Authentication/SecuritySessionPersistence.cs",
    "src/Modules/Security/Infrastructure/Authentication/SecuritySessionTokenService.cs",
    "tests/E2ETests/base-accessibility.spec.ts",
    "tests/UnitTests/Modules/Security/SecuritySessionTokenServiceTests.cs",
    "README/BL-MVP-026A_README.md",
    "README/BL-MVP-026B_README.md",
    "README/BL-MVP-026C_README.md",
    "README/BL-MVP-026D_README.md",
    "README/BL-MVP-023_README.md",
    "README/BL-MVP-024_README.md",
    "README/BL-MVP-025_README.md",
    "README/BL-MVP-026_README.md",
    "README/BL-MVP-028_README.md",
    "README/BL-MVP-035_README.md",
    "README.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026.md"
)

$removedReadmePaths = @(
    "BL-MVP-023_README.md",
    "BL-MVP-024_README.md",
    "BL-MVP-025_README.md",
    "BL-MVP-028_README.md",
    "BL-MVP-035_README.md",
    "README/README.md"
)

$allowedPaths = @($requiredFiles + $removedReadmePaths)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-026: $relativePath"
    }
}

foreach ($relativePath in $removedReadmePaths) {
    if (Test-Path (Join-Path $RepoRoot $relativePath)) {
        throw "La reorganizacion README esta incompleta; la ruta antigua aun existe: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."
$bashPath = Resolve-GitBash

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-026 debe instalarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"
Restore-GeneratedTypeScriptState
Assert-PackageInventory -AllowedPaths $allowedPaths

try {
    & "$PSScriptRoot/check-toolchain.ps1"

    docker version *> $null
    Assert-LastExitCode "Docker Engine"
    docker compose version *> $null
    Assert-LastExitCode "Docker Compose"

    & "$PSScriptRoot/local/ensure-local-secrets.ps1"

    docker compose config --quiet
    Assert-LastExitCode "Validacion Docker Compose"

    if (-not $SkipBrowserInstall) {
        Write-Host "Restaurando paquetes y Chromium fijados..."
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

        if (-not $SkipRegistrationSmoke -or
            -not $SkipVerificationSmoke -or
            -not $SkipLoginSmoke) {
            Invoke-IdentitySmokes `
                -BashPath $bashPath `
                -RunRegistration (-not $SkipRegistrationSmoke) `
                -RunVerification (-not $SkipVerificationSmoke) `
                -RunLogin (-not $SkipLoginSmoke)
        }
    }
}
finally {
    Restore-GeneratedTypeScriptState
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
    $SkipVerificationSmoke -or
    $SkipLoginSmoke) {
    Write-Warning "BL-MVP-026 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-026 instalado y validado localmente con login, cookie segura, CSRF, expiracion y revocacion."
}
Write-Host "Acceso:        http://localhost:5173/acceso"
Write-Host "API readiness: http://localhost:5080/health/ready"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

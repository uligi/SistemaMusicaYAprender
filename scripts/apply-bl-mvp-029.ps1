[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipLoginRegression,
    [switch]$SkipLogoutRegression,
    [switch]$SkipAbuseSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "147e86ffe9b53435d7f277282f6c091aef3523d0"
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

    throw "Git Bash no esta disponible junto a git.exe."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"
    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($trackedPaths.Count -eq 0) {
        return
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Assert-PackageInventory {
    param([Parameter(Mandatory = $true)][string[]]$AllowedPaths)

    git diff --cached --quiet
    Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

    $allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
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

        $relativePath = $line.Substring(3).Trim('"').Replace("\", "/")
        if ($relativePath.Contains(" -> ")) {
            $relativePath = ($relativePath -split " -> ", 2)[1]
        }

        if (-not $allowed.Contains($relativePath)) {
            [void]$unexpected.Add($relativePath)
        }
    }

    if ($unexpected.Count -gt 0) {
        throw "Hay cambios ajenos al paquete BL-MVP-029: $($unexpected -join ', ')."
    }
}

function Replace-ExactText {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $path = Join-Path $RepoRoot $RelativePath
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

    if ($content.Contains($NewText)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    if (-not $content.Contains($OldText)) {
        throw "No se encontro el ancla exacta para: $Description"
    }

    $updated = $content.Replace($OldText, $NewText)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $updated, $utf8NoBom)
    Write-Host "OK: $Description."
}

function Patch-ExternalConfiguration {
    $path = "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs"

    $oldConstants = @'
    private const string IdentityPasswordFingerprintKeySecret =
        "identity_password_fingerprint_key";
'@
    $newConstants = @'
    private const string IdentityPasswordFingerprintKeySecret =
        "identity_password_fingerprint_key";
    private const string IdentityLoginAbuseKeySecret = "identity_login_abuse_key";
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldConstants `
        -NewText $newConstants `
        -Description "secreto de abuso declarado en configuración externa"

    $oldRead = @'
        var identityPasswordFingerprintKey = TryReadSecret(
            secretDirectory,
            IdentityPasswordFingerprintKeySecret,
            minimumLength: 64);

        var identitySecretCount = new[]
'@
    $newRead = @'
        var identityPasswordFingerprintKey = TryReadSecret(
            secretDirectory,
            IdentityPasswordFingerprintKeySecret,
            minimumLength: 64);
        var identityLoginAbuseKey = TryReadSecret(
            secretDirectory,
            IdentityLoginAbuseKeySecret,
            minimumLength: 64);

        var identitySecretCount = new[]
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldRead `
        -NewText $newRead `
        -Description "lectura externa de identity_login_abuse_key"

    $oldProtected = @'
        if (identityEmailLookupKey is not null
            && identityEmailEncryptionKey is not null
            && identityVerificationTokenKey is not null
            && identityPasswordFingerprintKey is not null)
        {
            protectedConfiguration["IdentityProtection:EmailLookupKey"] =
                identityEmailLookupKey;
            protectedConfiguration["IdentityProtection:EmailEncryptionKey"] =
                identityEmailEncryptionKey;
            protectedConfiguration["IdentityProtection:VerificationTokenKey"] =
                identityVerificationTokenKey;
            protectedConfiguration["IdentityProtection:PasswordFingerprintKey"] =
                identityPasswordFingerprintKey;
        }
'@
    $newProtected = @'
        if (identityEmailLookupKey is not null
            && identityEmailEncryptionKey is not null
            && identityVerificationTokenKey is not null
            && identityPasswordFingerprintKey is not null)
        {
            protectedConfiguration["IdentityProtection:EmailLookupKey"] =
                identityEmailLookupKey;
            protectedConfiguration["IdentityProtection:EmailEncryptionKey"] =
                identityEmailEncryptionKey;
            protectedConfiguration["IdentityProtection:VerificationTokenKey"] =
                identityVerificationTokenKey;
            protectedConfiguration["IdentityProtection:PasswordFingerprintKey"] =
                identityPasswordFingerprintKey;
        }

        if (identityLoginAbuseKey is not null)
        {
            protectedConfiguration["IdentityProtection:LoginAbuseKey"] =
                identityLoginAbuseKey;
        }
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldProtected `
        -NewText $newProtected `
        -Description "secreto de abuso expuesto solo al proceso que lo monta"
}

function Patch-Compose {
    $path = "compose.yml"

    $oldEnvironment = @'
      Dependencies__OpenTelemetryHealthUrl: http://otel-collector:13133/
'@
    $newEnvironment = @'
      Dependencies__OpenTelemetryHealthUrl: http://otel-collector:13133/
      Security__LoginAbuse__AccountFailureLimit: ${LOGIN_ABUSE_ACCOUNT_FAILURE_LIMIT:-5}
      Security__LoginAbuse__ClientFailureLimit: ${LOGIN_ABUSE_CLIENT_FAILURE_LIMIT:-20}
      Security__LoginAbuse__WindowSeconds: ${LOGIN_ABUSE_WINDOW_SECONDS:-900}
      Security__LoginAbuse__TrustClientAddressHeader: 'true'
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldEnvironment `
        -NewText $newEnvironment `
        -Description "politica configurable 5/cuenta, 20/IP y 15 minutos en Compose"

    $oldApiSecret = @'
      - identity_password_fingerprint_key
      - aspnetcore_local_https_certificate
'@
    $newApiSecret = @'
      - identity_password_fingerprint_key
      - identity_login_abuse_key
      - aspnetcore_local_https_certificate
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldApiSecret `
        -NewText $newApiSecret `
        -Description "identity_login_abuse_key montada solo en API"

    $oldDefinition = @'
  identity_password_fingerprint_key:
    file: ./secrets/local/identity_password_fingerprint_key
  aspnetcore_local_https_certificate:
'@
    $newDefinition = @'
  identity_password_fingerprint_key:
    file: ./secrets/local/identity_password_fingerprint_key
  identity_login_abuse_key:
    file: ./secrets/local/identity_login_abuse_key
  aspnetcore_local_https_certificate:
'@
    Replace-ExactText `
        -RelativePath $path `
        -OldText $oldDefinition `
        -NewText $newDefinition `
        -Description "definición Docker secret para control de abuso"
}

function Invoke-RunningRegressions {
    param([Parameter(Mandatory = $true)][string]$BashPath)

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

    $postgresPasswordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
    if (-not (Test-Path $postgresPasswordPath -PathType Leaf)) {
        throw "Falta secrets/local/postgres_password."
    }

    $names = @(
        "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
        "BL026_USE_RUNNING_API", "BL026_USE_DOCKER_PSQL", "BL026_API_URL",
        "BL027_USE_RUNNING_API", "BL027_USE_DOCKER_PSQL", "BL027_API_URL"
    )
    $previous = @{}
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = $dbPort
        $env:PGUSER = $dbUser
        $env:PGDATABASE = $dbName
        $env:PGPASSWORD = [System.IO.File]::ReadAllText($postgresPasswordPath).Trim()

        if (-not $SkipLoginRegression) {
            $env:BL026_USE_RUNNING_API = "true"
            $env:BL026_USE_DOCKER_PSQL = "true"
            $env:BL026_API_URL = "http://localhost:$webPort"
            & $BashPath "./scripts/ci/identity/verify-personal-login.sh"
            Assert-LastExitCode "Regresion BL-MVP-026"
        }

        if (-not $SkipLogoutRegression) {
            $env:BL027_USE_RUNNING_API = "true"
            $env:BL027_USE_DOCKER_PSQL = "true"
            $env:BL027_API_URL = "http://localhost:$webPort"
            & $BashPath "./scripts/ci/identity/verify-personal-logout.sh"
            Assert-LastExitCode "Regresion BL-MVP-027"
        }
    }
    finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
    }
}

function Invoke-AbuseSmoke {
    param([Parameter(Mandatory = $true)][string]$BashPath)

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"

    $postgresPasswordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
    if (-not (Test-Path $postgresPasswordPath -PathType Leaf)) {
        throw "Falta secrets/local/postgres_password."
    }

    $names = @(
        "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
        "BL029_USE_DOCKER_PSQL", "BL029_API_URL"
    )
    $previous = @{}
    foreach ($name in $names) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = $dbPort
        $env:PGUSER = $dbUser
        $env:PGDATABASE = $dbName
        $env:PGPASSWORD = [System.IO.File]::ReadAllText($postgresPasswordPath).Trim()
        $env:BL029_USE_DOCKER_PSQL = "true"
        $env:BL029_API_URL = "https://localhost:5445"

        & $BashPath "./scripts/ci/identity/verify-login-abuse.sh"
        Assert-LastExitCode "Smoke BL-MVP-029"
    }
    finally {
        foreach ($name in $names) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
    }
}

$correctiveArtifacts = @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029A.md",
    "README/BL-MVP-029A_README.md",
    "scripts/apply-bl-mvp-029a.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029B.md",
    "README/BL-MVP-029B_README.md",
    "scripts/apply-bl-mvp-029b.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029C.md",
    "README/BL-MVP-029C_README.md",
    "scripts/apply-bl-mvp-029c.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029D.md",
    "README/BL-MVP-029D_README.md",
    "scripts/apply-bl-mvp-029d.ps1"
)

$requiredFiles = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/Identity/PersonalAccountLoginEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountLoginService.cs",
    "apps/api/Program.cs",
    "compose.yml",
    "config/secrets/manifest.json",
    "docs/engineering/security/login-abuse-and-session-limits.md",
    "infrastructure/containers/web/nginx.local.conf",
    "README/BL-MVP-029_README.md",
    "scripts/apply-bl-mvp-029.ps1",
    "scripts/ci/identity/verify-login-abuse.sh",
    "scripts/ci/identity/verify-personal-login.sh",
    "scripts/ci/security/create-compose-secrets.sh",
    "scripts/local/ensure-local-secrets.ps1",
    "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs",
    "src/Modules/Security/Infrastructure/Authentication/LoginAbuseFingerprintService.cs",
    "src/Modules/Security/Infrastructure/Authentication/LoginAbusePersistence.cs",
    "src/Modules/Security/Infrastructure/Authentication/LoginAbusePolicy.cs",
    "tests/E2ETests/personal-login-abuse.spec.ts",
    "tests/UnitTests/Modules/Security/LoginAbuseFingerprintServiceTests.cs",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029.md"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-029: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git."
Assert-Command -Name "docker" -Correction "Inicie Docker Desktop."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-029 debe instalarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

Restore-GeneratedTypeScriptState
Assert-PackageInventory -AllowedPaths @($requiredFiles + $correctiveArtifacts)

Patch-ExternalConfiguration
Patch-Compose

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/identity/verify-login-abuse.sh"
Assert-LastExitCode "bash -n de verify-login-abuse.sh"
& $bashPath -n "./scripts/ci/identity/verify-personal-login.sh"
Assert-LastExitCode "bash -n de verify-personal-login.sh"

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

        Invoke-RunningRegressions -BashPath $bashPath

        if (-not $SkipAbuseSmoke) {
            Invoke-AbuseSmoke -BashPath $bashPath
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
    $SkipLoginRegression -or
    $SkipLogoutRegression -or
    $SkipAbuseSmoke) {
    Write-Warning "BL-MVP-029 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-029 instalado y validado localmente con limites de abuso, recuperacion y sesion revocable."
}

Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

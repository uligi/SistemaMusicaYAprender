[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipLoginRegression,
    [switch]$SkipLogoutSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "32a2cbdb5bf0102b3e527cb1998fb5a227a56294"
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

function Normalize-PorcelainPath {
    param([Parameter(Mandatory = $true)][string]$RawPath)
    $path = $RawPath
    if ($path.StartsWith('"') -and $path.EndsWith('"')) {
        $path = $path.Substring(1, $path.Length - 2)
    }
    return $path.Replace("\", "/")
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

        $relativePath = Normalize-PorcelainPath -RawPath $line.Substring(3)
        if ($relativePath.Contains(" -> ")) {
            $relativePath = ($relativePath -split " -> ", 2)[1]
        }

        $isOfficeTemp =
            $relativePath.StartsWith("sistema de musica/~$", [StringComparison]::Ordinal) -and
            $relativePath.EndsWith(".docx", [StringComparison]::OrdinalIgnoreCase)

        if (-not $allowed.Contains($relativePath) -and -not $isOfficeTemp) {
            [void]$unexpected.Add($relativePath)
        }
    }

    if ($unexpected.Count -gt 0) {
        throw "Hay cambios ajenos al paquete BL-MVP-027: $($unexpected -join ', ')."
    }
}

function Invoke-SessionSmokes {
    param(
        [Parameter(Mandatory = $true)][string]$BashPath,
        [Parameter(Mandatory = $true)][bool]$RunLogin,
        [Parameter(Mandatory = $true)][bool]$RunLogout
    )

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

    $postgresPasswordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
    if (-not (Test-Path $postgresPasswordPath -PathType Leaf)) {
        throw "Falta secrets/local/postgres_password."
    }

    $environmentNames = @(
        "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
        "BL026_USE_RUNNING_API", "BL026_USE_DOCKER_PSQL", "BL026_API_URL",
        "BL027_USE_RUNNING_API", "BL027_USE_DOCKER_PSQL", "BL027_API_URL"
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

        if ($RunLogin) {
            $env:BL026_USE_RUNNING_API = "true"
            $env:BL026_USE_DOCKER_PSQL = "true"
            $env:BL026_API_URL = "http://localhost:$webPort"
            & $BashPath "./scripts/ci/identity/verify-personal-login.sh"
            Assert-LastExitCode "Regresion BL-MVP-026"
        }

        if ($RunLogout) {
            $env:BL027_USE_RUNNING_API = "true"
            $env:BL027_USE_DOCKER_PSQL = "true"
            $env:BL027_API_URL = "http://localhost:$webPort"
            & $BashPath "./scripts/ci/identity/verify-personal-logout.sh"
            Assert-LastExitCode "Smoke BL-MVP-027"
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
    "apps/api/Endpoints/Identity/PersonalAccountLogoutEndpoint.cs",
    "apps/api/Program.cs",
    "apps/web/src/app/access/AccessContext.tsx",
    "apps/web/src/routes/public/PersonalAccountLoginPage.tsx",
    "apps/web/src/routes/public/public-area.css",
    "tests/E2ETests/personal-logout.spec.ts",
    "scripts/ci/identity/verify-personal-logout.sh",
    "scripts/apply-bl-mvp-027.ps1",
    "README/BL-MVP-027_README.md",
    "docs/engineering/security/session-logout.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027.md"
)

$correctiveArtifacts = @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027A.md",
    "README/BL-MVP-027A_README.md",
    "scripts/apply-bl-mvp-027a.ps1",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-027B.md",
    "README/BL-MVP-027B_README.md",
    "scripts/apply-bl-mvp-027b.ps1"
)

$historicalReadmeMoves = @(
    "BL-MVP-023_README.md",
    "BL-MVP-024_README.md",
    "BL-MVP-025_README.md",
    "BL-MVP-028_README.md",
    "BL-MVP-035_README.md",
    "README/README.md",
    "README.md",
    "README/BL-MVP-023_README.md",
    "README/BL-MVP-024_README.md",
    "README/BL-MVP-025_README.md",
    "README/BL-MVP-028_README.md",
    "README/BL-MVP-035_README.md"
)

$allowedPaths = @($requiredFiles + $correctiveArtifacts + $historicalReadmeMoves)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-027: $relativePath"
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
    throw "BL-MVP-027 debe instalarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

Restore-GeneratedTypeScriptState
Assert-PackageInventory -AllowedPaths $allowedPaths

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/identity/verify-personal-logout.sh"
Assert-LastExitCode "bash -n de verify-personal-logout.sh"

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

        if (-not $SkipLoginRegression -or -not $SkipLogoutSmoke) {
            Invoke-SessionSmokes `
                -BashPath $bashPath `
                -RunLogin (-not $SkipLoginRegression) `
                -RunLogout (-not $SkipLogoutSmoke)
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
    $SkipLogoutSmoke) {
    Write-Warning "BL-MVP-027 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-027 instalado y validado localmente con cierre de sesion, CSRF y revocacion aislada."
}

Write-Host "Acceso: http://localhost:5173/acceso"
Write-Host "No se ejecuto staging, commit, push ni una migracion de produccion."

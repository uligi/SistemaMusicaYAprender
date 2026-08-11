[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipConfigurationSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "f65012126b438960d90e02ccb626216cf08a3f53"
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

function Read-Normalized {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta $RelativePath."
    }

    $content = [System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)
    return $content.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $path = Join-Path $RepoRoot $RelativePath
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText(
        $path,
        $normalized,
        [System.Text.UTF8Encoding]::new($false))
}

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $content = Read-Normalized -RelativePath $RelativePath
    $old = $OldText.Replace("`r`n", "`n").Replace("`r", "`n")
    $new = $NewText.Replace("`r`n", "`n").Replace("`r", "`n")

    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $old,
        $first + $old.Length,
        [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "El bloque para $Description aparece mas de una vez en $RelativePath."
    }

    $updated = $content.Remove($first, $old.Length).Insert($first, $new)
    Write-Utf8NoBomLf -RelativePath $RelativePath -Content $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"
    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta de indice TypeScript"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento TypeScript"
    if ($trackedPaths.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de salida incremental TypeScript"
    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion TypeScript incremental"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
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

function Get-ChangedPaths {
    $paths = @(
        git status --porcelain=v1 --untracked-files=all |
            ForEach-Object {
                if ($_.Length -ge 4) {
                    $_.Substring(3).Trim('"').Replace("\", "/")
                }
            } |
            Where-Object { $_ }
    )
    Assert-LastExitCode "Inventario Git"
    return $paths
}

Write-Host "BL-MVP-036: administracion versionada de catalogos y parametros..."

Assert-Command -Name "git.exe" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker.exe" -Correction "Instale o inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet.exe" -Correction "Instale .NET SDK 9.0.314."
Assert-Command -Name "node.exe" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-036 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

Restore-GeneratedTypeScriptState

$allowedPaths = @(
    ".github/workflows/ci.yml"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-036.md"
    "README/BL-MVP-036_README.md"
    "apps/api/Endpoints/Administration/ConfigurationAdministrationEndpoints.cs"
    "apps/api/Program.cs"
    "apps/api/Security/ConfigurationAdministrationTransactionExecutor.cs"
    "apps/web/src/routes/administration/AdministrationArea.tsx"
    "apps/web/src/routes/administration/ConfigurationAdministrationPage.tsx"
    "apps/web/src/routes/administration/configuration-administration.css"
    "docs/engineering/configuration/versioned-configuration-administration.md"
    "scripts/apply-bl-mvp-036.ps1"
    "scripts/ci/configuration/verify-versioned-configuration-administration.sh"
    "src/Modules/Configuration/Infrastructure/Administration/IConfigurationAdministrationTransactionExecutor.cs"
    "src/Modules/Configuration/Infrastructure/Administration/ConfigurationAdministrationService.cs"
    "tests/E2ETests/configuration-administration.spec.ts"
)
$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $allowedPaths) {
    [void]$allowed.Add($path)
}

$transientCorrectivePaths = @(
    "scripts/apply-bl-mvp-036a.ps1"
    "scripts/apply-bl-mvp-036b.ps1"
    "scripts/apply-bl-mvp-036c.ps1"
    "scripts/apply-bl-mvp-036d.ps1"
    "scripts/apply-bl-mvp-036e.ps1"
)
$transient = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $transientCorrectivePaths) {
    [void]$transient.Add($path)
}

$changedBeforePatch = Get-ChangedPaths
$unexpectedBeforePatch = @(
    $changedBeforePatch |
        Where-Object {
            -not $allowed.Contains($_) -and
            -not $transient.Contains($_)
        }
)
if ($unexpectedBeforePatch.Count -gt 0) {
    throw "Hay cambios fuera del paquete BL-MVP-036: $($unexpectedBeforePatch -join ', ')"
}

$requiredNew = @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-036.md"
    "README/BL-MVP-036_README.md"
    "apps/api/Endpoints/Administration/ConfigurationAdministrationEndpoints.cs"
    "apps/api/Security/ConfigurationAdministrationTransactionExecutor.cs"
    "apps/web/src/routes/administration/ConfigurationAdministrationPage.tsx"
    "apps/web/src/routes/administration/configuration-administration.css"
    "docs/engineering/configuration/versioned-configuration-administration.md"
    "scripts/apply-bl-mvp-036.ps1"
    "scripts/ci/configuration/verify-versioned-configuration-administration.sh"
    "src/Modules/Configuration/Infrastructure/Administration/IConfigurationAdministrationTransactionExecutor.cs"
    "src/Modules/Configuration/Infrastructure/Administration/ConfigurationAdministrationService.cs"
    "tests/E2ETests/configuration-administration.spec.ts"
)
foreach ($path in $requiredNew) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

# API: namespace de endpoints administrativos.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using Microsoft.Extensions.Options;
using MusicaAprender.Api.Endpoints.Identity;
'@ `
    -NewText @'
using Microsoft.Extensions.Options;
using MusicaAprender.Api.Endpoints.Administration;
using MusicaAprender.Api.Endpoints.Identity;
'@ `
    -AlreadyMarker "using MusicaAprender.Api.Endpoints.Administration;" `
    -Description "namespace endpoint de configuracion"

# API: contrato del modulo Configuration.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
'@ `
    -NewText @'
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Configuration.Infrastructure.Administration;
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Configuration.Infrastructure.Administration;" `
    -Description "namespace administracion Configuration"

# API: adaptador backoffice sin referencia Configuration -> Security.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<IPrivilegedSecurityTransactionExecutor>(
    static services =>
        services.GetRequiredService<BackofficeSecurityTransactionExecutor>());
builder.Services.AddSingleton<RoleAssignmentAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<IPrivilegedSecurityTransactionExecutor>(
    static services =>
        services.GetRequiredService<BackofficeSecurityTransactionExecutor>());
builder.Services.AddSingleton<IConfigurationAdministrationTransactionExecutor>(
    static services =>
        new ConfigurationAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ConfigurationAdministrationService>();
builder.Services.AddSingleton<RoleAssignmentAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<ConfigurationAdministrationService>();" `
    -Description "servicio de administracion versionada"

# API: rutas BL036.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapRoleAssignments();
app.MapPrivilegedMfa();

app.Run();
'@ `
    -NewText @'
app.MapRoleAssignments();
app.MapPrivilegedMfa();
app.MapConfigurationAdministration();

app.Run();
'@ `
    -AlreadyMarker "app.MapConfigurationAdministration();" `
    -Description "endpoints de administracion Configuration"

# UI-MVP-030 real.
# Correctivo A: no depende de que todo AdministrationArea.tsx sea byte-a-byte
# idéntico; inserta únicamente el import y la rama que pertenecen a BL036.
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/AdministrationArea.tsx" `
    -OldText @'
import { RoleManagementPage } from './RoleManagementPage';
'@ `
    -NewText @'
import { ConfigurationAdministrationPage } from './ConfigurationAdministrationPage';
import { RoleManagementPage } from './RoleManagementPage';
'@ `
    -AlreadyMarker "import { ConfigurationAdministrationPage } from './ConfigurationAdministrationPage';" `
    -Description "import UI-MVP-030 administracion de configuracion"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/AdministrationArea.tsx" `
    -OldText @'
  return (
    <RoutePlaceholder
'@ `
    -NewText @'
  if (match.route.id === 'UI-MVP-030') {
    return <ConfigurationAdministrationPage />;
  }

  return (
    <RoutePlaceholder
'@ `
    -AlreadyMarker "return <ConfigurationAdministrationPage />;" `
    -Description "ruta UI-MVP-030 administracion de configuracion"

# CI: añade puerta BL036 inmediatamente después de BL034.
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify basic profile and safe personal preferences
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL034_USE_DOCKER_PSQL: 'false'
          BL034_API_URL: https://localhost:5450
        run: bash scripts/ci/identity/verify-personal-preferences.sh

      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify basic profile and safe personal preferences
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL034_USE_DOCKER_PSQL: 'false'
          BL034_API_URL: https://localhost:5450
        run: bash scripts/ci/identity/verify-personal-preferences.sh

      - name: Verify versioned catalog and parameter administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL036_USE_DOCKER_PSQL: 'false'
          BL036_API_URL: https://localhost:5451
        run: bash scripts/ci/configuration/verify-versioned-configuration-administration.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "Verify versioned catalog and parameter administration" `
    -Description "puerta CI BL-MVP-036"

$configService = Read-Normalized -RelativePath `
    "src/Modules/Configuration/Infrastructure/Administration/ConfigurationAdministrationService.cs"
if ($configService.Contains("security.")) {
    throw "M19 no debe consultar ni modificar directamente tablas security.*; usa el adaptador de M18."
}
if ($configService -match "(?im)\bDELETE\s+FROM\s+configuration\.") {
    throw "BL-MVP-036 no permite borrado fisico de versiones configuration.*."
}
Write-Host "OK: propiedad modular y ausencia de DELETE fisico verificadas."

& "$PSScriptRoot/check-toolchain.ps1"

docker version *> $null
Assert-LastExitCode "Docker Engine"
docker compose version *> $null
Assert-LastExitCode "Docker Compose"

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

Write-Host "Validando restauracion .NET exactamente como CI..."
dotnet restore MusicaAprender.sln --locked-mode
Assert-LastExitCode "dotnet restore locked-mode"

Write-Host "Normalizando formato .NET de BL-MVP-036..."
dotnet format MusicaAprender.sln `
    --no-restore `
    --include `
        "apps/api/Endpoints/Administration/ConfigurationAdministrationEndpoints.cs" `
        "apps/api/Program.cs" `
        "apps/api/Security/ConfigurationAdministrationTransactionExecutor.cs" `
        "src/Modules/Configuration/Infrastructure/Administration/IConfigurationAdministrationTransactionExecutor.cs" `
        "src/Modules/Configuration/Infrastructure/Administration/ConfigurationAdministrationService.cs"
Assert-LastExitCode "dotnet format BL-MVP-036"

Write-Host "Restaurando frontend desde package-lock..."
npm.cmd ci
Assert-LastExitCode "npm ci"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
if (-not (Test-Path $prettier -PathType Leaf)) {
    throw "No se encontro Prettier tras npm ci."
}

$formatTargets = @(
    "apps/web/src/routes/administration/AdministrationArea.tsx",
    "apps/web/src/routes/administration/ConfigurationAdministrationPage.tsx",
    "apps/web/src/routes/administration/configuration-administration.css",
    "tests/E2ETests/configuration-administration.spec.ts",
    "docs/engineering/configuration/versioned-configuration-administration.md",
    "README/BL-MVP-036_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-036.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-036"
& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-036"

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/configuration/verify-versioned-configuration-administration.sh"
Assert-LastExitCode "Sintaxis bash BL-MVP-036"

if (-not $SkipBrowserInstall) {
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
        $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
        $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
        $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
        $webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

        $passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
        if (-not (Test-Path $passwordPath -PathType Leaf)) {
            throw "Falta secrets/local/postgres_password."
        }

        $names = @(
            "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
            "BL036_USE_RUNNING_API", "BL036_USE_DOCKER_PSQL", "BL036_API_URL"
        )
        $previous = @{}
        foreach ($name in $names) {
            $previous[$name] =
                [Environment]::GetEnvironmentVariable($name, "Process")
        }

        try {
            $env:PGHOST = "127.0.0.1"
            $env:PGPORT = $dbPort
            $env:PGUSER = $dbUser
            $env:PGDATABASE = $dbName
            $env:PGPASSWORD =
                [System.IO.File]::ReadAllText($passwordPath).Trim()

            $env:BL036_USE_RUNNING_API = "true"
            $env:BL036_USE_DOCKER_PSQL = "true"
            $env:BL036_API_URL = "http://localhost:$webPort"

            & $bashPath "./scripts/ci/configuration/verify-versioned-configuration-administration.sh"
            Assert-LastExitCode "Smoke BL-MVP-036"
        }
        finally {
            foreach ($name in $names) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    $previous[$name],
                    "Process")
            }
        }

        & "$PSScriptRoot/local/verify-running.ps1"
    }
}

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check"

$finalChanged = Get-ChangedPaths
$unexpectedFinal = @(
    $finalChanged |
        Where-Object {
            -not $allowed.Contains($_) -and
            -not $transient.Contains($_)
        }
)
if ($unexpectedFinal.Count -gt 0) {
    throw "La puerta genero cambios fuera de BL-MVP-036: $($unexpectedFinal -join ', ')"
}

foreach ($required in $allowedPaths) {
    if ($finalChanged -notcontains $required) {
        throw "BL-MVP-036 no produjo el cambio esperado: $required"
    }
}

Write-Host ""
git status --short --untracked-files=all
Assert-LastExitCode "git status"
Write-Host ""
git diff --stat
Assert-LastExitCode "git diff --stat"
Write-Host ""
git diff --name-only
Assert-LastExitCode "git diff --name-only"

Write-Host ""
if ($SkipQualityGate -or $SkipStart -or $SkipConfigurationSmoke) {
    Write-Warning "BL-MVP-036 fue ejecutado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-036 instalado y validado localmente con permisos, step-up, simulacion, vigencia, impacto, motivo, auditoria e historial preservado."
}
Write-Host "UI: http://localhost:5173/administracion/configuracion"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

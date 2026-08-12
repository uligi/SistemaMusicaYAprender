[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipArtistSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "95140c4fbc41a0bd06fca638b441db5932501c92"
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

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta de indice TypeScript"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged; no se restaurara automaticamente."
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

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No existe $RelativePath."
    }

    $content = [System.IO.File]::ReadAllText($path)

    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $OldText,
        $first + $OldText.Length,
        [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "El bloque para $Description aparece mas de una vez en $RelativePath."
    }

    $updated =
        $content.Substring(0, $first) +
        $NewText +
        $content.Substring($first + $OldText.Length)

    [System.IO.File]::WriteAllText(
        $path,
        $updated,
        [System.Text.UTF8Encoding]::new($false))

    Write-Host "OK: $Description aplicado."
}

Write-Host "BL-MVP-037: identidad estable de artista, alias y nombres localizados..."

Assert-Command -Name "git.exe" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker.exe" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet.exe" -Correction "Instale .NET SDK 9.0.314."
Assert-Command -Name "node.exe" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-037 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
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
    "apps/api/Program.cs"
    "apps/web/src/routes/editorial/EditorialArea.tsx"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-037.md"
    "README/BL-MVP-037_README.md"
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs"
    "apps/api/Endpoints/Editorial/ArtistAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx"
    "apps/web/src/routes/editorial/artist-administration.css"
    "docs/engineering/catalog/artist-identity-administration.md"
    "scripts/apply-bl-mvp-037.ps1"
    "scripts/ci/catalog/verify-artist-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/ArtistAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/IArtistAdministrationTransactionExecutor.cs"
    "tests/E2ETests/artist-administration.spec.ts"
)
$newPaths = @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-037.md"
    "README/BL-MVP-037_README.md"
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs"
    "apps/api/Endpoints/Editorial/ArtistAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx"
    "apps/web/src/routes/editorial/artist-administration.css"
    "docs/engineering/catalog/artist-identity-administration.md"
    "scripts/apply-bl-mvp-037.ps1"
    "scripts/ci/catalog/verify-artist-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/ArtistAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/IArtistAdministrationTransactionExecutor.cs"
    "tests/E2ETests/artist-administration.spec.ts"
)

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $allowedPaths) {
    [void]$allowed.Add($path)
}

$changedBeforePatch = Get-ChangedPaths
$unexpectedBeforePatch = @(
    $changedBeforePatch |
        Where-Object { -not $allowed.Contains($_) }
)
if ($unexpectedBeforePatch.Count -gt 0) {
    throw "Hay cambios fuera del paquete BL-MVP-037: $($unexpectedBeforePatch -join ', ')"
}

foreach ($path in $newPaths) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

# Program.cs: imports, DI y endpoints.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "using MusicaAprender.Api.Endpoints.Administration;`n" `
    -NewText "using MusicaAprender.Api.Endpoints.Administration;`nusing MusicaAprender.Api.Endpoints.Editorial;`n" `
    -AlreadyMarker "using MusicaAprender.Api.Endpoints.Editorial;" `
    -Description "namespace endpoint editorial"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "using MusicaAprender.Api.Security;`n" `
    -NewText "using MusicaAprender.Api.Catalog;`nusing MusicaAprender.Api.Security;`n" `
    -AlreadyMarker "using MusicaAprender.Api.Catalog;" `
    -Description "namespace adapter Catalog"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "using MusicaAprender.Modules.Configuration.Infrastructure.Administration;`n" `
    -NewText "using MusicaAprender.Modules.Catalog.Infrastructure.Administration;`nusing MusicaAprender.Modules.Configuration.Infrastructure.Administration;`n" `
    -AlreadyMarker "using MusicaAprender.Modules.Catalog.Infrastructure.Administration;" `
    -Description "namespace administracion Catalog"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<IArtistAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<ArtistAdministrationService>();" `
    -Description "servicio de artistas"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapConfigurationAdministration();
'@ `
    -NewText @'
app.MapConfigurationAdministration();
app.MapArtistAdministration();
'@ `
    -AlreadyMarker "app.MapArtistAdministration();" `
    -Description "endpoints de artistas"

# UI-MVP-018 real.
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
'@ `
    -NewText @'
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
'@ `
    -AlreadyMarker "import { ArtistAdministrationPage } from './ArtistAdministrationPage';" `
    -Description "import UI-MVP-018"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
export default function EditorialArea({ match }: EditorialAreaProps) {
  return (
'@ `
    -NewText @'
export default function EditorialArea({ match }: EditorialAreaProps) {
  if (match.route.id === 'UI-MVP-018') {
    return <ArtistAdministrationPage />;
  }

  return (
'@ `
    -AlreadyMarker "return <ArtistAdministrationPage />;" `
    -Description "ruta UI-MVP-018"

# CI BL037 after BL036.
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify stable artist identities, aliases and duplicate warning
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL037_USE_DOCKER_PSQL: 'false'
          BL037_API_URL: https://localhost:5452
        run: bash scripts/ci/catalog/verify-artist-administration.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "run: bash scripts/ci/catalog/verify-artist-administration.sh" `
    -Description "puerta CI BL-MVP-037"

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

Write-Host "Normalizando formato .NET de BL-MVP-037..."
dotnet format MusicaAprender.sln `
    --no-restore `
    --include `
        "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
        "apps/api/Endpoints/Editorial/ArtistAdministrationEndpoints.cs" `
        "apps/api/Program.cs" `
        "src/Modules/Catalog/Infrastructure/Administration/ArtistAdministrationService.cs" `
        "src/Modules/Catalog/Infrastructure/Administration/IArtistAdministrationTransactionExecutor.cs"
Assert-LastExitCode "dotnet format BL-MVP-037"

Write-Host "Restaurando frontend desde package-lock..."
npm.cmd ci
Assert-LastExitCode "npm ci"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
if (-not (Test-Path $prettier -PathType Leaf)) {
    throw "No se encontro Prettier tras npm ci."
}

$formatTargets = @(
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx",
    "apps/web/src/routes/editorial/artist-administration.css",
    "tests/E2ETests/artist-administration.spec.ts",
    "docs/engineering/catalog/artist-identity-administration.md",
    "README/BL-MVP-037_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-037.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-037"
& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-037"

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/catalog/verify-artist-administration.sh"
Assert-LastExitCode "Sintaxis bash BL-MVP-037"

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

    if (-not $SkipArtistSmoke) {
        $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
        $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
        $dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
        $webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

        $passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
        if (-not (Test-Path $passwordPath -PathType Leaf)) {
            throw "Falta secrets/local/postgres_password."
        }

        $environmentNames = @(
            "PGHOST",
            "PGPORT",
            "PGUSER",
            "PGDATABASE",
            "PGPASSWORD",
            "BL037_USE_RUNNING_API",
            "BL037_USE_DOCKER_PSQL",
            "BL037_API_URL"
        )
        $previousEnvironment = @{}
        foreach ($name in $environmentNames) {
            $previousEnvironment[$name] =
                [Environment]::GetEnvironmentVariable(
                    $name,
                    "Process")
        }

        try {
            $env:PGHOST = "127.0.0.1"
            $env:PGPORT = $dbPort
            $env:PGUSER = $dbUser
            $env:PGDATABASE = $dbName
            $env:PGPASSWORD =
                [System.IO.File]::ReadAllText(
                    $passwordPath).Trim()
            $env:BL037_USE_RUNNING_API = "true"
            $env:BL037_USE_DOCKER_PSQL = "true"
            $env:BL037_API_URL = "http://localhost:$webPort"

            & $bashPath "./scripts/ci/catalog/verify-artist-administration.sh"
            Assert-LastExitCode "Smoke BL-MVP-037"
        }
        finally {
            foreach ($name in $environmentNames) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    $previousEnvironment[$name],
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
        Where-Object { -not $allowed.Contains($_) }
)
if ($unexpectedFinal.Count -gt 0) {
    throw "La puerta genero cambios fuera de BL-MVP-037: $($unexpectedFinal -join ', ')"
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
if ($SkipQualityGate -or $SkipStart -or $SkipArtistSmoke) {
    Write-Warning "BL-MVP-037 fue ejecutado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-037 instalado y validado localmente con identidad estable, alias/lecturas, advertencia de duplicados, idempotencia, autorizacion y auditoria."
}
Write-Host "UI: http://localhost:5173/editorial/canciones/nueva"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

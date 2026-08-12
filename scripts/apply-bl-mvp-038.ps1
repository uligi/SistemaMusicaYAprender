[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipSongDraftSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "f4151ec6b433c2a55a3bfbe1fafc36494eb2458a"
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

    $first = $content.IndexOf(
        $old,
        [System.StringComparison]::Ordinal)

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

    $updated = $content.Remove(
        $first,
        $old.Length).Insert(
            $first,
            $new)

    Write-Utf8NoBomLf `
        -RelativePath $RelativePath `
        -Content $updated

    Write-Host "OK: $Description aplicado."
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

Write-Host "BL-MVP-038: obra, grabacion y fuente de YouTube separadas..."

Assert-Command -Name "git.exe" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker.exe" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet.exe" -Correction "Instale .NET SDK 9.0.314."
Assert-Command -Name "node.exe" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-038 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
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
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs"
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx"
    "apps/web/src/routes/editorial/EditorialArea.tsx"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-038.md"
    "README/BL-MVP-038_README.md"
    "apps/api/Endpoints/Editorial/SongDraftAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/SongDraftComposer.tsx"
    "apps/web/src/routes/editorial/SongDraftDetailPage.tsx"
    "apps/web/src/routes/editorial/song-draft-administration.css"
    "docs/engineering/catalog/work-recording-youtube-source-administration.md"
    "scripts/apply-bl-mvp-038.ps1"
    "scripts/ci/catalog/verify-song-draft-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/SongDraftAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/ISongDraftAdministrationTransactionExecutor.cs"
    "tests/E2ETests/artist-administration.spec.ts"
    "tests/E2ETests/song-draft-administration.spec.ts"
)

$newPaths = @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-038.md"
    "README/BL-MVP-038_README.md"
    "apps/api/Endpoints/Editorial/SongDraftAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/SongDraftComposer.tsx"
    "apps/web/src/routes/editorial/SongDraftDetailPage.tsx"
    "apps/web/src/routes/editorial/song-draft-administration.css"
    "docs/engineering/catalog/work-recording-youtube-source-administration.md"
    "scripts/apply-bl-mvp-038.ps1"
    "scripts/ci/catalog/verify-song-draft-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/SongDraftAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/ISongDraftAdministrationTransactionExecutor.cs"
    "tests/E2ETests/song-draft-administration.spec.ts"
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
    throw "Hay cambios fuera del paquete BL-MVP-038: $($unexpectedBeforePatch -join ', ')"
}

foreach ($path in $newPaths) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

# Adapter API -> Catalog: reutiliza la misma transaccion backoffice sin acoplar Catalog a Security.
Replace-ExactOnce `
    -RelativePath "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
    -OldText @'
public sealed class CatalogAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : IArtistAdministrationTransactionExecutor
'@ `
    -NewText @'
public sealed class CatalogAdministrationTransactionExecutor(
    BackofficeSecurityTransactionExecutor inner)
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor
'@ `
    -AlreadyMarker "ISongDraftAdministrationTransactionExecutor" `
    -Description "contrato transaccional de borradores de cancion"

# Program.cs: servicio BL038.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<ISongDraftAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<SongDraftAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<SongDraftAdministrationService>();" `
    -Description "servicio de obra grabacion y fuente"

# Program.cs: rutas BL038 usando un ancla mínima y estable.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapArtistAdministration();
'@ `
    -NewText @'
app.MapArtistAdministration();
app.MapSongDraftAdministration();
'@ `
    -AlreadyMarker "app.MapSongDraftAdministration();" `
    -Description "endpoints de borradores de cancion"

# UI-MVP-019: expediente real.
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
'@ `
    -NewText @'
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import { SongDraftDetailPage } from './SongDraftDetailPage';
'@ `
    -AlreadyMarker "import { SongDraftDetailPage } from './SongDraftDetailPage';" `
    -Description "import UI-MVP-019"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
  if (match.route.id === 'UI-MVP-018') {
    return <ArtistAdministrationPage />;
  }

  return (
'@ `
    -NewText @'
  if (match.route.id === 'UI-MVP-018') {
    return <ArtistAdministrationPage />;
  }

  if (match.route.id === 'UI-MVP-019') {
    return <SongDraftDetailPage recordingId={match.params.id ?? ''} />;
  }

  return (
'@ `
    -AlreadyMarker "return <SongDraftDetailPage recordingId={match.params.id ?? ''} />;" `
    -Description "ruta UI-MVP-019"

# UI-MVP-018: selección de artista + continuación a obra/grabación/fuente.
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    -OldText @'
import { createHttpClient } from '../../data/http';
import './artist-administration.css';
'@ `
    -NewText @'
import { createHttpClient } from '../../data/http';
import { SongDraftComposer, type SelectedArtist } from './SongDraftComposer';
import './artist-administration.css';
import './song-draft-administration.css';
'@ `
    -AlreadyMarker "import { SongDraftComposer, type SelectedArtist } from './SongDraftComposer';" `
    -Description "composer BL038 en UI-MVP-018"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    -OldText @'
  const [searchResults, setSearchResults] = useState<ArtistSearchResult[]>([]);
  const [message, setMessage] = useState('');
'@ `
    -NewText @'
  const [searchResults, setSearchResults] = useState<ArtistSearchResult[]>([]);
  const [selectedArtist, setSelectedArtist] = useState<SelectedArtist | null>(null);
  const [message, setMessage] = useState('');
'@ `
    -AlreadyMarker "const [selectedArtist, setSelectedArtist]" `
    -Description "estado de artista seleccionado"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    -OldText @'
    setCreated(result.data);
    setMessage(
'@ `
    -NewText @'
    setCreated(result.data);
    setSelectedArtist({
      artistId: result.data.artistId,
      canonicalName: result.data.canonicalName,
    });
    setMessage(
'@ `
    -AlreadyMarker "canonicalName: result.data.canonicalName" `
    -Description "seleccion automatica del artista creado"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    -OldText @'
                  <code>{artist.artistId}</code>
                </li>
'@ `
    -NewText @'
                  <code>{artist.artistId}</code>
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() =>
                      setSelectedArtist({
                        artistId: artist.artistId,
                        canonicalName: artist.canonicalName,
                      })
                    }
                  >
                    Usar {artist.canonicalName}
                  </Button>
                </li>
'@ `
    -AlreadyMarker "Usar {artist.canonicalName}" `
    -Description "seleccion de artista existente"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    -OldText @'
      </div>
    </section>
  );
}
'@ `
    -NewText @'
      </div>

      {selectedArtist ? <SongDraftComposer artist={selectedArtist} /> : null}
    </section>
  );
}
'@ `
    -AlreadyMarker "<SongDraftComposer artist={selectedArtist} />" `
    -Description "continuacion BL038 de nueva cancion"

# CI: BL038 inmediatamente después de BL037.
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify work, recording and exact YouTube source administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL038_USE_DOCKER_PSQL: 'false'
          BL038_API_URL: https://localhost:5453
        run: bash scripts/ci/catalog/verify-song-draft-administration.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "run: bash scripts/ci/catalog/verify-song-draft-administration.sh" `
    -Description "puerta CI BL-MVP-038"

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

Write-Host "Normalizando formato .NET de BL-MVP-038..."
dotnet format MusicaAprender.sln `
    --no-restore `
    --include `
        "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
        "apps/api/Endpoints/Editorial/SongDraftAdministrationEndpoints.cs" `
        "apps/api/Program.cs" `
        "src/Modules/Catalog/Infrastructure/Administration/SongDraftAdministrationService.cs" `
        "src/Modules/Catalog/Infrastructure/Administration/ISongDraftAdministrationTransactionExecutor.cs"
Assert-LastExitCode "dotnet format BL-MVP-038"

Write-Host "Restaurando frontend desde package-lock..."
npm.cmd ci
Assert-LastExitCode "npm ci"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
if (-not (Test-Path $prettier -PathType Leaf)) {
    throw "No se encontro Prettier tras npm ci."
}

$formatTargets = @(
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SongDraftComposer.tsx",
    "apps/web/src/routes/editorial/SongDraftDetailPage.tsx",
    "apps/web/src/routes/editorial/song-draft-administration.css",
    "tests/E2ETests/artist-administration.spec.ts",
    "tests/E2ETests/song-draft-administration.spec.ts",
    "docs/engineering/catalog/work-recording-youtube-source-administration.md",
    "README/BL-MVP-038_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-038.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-038"
& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-038"

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/catalog/verify-song-draft-administration.sh"
Assert-LastExitCode "Sintaxis bash BL-MVP-038"

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

    if (-not $SkipSongDraftSmoke) {
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
            "BL038_USE_RUNNING_API",
            "BL038_USE_DOCKER_PSQL",
            "BL038_API_URL"
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
            $env:BL038_USE_RUNNING_API = "true"
            $env:BL038_USE_DOCKER_PSQL = "true"
            $env:BL038_API_URL = "http://localhost:$webPort"

            & $bashPath "./scripts/ci/catalog/verify-song-draft-administration.sh"
            Assert-LastExitCode "Smoke BL-MVP-038"
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
    throw "La puerta genero cambios fuera de BL-MVP-038: $($unexpectedFinal -join ', ')"
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
if ($SkipQualityGate -or $SkipStart -or $SkipSongDraftSmoke) {
    Write-Warning "BL-MVP-038 fue ejecutado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-038 instalado y validado localmente con obra, grabacion y fuente YouTube separadas, validacion local, duplicados, idempotencia, autorizacion y auditoria."
}

Write-Host "UI alta: http://localhost:5173/editorial/canciones/nueva"
Write-Host "UI expediente: http://localhost:5173/editorial/canciones/{recordingId}"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

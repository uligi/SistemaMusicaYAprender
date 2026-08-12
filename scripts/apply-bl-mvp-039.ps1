[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "e0fd70dbfb5d120c782a3645ce81ab2795917b2b"
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

function Replace-RegexOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $content = Read-Normalized -RelativePath $RelativePath
    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $matches = $regex.Matches($content)

    if ($matches.Count -ne 1) {
        throw "Se esperaba una coincidencia para $Description en $RelativePath y se encontraron $($matches.Count)."
    }

    $updated = $regex.Replace(
        $content,
        $Replacement,
        1)

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
        Write-Host "Restaurado $relativePath."
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

Write-Host "BL-MVP-039: creditos, participantes, procedencia y menu lateral backoffice..."

Assert-Command `
    -Name "git.exe" `
    -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command `
    -Name "docker.exe" `
    -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command `
    -Name "dotnet.exe" `
    -Correction "Instale el SDK .NET fijado por el repositorio."
Assert-Command `
    -Name "node.exe" `
    -Correction "Instale Node.js fijado por el repositorio."
Assert-Command `
    -Name "npm.cmd" `
    -Correction "Instale npm fijado por el repositorio."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"

if ($currentBranch -ne "main") {
    throw "BL-MVP-039 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
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
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs"
    "apps/api/Program.cs"
    "apps/web/src/app/shell/BackofficeShell.tsx"
    "apps/web/src/routes/editorial/EditorialArea.tsx"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-039.md"
    "README/BL-MVP-039_README.md"
    "apps/api/Endpoints/Editorial/CreditProvenanceAdministrationEndpoints.cs"
    "apps/api/Security/AnyEffectivePermissionEndpointFilter.cs"
    "apps/web/src/app/shell/BackofficeSidebar.tsx"
    "apps/web/src/app/shell/backoffice-sidebar.css"
    "apps/web/src/routes/editorial/CreditProvenancePage.tsx"
    "apps/web/src/routes/editorial/credit-provenance.css"
    "docs/engineering/catalog/credit-participant-provenance-administration.md"
    "scripts/apply-bl-mvp-039.ps1"
    "scripts/ci/catalog/verify-credit-provenance-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/CreditProvenanceAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/ICreditProvenanceAdministrationTransactionExecutor.cs"
    "tests/E2ETests/backoffice-sidebar.spec.ts"
    "tests/E2ETests/credit-provenance-administration.spec.ts"
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
    throw "Hay cambios fuera del paquete BL-MVP-039: $($unexpectedBeforePatch -join ', ')"
}

$newPaths = @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-039.md"
    "README/BL-MVP-039_README.md"
    "apps/api/Endpoints/Editorial/CreditProvenanceAdministrationEndpoints.cs"
    "apps/api/Security/AnyEffectivePermissionEndpointFilter.cs"
    "apps/web/src/app/shell/BackofficeSidebar.tsx"
    "apps/web/src/app/shell/backoffice-sidebar.css"
    "apps/web/src/routes/editorial/CreditProvenancePage.tsx"
    "apps/web/src/routes/editorial/credit-provenance.css"
    "docs/engineering/catalog/credit-participant-provenance-administration.md"
    "scripts/apply-bl-mvp-039.ps1"
    "scripts/ci/catalog/verify-credit-provenance-administration.sh"
    "src/Modules/Catalog/Infrastructure/Administration/CreditProvenanceAdministrationService.cs"
    "src/Modules/Catalog/Infrastructure/Administration/ICreditProvenanceAdministrationTransactionExecutor.cs"
    "tests/E2ETests/backoffice-sidebar.spec.ts"
    "tests/E2ETests/credit-provenance-administration.spec.ts"
)

foreach ($path in $newPaths) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

Replace-ExactOnce `
    -RelativePath "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
    -OldText @'
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor
'@ `
    -NewText @'
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor,
      ICreditProvenanceAdministrationTransactionExecutor
'@ `
    -AlreadyMarker "ICreditProvenanceAdministrationTransactionExecutor" `
    -Description "contrato transaccional de creditos"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<ISongDraftAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<SongDraftAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<ISongDraftAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
builder.Services.AddSingleton<SongDraftAdministrationService>();
builder.Services.AddSingleton<CreditProvenanceAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<CreditProvenanceAdministrationService>();" `
    -Description "servicio de creditos y procedencia"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapSongDraftAdministration();

app.Run();
'@ `
    -NewText @'
app.MapSongDraftAdministration();
app.MapCreditProvenanceAdministration();

app.Run();
'@ `
    -AlreadyMarker "app.MapCreditProvenanceAdministration();" `
    -Description "endpoints de creditos y procedencia"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import { SongDraftDetailPage } from './SongDraftDetailPage';
'@ `
    -NewText @'
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import { CreditProvenancePage } from './CreditProvenancePage';
import { SongDraftDetailPage } from './SongDraftDetailPage';
'@ `
    -AlreadyMarker "import { CreditProvenancePage } from './CreditProvenancePage';" `
    -Description "import UI-MVP-020 creditos"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
  if (match.route.id === 'UI-MVP-019') {
    return <SongDraftDetailPage recordingId={match.params.id ?? ''} />;
  }

  return (
'@ `
    -NewText @'
  if (match.route.id === 'UI-MVP-019') {
    return <SongDraftDetailPage recordingId={match.params.id ?? ''} />;
  }

  if (match.route.id === 'UI-MVP-020') {
    return <CreditProvenancePage recordingId={match.params.id ?? ''} />;
  }

  return (
'@ `
    -AlreadyMarker "return <CreditProvenancePage recordingId={match.params.id ?? ''} />;" `
    -Description "ruta UI-MVP-020 creditos"

Replace-ExactOnce `
    -RelativePath "apps/web/src/app/shell/BackofficeShell.tsx" `
    -OldText @'
import { AppLink } from '../router/navigation';
'@ `
    -NewText @'
import { AppLink } from '../router/navigation';
import { BackofficeSidebar } from './BackofficeSidebar';
'@ `
    -AlreadyMarker "import { BackofficeSidebar } from './BackofficeSidebar';" `
    -Description "import menu lateral backoffice"

Replace-RegexOnce `
    -RelativePath "apps/web/src/app/shell/BackofficeShell.tsx" `
    -Pattern 'type BackofficeItem = \{.*?const administrationItems: readonly BackofficeItem\[\] = \[.*?\n\];\n\n(?=export type BackofficeShellProps)' `
    -Replacement '' `
    -AlreadyMarker "<BackofficeSidebar access={access} pathname={pathname} />" `
    -Description "retiro de menu placeholder"

Replace-RegexOnce `
    -RelativePath "apps/web/src/app/shell/BackofficeShell.tsx" `
    -Pattern '  const items = \[\.\.\.editorialItems, \.\.\.administrationItems\]\.filter\(\(item\) =>\n    access\.capabilities\.includes\(item\.capability\),\n  \);\n\n' `
    -Replacement '' `
    -AlreadyMarker "<BackofficeSidebar access={access} pathname={pathname} />" `
    -Description "retiro de filtro de capabilities obsoletas"

Replace-RegexOnce `
    -RelativePath "apps/web/src/app/shell/BackofficeShell.tsx" `
    -Pattern '<nav[^>]*className="backoffice-nav">.*?</nav>' `
    -Replacement '<BackofficeSidebar access={access} pathname={pathname} />' `
    -AlreadyMarker "<BackofficeSidebar access={access} pathname={pathname} />" `
    -Description "menu lateral editorial y administracion"

Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify credit participant provenance administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL039_USE_DOCKER_PSQL: 'false'
          BL039_API_URL: https://localhost:5454
        run: bash scripts/ci/catalog/verify-credit-provenance-administration.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "BL039_API_URL: https://localhost:5454" `
    -Description "puerta CI BL-MVP-039"

$bash = Resolve-GitBash

& $bash -n "scripts/ci/catalog/verify-credit-provenance-administration.sh"
Assert-LastExitCode "Sintaxis Bash BL-MVP-039"

dotnet restore MusicaAprender.sln
Assert-LastExitCode "Restauracion .NET BL-MVP-039"

dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "Formato .NET BL-MVP-039"

npm.cmd ci
Assert-LastExitCode "npm ci BL-MVP-039"

npm.cmd exec -- prettier --write `
    "apps/web/src/app/shell/BackofficeSidebar.tsx" `
    "apps/web/src/app/shell/backoffice-sidebar.css" `
    "apps/web/src/routes/editorial/CreditProvenancePage.tsx" `
    "apps/web/src/routes/editorial/credit-provenance.css" `
    "apps/web/src/app/shell/BackofficeShell.tsx" `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    "tests/E2ETests/backoffice-sidebar.spec.ts" `
    "tests/E2ETests/credit-provenance-administration.spec.ts" `
    "docs/engineering/catalog/credit-participant-provenance-administration.md" `
    "README/BL-MVP-039_README.md" `
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-039.md"
Assert-LastExitCode "Prettier BL-MVP-039"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalacion Chromium"
}

if (-not $SkipQualityGate) {
    & ".\scripts\check-quality.ps1"
}

dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL-MVP-039"

if (-not $SkipSmoke) {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $env:PGUSER = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "postgres"
    $env:PGPASSWORD = Get-DotEnvValue -Name "POSTGRES_PASSWORD" -DefaultValue "postgres"
    $env:PGDATABASE = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $env:BL039_USE_DOCKER_PSQL = "true"
    $env:BL039_API_URL = "https://localhost:5454"

    & $bash "scripts/ci/catalog/verify-credit-provenance-administration.sh"
    Assert-LastExitCode "Smoke BL-MVP-039"
}

Restore-GeneratedTypeScriptState

$changedAfter = Get-ChangedPaths
$unexpectedAfter = @(
    $changedAfter |
        Where-Object { -not $allowed.Contains($_) }
)

if ($unexpectedAfter.Count -gt 0) {
    throw "BL-MVP-039 genero cambios fuera de inventario: $($unexpectedAfter -join ', ')"
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short --untracked-files=all
git diff --stat
git diff --name-status

Write-Host ""
Write-Host "OK: BL-MVP-039 instalado y validado localmente."
Write-Host "Incluye creditos/procedencia y menu lateral funcional de Editorial/Administracion."
Write-Host "No se ejecuto git add, commit, push ni migracion de produccion."

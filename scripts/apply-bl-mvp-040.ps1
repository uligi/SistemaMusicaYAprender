[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "7c4efd50a7c4039a58429745fa4c04a53c40f959"
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

Write-Host "BL-MVP-040: derechos, usos, territorios, vigencias y evidencia privada..."

Assert-Command -Name "git.exe" -Correction "Instale Git y abra una PowerShell nueva."
Assert-Command -Name "docker.exe" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet.exe" -Correction "Instale el SDK .NET fijado por el repositorio."
Assert-Command -Name "node.exe" -Correction "Instale Node.js fijado por el repositorio."
Assert-Command -Name "npm.cmd" -Correction "Instale npm fijado por el repositorio."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-040 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
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
    "database/postgresql/security/02_database_access.sql"
    "database/postgresql/security/access-matrix.json"
    "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs"
    "apps/api/Program.cs"
    "apps/web/src/app/shell/BackofficeSidebar.tsx"
    "apps/web/src/routes/editorial/CreditProvenancePage.tsx"
    "apps/web/src/routes/editorial/EditorialArea.tsx"
    "tests/E2ETests/backoffice-sidebar.spec.ts"
    "apps/api/Editorial/EditorialRightsAdministrationTransactionExecutor.cs"
    "apps/api/Endpoints/Editorial/RightsAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/RightsProvenancePage.tsx"
    "apps/web/src/routes/editorial/RightsAdministrationPanel.tsx"
    "apps/web/src/routes/editorial/rights-administration.css"
    "docs/engineering/editorial/rights-administration.md"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-040.md"
    "README/BL-MVP-040_README.md"
    "scripts/apply-bl-mvp-040.ps1"
    "scripts/ci/editorial/verify-rights-administration.sh"
    "src/Modules/Editorial/Infrastructure/Administration/IRightsAdministrationTransactionExecutor.cs"
    "src/Modules/Editorial/Infrastructure/Administration/RightsAdministrationService.cs"
    "tests/E2ETests/rights-administration.spec.ts"
)

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($path in $allowedPaths) {
    [void]$allowed.Add($path)
}

$changedBeforePatch = Get-ChangedPaths
$unexpectedBeforePatch = @(
    $changedBeforePatch | Where-Object { -not $allowed.Contains($_) }
)
if ($unexpectedBeforePatch.Count -gt 0) {
    throw "Hay cambios fuera del paquete BL-MVP-040: $($unexpectedBeforePatch -join ', ')"
}

$newPaths = @(
    "apps/api/Editorial/EditorialRightsAdministrationTransactionExecutor.cs"
    "apps/api/Endpoints/Editorial/RightsAdministrationEndpoints.cs"
    "apps/web/src/routes/editorial/RightsProvenancePage.tsx"
    "apps/web/src/routes/editorial/RightsAdministrationPanel.tsx"
    "apps/web/src/routes/editorial/rights-administration.css"
    "docs/engineering/editorial/rights-administration.md"
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-040.md"
    "README/BL-MVP-040_README.md"
    "scripts/apply-bl-mvp-040.ps1"
    "scripts/ci/editorial/verify-rights-administration.sh"
    "src/Modules/Editorial/Infrastructure/Administration/IRightsAdministrationTransactionExecutor.cs"
    "src/Modules/Editorial/Infrastructure/Administration/RightsAdministrationService.cs"
    "tests/E2ETests/rights-administration.spec.ts"
)
foreach ($path in $newPaths) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.Api.Catalog;
using MusicaAprender.Api.Endpoints.Administration;
'@ `
    -NewText @'
using MusicaAprender.Api.Catalog;
using MusicaAprender.Api.Editorial;
using MusicaAprender.Api.Endpoints.Administration;
'@ `
    -AlreadyMarker "using MusicaAprender.Api.Editorial;" `
    -Description "namespace adapter Editorial"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
'@ `
    -NewText @'
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Editorial.Infrastructure.Administration;" `
    -Description "namespace administracion Editorial"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IRightsAdministrationTransactionExecutor>(
    static services =>
        new EditorialRightsAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ArtistAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<IRightsAdministrationTransactionExecutor>(" `
    -Description "contrato transaccional de derechos"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<CreditProvenanceAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<CreditProvenanceAdministrationService>();
builder.Services.AddSingleton<RightsAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<RightsAdministrationService>();" `
    -Description "servicio de derechos"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapCreditProvenanceAdministration();

app.Run();
'@ `
    -NewText @'
app.MapCreditProvenanceAdministration();
app.MapRightsAdministration();

app.Run();
'@ `
    -AlreadyMarker "app.MapRightsAdministration();" `
    -Description "endpoints de derechos"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
import { CreditProvenancePage } from './CreditProvenancePage';
import { SongDraftDetailPage } from './SongDraftDetailPage';
'@ `
    -NewText @'
import { RightsProvenancePage } from './RightsProvenancePage';
import { SongDraftDetailPage } from './SongDraftDetailPage';
'@ `
    -AlreadyMarker "import { RightsProvenancePage } from './RightsProvenancePage';" `
    -Description "import UI-MVP-020 derechos"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/EditorialArea.tsx" `
    -OldText @'
  if (match.route.id === 'UI-MVP-020') {
    return <CreditProvenancePage recordingId={match.params.id ?? ''} />;
  }
'@ `
    -NewText @'
  if (match.route.id === 'UI-MVP-020') {
    return <RightsProvenancePage recordingId={match.params.id ?? ''} />;
  }
'@ `
    -AlreadyMarker "return <RightsProvenancePage recordingId={match.params.id ?? ''} />;" `
    -Description "UI-MVP-020 compuesta con derechos"

Replace-ExactOnce `
    -RelativePath "apps/web/src/app/shell/BackofficeSidebar.tsx" `
    -OldText "        label: 'Créditos y procedencia'," `
    -NewText "        label: 'Derechos y procedencia'," `
    -AlreadyMarker "        label: 'Derechos y procedencia'," `
    -Description "etiqueta menu UI-MVP-020"

Replace-ExactOnce `
    -RelativePath "tests/E2ETests/backoffice-sidebar.spec.ts" `
    -OldText "sidebar.getByRole('link', { name: 'Créditos y procedencia' })" `
    -NewText "sidebar.getByRole('link', { name: 'Derechos y procedencia' })" `
    -AlreadyMarker "sidebar.getByRole('link', { name: 'Derechos y procedencia' })" `
    -Description "prueba sidebar UI-MVP-020"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/editorial/CreditProvenancePage.tsx" `
    -OldText "          Los derechos, territorios, usos y vigencias se completarán en BL-MVP-040." `
    -NewText "          Los derechos, territorios, usos y vigencias se administran en esta misma pantalla." `
    -AlreadyMarker "Los derechos, territorios, usos y vigencias se administran en esta misma pantalla." `
    -Description "texto UI-MVP-020 actualizado"

Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify rights, uses, territories and validity administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL040_USE_DOCKER_PSQL: 'false'
          BL040_API_URL: https://localhost:5455
        run: bash scripts/ci/editorial/verify-rights-administration.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "BL040_API_URL: https://localhost:5455" `
    -Description "puerta CI BL-MVP-040"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/editorial/verify-rights-administration.sh"
Assert-LastExitCode "Sintaxis Bash BL-MVP-040"

& ".\scripts\local\ensure-local-secrets.ps1"
& ".\scripts\local\sync-postgres-secret.ps1"

dotnet restore MusicaAprender.sln
Assert-LastExitCode "Restauracion .NET BL-MVP-040"

dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "Formato .NET BL-MVP-040"

npm.cmd ci
Assert-LastExitCode "npm ci BL-MVP-040"

npm.cmd exec -- prettier --write `
    "apps/web/src/app/shell/BackofficeSidebar.tsx" `
    "apps/web/src/routes/editorial/CreditProvenancePage.tsx" `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    "apps/web/src/routes/editorial/RightsProvenancePage.tsx" `
    "apps/web/src/routes/editorial/RightsAdministrationPanel.tsx" `
    "apps/web/src/routes/editorial/rights-administration.css" `
    "tests/E2ETests/backoffice-sidebar.spec.ts" `
    "tests/E2ETests/rights-administration.spec.ts" `
    "docs/engineering/editorial/rights-administration.md" `
    "README/BL-MVP-040_README.md" `
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-040.md"
Assert-LastExitCode "Prettier BL-MVP-040"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalacion Chromium"
}

if (-not $SkipQualityGate) {
    & ".\scripts\check-quality.ps1"
}

dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL-MVP-040"

if (-not $SkipSmoke) {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
    $env:PGUSER = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "postgres"
    $env:PGPASSWORD = Get-DotEnvValue -Name "POSTGRES_PASSWORD" -DefaultValue "postgres"
    $env:PGDATABASE = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
    $env:BL040_USE_DOCKER_PSQL = "true"
    $env:BL040_API_URL = "https://localhost:5455"

    & ".\scripts\database\prepare-database-access.ps1" -Database $env:PGDATABASE
    Assert-LastExitCode "Acceso minimo para evidencia BL-MVP-040"

    & $bash "scripts/ci/editorial/verify-rights-administration.sh"
    Assert-LastExitCode "Smoke BL-MVP-040"
}

Restore-GeneratedTypeScriptState

$changedAfter = Get-ChangedPaths
$unexpectedAfter = @(
    $changedAfter | Where-Object { -not $allowed.Contains($_) }
)
if ($unexpectedAfter.Count -gt 0) {
    throw "BL-MVP-040 genero cambios fuera de inventario: $($unexpectedAfter -join ', ')"
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short --untracked-files=all
git diff --stat
git diff --name-status

Write-Host ""
Write-Host "OK: BL-MVP-040 instalado y validado localmente."
Write-Host "Incluye derechos, usos, territorios, vigencias, evidencia privada y evaluacion territorial."
Write-Host "PENDIENTE: reiniciar entorno y verificar visualmente UI-MVP-020 antes de staging."
Write-Host "No se ejecuto git add, commit, push ni migracion de produccion."

[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "a3e54e0393d829117f2d6966a5342516a1e5a15d"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs",
    "apps/api/Endpoints/Editorial/EditorialInboxEndpoints.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/EditorialInboxPage.tsx",
    "apps/web/src/routes/editorial/editorial-inbox.css",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-044.md",
    "README/BL-MVP-044_README.md",
    "docs/engineering/editorial/editorial-capability-inbox.md",
    "scripts/apply-bl-mvp-044.ps1",
    "scripts/ci/editorial/verify-editorial-inbox.sh",
    "src/Modules/Catalog/Infrastructure/Administration/EditorialInboxService.cs",
    "src/Modules/Catalog/Infrastructure/Administration/IEditorialInboxTransactionExecutor.cs",
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAuthorizationService.cs",
    "tests/E2ETests/editorial-inbox.spec.ts"
)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    $candidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "No se encontro Git Bash real."
}

function Read-Normalized([string]$RelativePath) {
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta $RelativePath."
    }

    return ([System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8NoBomLf([string]$RelativePath, [string]$Content) {
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoRoot $RelativePath),
        $Content.Replace("`r`n", "`n").Replace("`r", "`n"),
        [System.Text.UTF8Encoding]::new($false))
}

function Replace-ExactOnce(
    [string]$RelativePath,
    [string]$OldText,
    [string]$NewText,
    [string]$AlreadyMarker,
    [string]$Description) {

    $content = Read-Normalized $RelativePath

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
        throw "El bloque de $Description aparece mas de una vez en $RelativePath."
    }

    $updated = $content.Remove($first, $OldText.Length).Insert($first, $NewText)
    Write-Utf8NoBomLf $RelativePath $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    git ls-files --error-unmatch -- $relativePath *> $null
    if ($LASTEXITCODE -ne 0) {
        $global:LASTEXITCODE = 0
        return
    }

    $status = git status --porcelain=v1 -- $relativePath
    if ($status) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restaurar tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Get-ChangedPaths {
    $tracked = @(git diff --name-only)
    Assert-LastExitCode "Leer cambios tracked"
    $untracked = @(git ls-files --others --exclude-standard)
    Assert-LastExitCode "Leer cambios untracked"

    return @($tracked + $untracked | Where-Object { $_ } | Sort-Object -Unique)
}

function Assert-InventorySubset {
    $allowed = @{}
    foreach ($path in $PermanentPaths) {
        $allowed[$path] = $true
    }

    foreach ($path in Get-ChangedPaths) {
        if (-not $allowed.ContainsKey($path)) {
            throw "Ruta fuera del inventario BL-MVP-044: $path"
        }
    }
}

Write-Host "BL-MVP-044: bandeja editorial por capacidades, estado, propietario, bloqueo y siguiente accion..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-044 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-044 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-044 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object { $_ -notin @(
    ".github/workflows/ci.yml",
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAuthorizationService.cs"
) }) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

$executorOld = @'
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor,
      ICreditProvenanceAdministrationTransactionExecutor
'@
$executorNew = @'
    : IArtistAdministrationTransactionExecutor,
      ISongDraftAdministrationTransactionExecutor,
      ICreditProvenanceAdministrationTransactionExecutor,
      IEditorialInboxTransactionExecutor
'@
Replace-ExactOnce `
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
    $executorOld `
    $executorNew `
    "IEditorialInboxTransactionExecutor" `
    "executor de transaccion para bandeja"

$programExecutorOld = @'
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@
$programExecutorNew = @'
builder.Services.AddSingleton<ICreditProvenanceAdministrationTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<IEditorialInboxTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programExecutorOld `
    $programExecutorNew `
    "AddSingleton<IEditorialInboxTransactionExecutor>" `
    "registro executor bandeja"

$programServiceOld = "builder.Services.AddSingleton<CreditProvenanceAdministrationService>();"
$programServiceNew = @'
builder.Services.AddSingleton<CreditProvenanceAdministrationService>();
builder.Services.AddSingleton<EditorialInboxService>();
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programServiceOld `
    $programServiceNew `
    "AddSingleton<EditorialInboxService>" `
    "registro servicio bandeja"

$programMapOld = "app.MapSongDraftAdministration();"
$programMapNew = @'
app.MapSongDraftAdministration();
app.MapEditorialInbox();
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programMapOld `
    $programMapNew `
    "app.MapEditorialInbox();" `
    "endpoint bandeja editorial"

$areaImportOld = "import { ArtistAdministrationPage } from './ArtistAdministrationPage';"
$areaImportNew = @'
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import { EditorialInboxPage } from './EditorialInboxPage';
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaImportOld `
    $areaImportNew `
    "EditorialInboxPage" `
    "import UI-MVP-017"

$areaBranchOld = @'
export default function EditorialArea({ match }: EditorialAreaProps) {
  if (match.route.id === 'UI-MVP-018') {
'@
$areaBranchNew = @'
export default function EditorialArea({ match }: EditorialAreaProps) {
  if (match.route.id === 'UI-MVP-017') {
    return <EditorialInboxPage />;
  }

  if (match.route.id === 'UI-MVP-018') {
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaBranchOld `
    $areaBranchNew `
    "match.route.id === 'UI-MVP-017'" `
    "UI-MVP-017 funcional"

$authAnchor = @'
    public async Task<AuthorizationDecision> AuthorizeAsync(
'@
$authAddition = @'
    public async Task<IReadOnlyList<EffectivePermissionGrant>>
        ResolveScopedPermissionsAsync(
            Guid accountId,
            string correlationId,
            CancellationToken cancellationToken = default)
    {
        ValidateSubject(accountId, correlationId);

        var grants = await LoadEffectiveGrantsAsync(
            accountId,
            correlationId,
            cancellationToken);

        if (!grants.AccountActive)
        {
            return Array.Empty<EffectivePermissionGrant>();
        }

        return grants.Rows
            .Select(static row => new EffectivePermissionGrant(
                row.PermissionCode,
                row.ScopeType,
                row.ModuleCode,
                row.ObjectId))
            .Distinct()
            .OrderBy(static grant => grant.PermissionCode, StringComparer.Ordinal)
            .ThenBy(static grant => grant.ScopeType, StringComparer.Ordinal)
            .ThenBy(static grant => grant.ModuleCode, StringComparer.Ordinal)
            .ThenBy(static grant => grant.ObjectId)
            .ToArray();
    }

    public async Task<AuthorizationDecision> AuthorizeAsync(
'@
Replace-ExactOnce `
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAuthorizationService.cs" `
    $authAnchor `
    $authAddition `
    "ResolveScopedPermissionsAsync" `
    "lectura eficiente de grants con alcance"

$authRecordAnchor = @'
public sealed record AuthorizationCatalog(
'@
$authRecordNew = @'
public sealed record EffectivePermissionGrant(
    string PermissionCode,
    string? ScopeType,
    string? ModuleCode,
    Guid? ObjectId);

public sealed record AuthorizationCatalog(
'@
Replace-ExactOnce `
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAuthorizationService.cs" `
    $authRecordAnchor `
    $authRecordNew `
    "public sealed record EffectivePermissionGrant" `
    "contrato de grant efectivo"

$ciOld = @'
      - name: Verify public song detail by readable slug
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL043_USE_DOCKER_PSQL: 'false'
          BL043_API_URL: https://localhost:5458
        run: bash scripts/ci/catalog/verify-public-song-detail.sh
'@
$ciNew = @'
      - name: Verify public song detail by readable slug
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL043_USE_DOCKER_PSQL: 'false'
          BL043_API_URL: https://localhost:5458
        run: bash scripts/ci/catalog/verify-public-song-detail.sh

      - name: Verify capability-filtered editorial inbox
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL044_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/editorial/verify-editorial-inbox.sh
'@
Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify capability-filtered editorial inbox" `
    "puerta CI BL-MVP-044"

$formatTargets = @(
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/EditorialInboxPage.tsx",
    "apps/web/src/routes/editorial/editorial-inbox.css",
    "tests/E2ETests/editorial-inbox.spec.ts",
    "README/BL-MVP-044_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-044.md",
    "docs/engineering/editorial/editorial-capability-inbox.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL044"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/editorial/verify-editorial-inbox.sh"
Assert-LastExitCode "bash -n BL044"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para smoke..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL044"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-044..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = "musica_aprender"
    $databaseUser = "musica_local"

    if (Test-Path ".env") {
        foreach ($line in Get-Content ".env") {
            if ($line -match '^POSTGRES_DB=(.+)$') { $database = $Matches[1].Trim() }
            if ($line -match '^POSTGRES_USER=(.+)$') { $databaseUser = $Matches[1].Trim() }
        }
    }

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL044_USE_DOCKER_PSQL = $env:BL044_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL044_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/editorial/verify-editorial-inbox.sh"
        Assert-LastExitCode "Smoke BL-MVP-044"
    }
    finally {
        foreach ($name in $previousEnv.Keys) {
            $value = $previousEnv[$name]
            if ($null -eq $value) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$name" $value
            }
        }
    }
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

git diff --check
Assert-LastExitCode "git diff --check BL044"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-044 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-044 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 16 rutas BL-MVP-044."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-044 instalado y validado localmente."
Write-Host "Incluye UI-MVP-017 real, filtro por alcance, estado, propietario, bloqueo, procedencia y siguiente accion."
Write-Host "PENDIENTE: reinicio normal y revision visual de /editorial antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

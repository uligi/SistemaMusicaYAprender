[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "11c79f40461bfaf0b1ad69f5f2b5282f9fd7e521"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-046.md",
    "README/BL-MVP-046_README.md",
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs",
    "apps/api/Endpoints/Editorial/SongEditorialDossierEndpoints.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx",
    "apps/web/src/routes/editorial/song-editorial-dossier.css",
    "docs/engineering/editorial/song-editorial-dossier.md",
    "scripts/apply-bl-mvp-046.ps1",
    "scripts/ci/editorial/verify-song-editorial-dossier.sh",
    "src/Modules/Catalog/Infrastructure/Administration/ISongEditorialDossierTransactionExecutor.cs",
    "src/Modules/Catalog/Infrastructure/Administration/SongEditorialDossierService.cs",
    "tests/E2ETests/editorial-dossier.spec.ts",
    "tests/E2ETests/song-draft-administration.spec.ts"
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
            throw "Ruta fuera del inventario BL-MVP-046: $path"
        }
    }
}

Write-Host "BL-MVP-046: expediente editorial por revision, propietario, derechos, incidencias y accesos..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-046 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-046 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-046 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object { $_ -notin @(
    ".github/workflows/ci.yml",
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "tests/E2ETests/song-draft-administration.spec.ts"
) }) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

$executorOld = @'
      ICreditProvenanceAdministrationTransactionExecutor,
      IEditorialInboxTransactionExecutor
'@
$executorNew = @'
      ICreditProvenanceAdministrationTransactionExecutor,
      IEditorialInboxTransactionExecutor,
      ISongEditorialDossierTransactionExecutor
'@
Replace-ExactOnce `
    "apps/api/Catalog/CatalogAdministrationTransactionExecutor.cs" `
    $executorOld `
    $executorNew `
    "ISongEditorialDossierTransactionExecutor" `
    "executor de transaccion del expediente"

$programExecutorOld = @'
builder.Services.AddSingleton<IEditorialInboxTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@
$programExecutorNew = @'
builder.Services.AddSingleton<IEditorialInboxTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ISongEditorialDossierTransactionExecutor>(
    static services =>
        new CatalogAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programExecutorOld `
    $programExecutorNew `
    "AddSingleton<ISongEditorialDossierTransactionExecutor>" `
    "registro executor expediente"

$programServiceOld = "builder.Services.AddSingleton<EditorialInboxService>();"
$programServiceNew = @'
builder.Services.AddSingleton<EditorialInboxService>();
builder.Services.AddSingleton<SongEditorialDossierService>();
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programServiceOld `
    $programServiceNew `
    "AddSingleton<SongEditorialDossierService>" `
    "registro servicio expediente"

$programMapOld = "app.MapEditorialInbox();"
$programMapNew = @'
app.MapEditorialInbox();
app.MapSongEditorialDossier();
'@
Replace-ExactOnce `
    "apps/api/Program.cs" `
    $programMapOld `
    $programMapNew `
    "app.MapSongEditorialDossier();" `
    "endpoint expediente editorial"

$areaImportOld = "import { SongDraftDetailPage } from './SongDraftDetailPage';"
$areaImportNew = "import { SongEditorialDossierPage } from './SongEditorialDossierPage';"
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaImportOld `
    $areaImportNew `
    "SongEditorialDossierPage" `
    "import UI-MVP-019 expediente"

$areaPageOld = @'
        <SongDraftDetailPage recordingId={match.params.id ?? ''} />
'@
$areaPageNew = @'
        <SongEditorialDossierPage recordingId={match.params.id ?? ''} />
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaPageOld `
    $areaPageNew `
    "<SongEditorialDossierPage" `
    "UI-MVP-019 al expediente agregado"

$oldE2E = @'
  test('abre UI-MVP-019 mostrando obra, grabación y fuente como objetos distintos', async ({
    page,
  }) => {
    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          workId,
          recordingId,
          sourceId,
          artistId,
          artistName: 'サカナクション',
          canonicalTitle: '怪獣',
          languageTag: 'ja',
          recordingTitle: '怪獣',
          recordingDurationMs: 241125,
          providerCode: 'YOUTUBE',
          externalRef: 'a8dgNdJVluc',
          sourceDurationMs: 245000,
          offsetMs: 2500,
          workStatusCode: 'DRAFT',
          recordingStatusCode: 'DRAFT',
          sourceStatusCode: 'DRAFT',
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(
      page.getByRole('heading', {
        level: 1,
        name: 'Obra, grabación y fuente',
      }),
    ).toBeVisible();

    await expect(page.getByText(workId)).toBeVisible();
    await expect(page.getByText(recordingId)).toBeVisible();
    await expect(page.getByText(sourceId)).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Fuente de YouTube' })).toBeVisible();
    await expect(page.getByText('a8dgNdJVluc', { exact: true })).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
'@

$newE2E = @'
  test('abre UI-MVP-019 como expediente agregado sin adelantar publicación', async ({ page }) => {
    await page.route(`**/api/v1/editorial/song-dossiers/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          canonicalTitle: '怪獣',
          recordingTitle: '怪獣',
          artistName: 'サカナクション',
          recordingStatusCode: 'DRAFT',
          providerCode: 'YOUTUBE',
          externalRef: 'a8dgNdJVluc',
          sourceStatusCode: 'DRAFT',
          components: [
            {
              code: 'CATALOG',
              label: 'Catálogo',
              revisionLabel: 'v1',
              stateCode: 'DRAFT',
              ownerLabel: 'Tú',
              exists: true,
              href: null,
            },
          ],
          rights: {
            totalRecords: 0,
            activeRecords: 0,
            provenanceRecords: 0,
            ownerLabel: 'Sin responsable identificado',
            stateCode: 'NOT_STARTED',
          },
          incidents: [],
          allowedAccesses: [
            {
              code: 'DOSSIER',
              label: 'Expediente',
              href: `/editorial/canciones/${recordingId}`,
            },
          ],
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-019"]')).toBeVisible();
    await expect(
      page.getByRole('heading', {
        level: 1,
        name: 'Expediente editorial de canción',
      }),
    ).toBeVisible();
    await expect(page.getByRole('heading', { level: 2, name: '怪獣' })).toBeVisible();
    await expect(page.getByText('Sin incidencias abiertas', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
'@
Replace-ExactOnce `
    "tests/E2ETests/song-draft-administration.spec.ts" `
    $oldE2E `
    $newE2E `
    'data-route-id="UI-MVP-019"' `
    "regresion UI-MVP-019 BL038/045 al expediente BL046"

$ciOld = @'
      - name: Verify new-song editorial assistant
        shell: bash
        run: bash scripts/ci/editorial/verify-new-song-assistant.sh
'@
$ciNew = @'
      - name: Verify new-song editorial assistant
        shell: bash
        run: bash scripts/ci/editorial/verify-new-song-assistant.sh

      - name: Verify song editorial dossier
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL046_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/editorial/verify-song-editorial-dossier.sh
'@
Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify song editorial dossier" `
    "puerta CI BL-MVP-046"

# BL-MVP-046F: runtime schema guards.
$serviceRuntime046 = Read-Normalized "src/Modules/Catalog/Infrastructure/Administration/SongEditorialDossierService.cs"
if ($serviceRuntime046.Contains("rights.recorded_by") -or
    $serviceRuntime046.Contains("rights.recorded_at")) {
    throw "BL-MVP-046 no puede consultar columnas recorded_by/recorded_at inexistentes en editorial.rights_record."
}
if (-not $serviceRuntime046.Contains("latest_audit.occurred_at DESC NULLS LAST")) {
    throw "BL-MVP-046 requiere propietario de derechos derivado desde security.audit_event."
}

$verifierRuntime046 = Read-Normalized "scripts/ci/editorial/verify-song-editorial-dossier.sh"
if (-not $verifierRuntime046.Contains("PREPARE bl046_rights_summary(uuid) AS")) {
    throw "BL-MVP-046 requiere smoke SQL de la consulta real de derechos."
}

$formatTargets = @(
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx",
    "apps/web/src/routes/editorial/song-editorial-dossier.css",
    "tests/E2ETests/editorial-dossier.spec.ts",
    "tests/E2ETests/song-draft-administration.spec.ts",
    "README/BL-MVP-046_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-046.md",
    "docs/engineering/editorial/song-editorial-dossier.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL046"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/editorial/verify-song-editorial-dossier.sh"
Assert-LastExitCode "bash -n BL046"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL046"

Write-Host "Ejecutando Playwright focal BL038/045/046..."
npm.cmd run test:e2e -- tests/E2ETests/song-draft-administration.spec.ts tests/E2ETests/editorial-dossier.spec.ts
Assert-LastExitCode "Playwright focal BL046"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-046..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL046"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-046..."
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
        BL046_USE_DOCKER_PSQL = $env:BL046_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL046_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/editorial/verify-song-editorial-dossier.sh"
        Assert-LastExitCode "Smoke BL-MVP-046"
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
Assert-LastExitCode "git diff --check BL046"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-046 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-046 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 16 rutas BL-MVP-046."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-046 instalado y validado localmente."
Write-Host "Incluye revisiones, propietario, estado, derechos, incidencias y accesos permitidos."
Write-Host "PENDIENTE: reinicio normal y revision visual de /editorial/canciones/{id} antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

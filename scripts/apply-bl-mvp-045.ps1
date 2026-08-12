[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "a8c02b3ee6f15435ff0a66b6e804ec198a810fea"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-045.md",
    "README/BL-MVP-045_README.md",
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/NewSongAssistantPage.tsx",
    "apps/web/src/routes/editorial/SongDraftComposer.tsx",
    "apps/web/src/routes/editorial/new-song-assistant.css",
    "docs/engineering/editorial/new-song-assistant.md",
    "scripts/apply-bl-mvp-045.ps1",
    "scripts/ci/editorial/verify-new-song-assistant.sh",
    "tests/E2ETests/artist-administration.spec.ts",
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
            throw "Ruta fuera del inventario BL-MVP-045: $path"
        }
    }
}

Write-Host "BL-MVP-045: asistente de nueva cancion con minimos canonicos y guardado en borrador..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-045 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-045 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-045 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object { $_ -notin @(
    ".github/workflows/ci.yml",
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SongDraftComposer.tsx",
    "tests/E2ETests/song-draft-administration.spec.ts"
) }) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

$areaImportOld = "import { ArtistAdministrationPage } from './ArtistAdministrationPage';"
$areaImportNew = "import { NewSongAssistantPage } from './NewSongAssistantPage';"
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaImportOld `
    $areaImportNew `
    "NewSongAssistantPage" `
    "import del asistente UI-MVP-018"

$areaRouteOld = @'
  if (match.route.id === 'UI-MVP-018') {
    return <ArtistAdministrationPage />;
  }
'@
$areaRouteNew = @'
  if (match.route.id === 'UI-MVP-018') {
    return <NewSongAssistantPage />;
  }
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $areaRouteOld `
    $areaRouteNew `
    "return <NewSongAssistantPage />;" `
    "ruta UI-MVP-018 al asistente"

$artistHeadingOld = @'
        <p className="artist-administration__eyebrow">F2 · Catálogo musical · M02</p>
        <h1 id="artist-administration-title">Artista canónico para una nueva canción</h1>
'@
$artistHeadingNew = @'
        <p className="artist-administration__eyebrow">Paso 1 de 3 · Artista canónico</p>
        <h2 id="artist-administration-title">Artista canónico para una nueva canción</h2>
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx" `
    $artistHeadingOld `
    $artistHeadingNew `
    "Paso 1 de 3 · Artista canónico" `
    "paso 1 del asistente"

$songHeadingOld = @'
        <p className="song-draft__eyebrow">BL-MVP-038 · Obra, grabación y fuente</p>
        <h2 id="song-draft-title">Completar el borrador de canción</h2>
'@
$songHeadingNew = @'
        <p className="song-draft__eyebrow">Paso 2 de 3 · Obra, grabación y fuente</p>
        <h2 id="song-draft-title">Completar el borrador de canción</h2>
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/SongDraftComposer.tsx" `
    $songHeadingOld `
    $songHeadingNew `
    "Paso 2 de 3 · Obra, grabación y fuente" `
    "paso 2 del asistente"

$createdOld = @'
          <section className="song-draft__created" aria-label="Borrador de canción confirmado">
            <h3>{created.canonicalTitle}</h3>
'@
$createdNew = @'
          <section className="song-draft__created" aria-label="Borrador de canción confirmado">
            <p className="song-draft__eyebrow">Paso 3 de 3 · Borrador guardado</p>
            <h3>{created.canonicalTitle}</h3>
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/SongDraftComposer.tsx" `
    $createdOld `
    $createdNew `
    "Paso 3 de 3 · Borrador guardado" `
    "paso 3 del asistente"

$createdLinkOld = @'
            <a className="ma-link" href={`/editorial/canciones/${created.recordingId}`}>
              Abrir expediente de la canción
            </a>
'@
$createdLinkNew = @'
            <a className="ma-link" href={`/editorial/canciones/${created.recordingId}`}>
              Abrir expediente de la canción
            </a>
            <a
              className="ma-link"
              href={`/editorial/canciones/${created.recordingId}/derechos`}
            >
              Continuar con derechos y procedencia
            </a>
            <p>
              El borrador sigue sin publicar. Revisión, paquete y publicación se completan en sus
              etapas editoriales correspondientes.
            </p>
'@
Replace-ExactOnce `
    "apps/web/src/routes/editorial/SongDraftComposer.tsx" `
    $createdLinkOld `
    $createdLinkNew `
    "Continuar con derechos y procedencia" `
    "continuidad desde borrador guardado"

$artistRegressionOld = @(
    "    await expect("
    "      page.getByRole('heading', {"
    "        level: 1,"
    "        name: 'Artista canónico para una nueva canción',"
    "      }),"
    "    ).toBeVisible();"
) -join "`n"
$artistRegressionNew = @(
    "    await expect(page.getByRole('heading', { level: 1, name: 'Nueva canción' })).toBeVisible();"
    "    await expect("
    "      page.getByRole('heading', {"
    "        level: 2,"
    "        name: 'Artista canónico para una nueva canción',"
    "      }),"
    "    ).toBeVisible();"
) -join "`n"
Replace-ExactOnce `
    "tests/E2ETests/artist-administration.spec.ts" `
    $artistRegressionOld `
    $artistRegressionNew `
    "level: 2,`n        name: 'Artista canónico para una nueva canción'" `
    "regresion BL037 por jerarquia semantica BL045"

$e2eGotoOld = @'
    await page.goto('/editorial/canciones/nueva');

    await page.locator('#artist-search-query').fill('Sakanaction');
'@
$e2eGotoNew = @'
    await page.goto('/editorial/canciones/nueva');

    await expect(page.locator('[data-route-id="UI-MVP-018"]')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1, name: 'Nueva canción' })).toBeFocused();
    await expect(page.getByText('1. Artista canónico', { exact: true })).toBeVisible();
    await expect(page.getByText('Paso 1 de 3 · Artista canónico', { exact: true })).toBeVisible();

    await page.locator('#artist-search-query').fill('Sakanaction');
'@
Replace-ExactOnce `
    "tests/E2ETests/song-draft-administration.spec.ts" `
    $e2eGotoOld `
    $e2eGotoNew `
    "Paso 1 de 3 · Artista canónico" `
    "E2E paso 1 BL045"

$e2eStep2Old = @'
    await expect(
      page.getByRole('heading', {
        name: 'Completar el borrador de canción',
      }),
    ).toBeVisible();

    await page.locator('#song-work-title').fill('怪獣');
'@
$e2eStep2New = @'
    await expect(
      page.getByRole('heading', {
        name: 'Completar el borrador de canción',
      }),
    ).toBeVisible();
    await expect(
      page.getByText('Paso 2 de 3 · Obra, grabación y fuente', { exact: true }),
    ).toBeVisible();

    await page.locator('#song-work-title').fill('怪獣');
'@
Replace-ExactOnce `
    "tests/E2ETests/song-draft-administration.spec.ts" `
    $e2eStep2Old `
    $e2eStep2New `
    "Paso 2 de 3 · Obra, grabación y fuente" `
    "E2E paso 2 BL045"

$e2eCreatedOld = @'
    await expect(
      page.getByRole('link', { name: 'Abrir expediente de la canción' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}`);

    const accessibility = await new AxeBuilder({ page })
'@
$e2eCreatedNew = @'
    await expect(
      page.getByRole('link', { name: 'Abrir expediente de la canción' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}`);
    await expect(page.getByText('Paso 3 de 3 · Borrador guardado', { exact: true })).toBeVisible();
    await expect(
      page.getByRole('link', { name: 'Continuar con derechos y procedencia' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}/derechos`);
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
'@
Replace-ExactOnce `
    "tests/E2ETests/song-draft-administration.spec.ts" `
    $e2eCreatedOld `
    $e2eCreatedNew `
    "Continuar con derechos y procedencia" `
    "E2E paso 3 BL045"

$e2eSecondTestAnchor = @'
  test('abre UI-MVP-019 mostrando obra, grabación y fuente como objetos distintos', async ({
'@
$e2eResponsive = @'
  test('BL-MVP-045 presenta el asistente completo a 320px sin desbordamiento', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto('/editorial/canciones/nueva');

    await expect(page.locator('[data-route-id="UI-MVP-018"]')).toBeVisible();
    await expect(page.getByText('1. Artista canónico', { exact: true })).toBeVisible();
    await expect(page.getByText('2. Obra, grabación y fuente', { exact: true })).toBeVisible();
    await expect(page.getByText('3. Borrador guardado', { exact: true })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('abre UI-MVP-019 mostrando obra, grabación y fuente como objetos distintos', async ({
'@
Replace-ExactOnce `
    "tests/E2ETests/song-draft-administration.spec.ts" `
    $e2eSecondTestAnchor `
    $e2eResponsive `
    "BL-MVP-045 presenta el asistente completo a 320px" `
    "E2E responsive BL045"

$ciOld = @'
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
$ciNew = @'
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

      - name: Verify new-song editorial assistant
        shell: bash
        run: bash scripts/ci/editorial/verify-new-song-assistant.sh
'@
Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify new-song editorial assistant" `
    "puerta CI BL-MVP-045"

$formatTargets = @(
    "apps/web/src/routes/editorial/ArtistAdministrationPage.tsx",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/NewSongAssistantPage.tsx",
    "apps/web/src/routes/editorial/SongDraftComposer.tsx",
    "apps/web/src/routes/editorial/new-song-assistant.css",
    "tests/E2ETests/song-draft-administration.spec.ts",
    "README/BL-MVP-045_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-045.md",
    "docs/engineering/editorial/new-song-assistant.md",
    "tests/E2ETests/artist-administration.spec.ts"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL045"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/editorial/verify-new-song-assistant.sh"
Assert-LastExitCode "bash -n BL045"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL045"

Write-Host "Ejecutando Playwright focal BL038/BL045 con configuracion oficial..."
npm.cmd run test:e2e -- tests/E2ETests/song-draft-administration.spec.ts
Assert-LastExitCode "Playwright focal BL045"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-045..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL045"

& $bash "scripts/ci/editorial/verify-new-song-assistant.sh"
Assert-LastExitCode "Verificacion BL-MVP-045"

Restore-GeneratedTypeScriptState
Assert-InventorySubset

git diff --check
Assert-LastExitCode "git diff --check BL045"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-045 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-045 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 13 rutas BL-MVP-045."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-045 instalado y validado localmente."
Write-Host "Incluye UI-MVP-018 como asistente guiado y conserva los contratos publicados BL037/BL038."
Write-Host "PENDIENTE: reinicio normal y revision visual de /editorial/canciones/nueva antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

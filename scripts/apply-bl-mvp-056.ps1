[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "022f2ffd076744591ef7672b4cd4ddba472c151e"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-056.md",
    "README/BL-MVP-056_README.md",
    "apps/api/Content/ContentAdministrationTransactionExecutor.cs",
    "apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/editorial/synchronization-structure.css",
    "docs/engineering/content/timing-revision-model.md",
    "scripts/apply-bl-mvp-056.ps1",
    "scripts/ci/content/verify-timing-revision-model.sh",
    "src/Modules/Content/Infrastructure/Administration/ITimingAdministrationTransactionExecutor.cs",
    "src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs",
    "tests/E2ETests/timing-revision-model.spec.ts"
)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    foreach ($candidate in @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )) {
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

    return @(
        $tracked + $untracked |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Assert-InventorySubset {
    $allowed = @{}
    foreach ($path in $PermanentPaths) {
        $allowed[$path] = $true
    }

    foreach ($path in Get-ChangedPaths) {
        if (-not $allowed.ContainsKey($path)) {
            throw "Ruta fuera del inventario BL-MVP-056: $path"
        }
    }
}

Write-Host "BL-MVP-056: revisiones y segmentos de sincronizacion por fuente..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-056 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-056 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-056 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object {
    $_ -notin @(
        ".github/workflows/ci.yml",
        "apps/api/Content/ContentAdministrationTransactionExecutor.cs",
        "apps/api/Program.cs",
        "apps/web/src/routes/editorial/EditorialArea.tsx"
    )
}) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

Replace-ExactOnce `
    "apps/api/Content/ContentAdministrationTransactionExecutor.cs" `
    ": ILyricsStructureAdministrationTransactionExecutor" `
    ": ILyricsStructureAdministrationTransactionExecutor, ITimingAdministrationTransactionExecutor" `
    "ITimingAdministrationTransactionExecutor" `
    "executor transaccional de sincronizacion"

Replace-ExactOnce `
    "apps/api/Program.cs" `
    @'
builder.Services.AddSingleton<ILyricsStructureAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@ `
    @'
builder.Services.AddSingleton<ILyricsStructureAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
builder.Services.AddSingleton<ITimingAdministrationTransactionExecutor>(
    static services =>
        new ContentAdministrationTransactionExecutor(
            services.GetRequiredService<BackofficeSecurityTransactionExecutor>()));
'@ `
    "AddSingleton<ITimingAdministrationTransactionExecutor>" `
    "registro executor temporal"

Replace-ExactOnce `
    "apps/api/Program.cs" `
    "builder.Services.AddSingleton<LyricsStructureAdministrationService>();" `
    @'
builder.Services.AddSingleton<LyricsStructureAdministrationService>();
builder.Services.AddSingleton<TimingRevisionAdministrationService>();
'@ `
    "AddSingleton<TimingRevisionAdministrationService>" `
    "registro servicio temporal"

Replace-ExactOnce `
    "apps/api/Program.cs" `
    "app.MapLyricsStructureAdministration();" `
    @'
app.MapLyricsStructureAdministration();
app.MapTimingRevisionAdministration();
'@ `
    "app.MapTimingRevisionAdministration();" `
    "registro endpoints temporales"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    "import { LyricsStructurePage } from './LyricsStructurePage';" `
    @'
import { LyricsStructurePage } from './LyricsStructurePage';
import { SynchronizationStructurePage } from './SynchronizationStructurePage';
'@ `
    "SynchronizationStructurePage" `
    "import UI-MVP-022"

$placeholder = @'
  if (
    match.route.id === 'UI-MVP-022' ||
    match.route.id === 'UI-MVP-023' ||
    match.route.id === 'UI-MVP-024' ||
    match.route.id === 'UI-MVP-025'
  ) {
'@

$syncRoute = @'
  if (match.route.id === 'UI-MVP-022') {
    return (
      <SongWorkspace match={match}>
        <SynchronizationStructurePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (
    match.route.id === 'UI-MVP-023' ||
    match.route.id === 'UI-MVP-024' ||
    match.route.id === 'UI-MVP-025'
  ) {
'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/EditorialArea.tsx" `
    $placeholder `
    $syncRoute `
    "match.route.id === 'UI-MVP-022')" `
    "UI-MVP-022 funcional"

$ciOld = @'
      - name: Verify manual lyrics token segmentation
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL055_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-token-segmentation.sh
'@

$ciNew = @'
      - name: Verify manual lyrics token segmentation
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL055_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-token-segmentation.sh

      - name: Verify timing revisions and synchronization segments
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL056_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-timing-revision-model.sh
'@

Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify timing revisions and synchronization segments" `
    "puerta CI BL-MVP-056"

$formatTargets = @(
    "apps/web/src/routes/editorial/EditorialArea.tsx",
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/editorial/synchronization-structure.css",
    "tests/E2ETests/timing-revision-model.spec.ts",
    "README/BL-MVP-056_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-056.md",
    "docs/engineering/content/timing-revision-model.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL056"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/content/verify-timing-revision-model.sh"
Assert-LastExitCode "bash -n BL056"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL056"

Write-Host "Ejecutando Playwright focal BL055/056..."
npm.cmd run test:e2e -- tests/E2ETests/lyrics-token-segmentation.spec.ts tests/E2ETests/timing-revision-model.spec.ts
Assert-LastExitCode "Playwright focal BL056"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-056..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL056"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-056..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = "musica_aprender"
    $databaseUser = "musica_local"

    if (Test-Path ".env") {
        foreach ($line in Get-Content ".env") {
            if ($line -match '^POSTGRES_DB=(.+)$') {
                $database = $Matches[1].Trim()
            }
            if ($line -match '^POSTGRES_USER=(.+)$') {
                $databaseUser = $Matches[1].Trim()
            }
        }
    }

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL056_USE_DOCKER_PSQL = $env:BL056_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL056_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/content/verify-timing-revision-model.sh"
        Assert-LastExitCode "Smoke BL-MVP-056"
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
Assert-LastExitCode "git diff --check BL056"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-056 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-056 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 15 rutas BL-MVP-056."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-056 instalado y validado localmente."
Write-Host "Incluye revisiones por fuente, milisegundos, tiempos por linea/token y validacion de solapamientos."
Write-Host "No implementa todavia editor de linea de tiempo BL057, YouTube ni publicacion."
Write-Host "PENDIENTE: reinicio normal y revision visual real de UI-MVP-022 antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

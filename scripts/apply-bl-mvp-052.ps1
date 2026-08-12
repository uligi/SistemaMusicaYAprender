[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "f7ff536295b82d556ca589f5cf5fd7143d79a178"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-052.md",
    "README/BL-MVP-052_README.md",
    "apps/api/Endpoints/Editorial/RecordingDraftAutosaveEndpoints.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/editorial/RecordingAutosavePanel.tsx",
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx",
    "apps/web/src/routes/editorial/recording-autosave.css",
    "apps/web/src/routes/editorial/useEditorialAutosave.ts",
    "docs/engineering/editorial/editorial-autosave-concurrency.md",
    "scripts/apply-bl-mvp-052.ps1",
    "scripts/ci/editorial/verify-editorial-autosave-conflicts.sh",
    "src/Modules/Catalog/Infrastructure/Administration/RecordingDraftAutosaveService.cs",
    "tests/E2ETests/editorial-autosave-conflict.spec.ts"
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
            throw "Ruta fuera del inventario BL-MVP-052: $path"
        }
    }
}

Write-Host "BL-MVP-052: autoguardado, ETag/If-Match y conflictos editoriales..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-052 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-052 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-052 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object {
    $_ -notin @(
        ".github/workflows/ci.yml",
        "apps/api/Program.cs",
        "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx"
    )
}) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

Replace-ExactOnce `
    "apps/api/Program.cs" `
    "builder.Services.AddSingleton<SongEditorialDossierService>();" `
    @'
builder.Services.AddSingleton<SongEditorialDossierService>();
builder.Services.AddSingleton<RecordingDraftAutosaveService>();
'@ `
    "AddSingleton<RecordingDraftAutosaveService>" `
    "registro servicio autoguardado"

Replace-ExactOnce `
    "apps/api/Program.cs" `
    "app.MapSongEditorialDossier();" `
    @'
app.MapSongEditorialDossier();
app.MapRecordingDraftAutosave();
'@ `
    "app.MapRecordingDraftAutosave();" `
    "endpoint autoguardado"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx" `
    "import { StateMessage } from '../../components/ui';" `
    @'
import { StateMessage } from '../../components/ui';
import { RecordingAutosavePanel } from './RecordingAutosavePanel';
'@ `
    "RecordingAutosavePanel" `
    "import panel autoguardado"

$identityClose = @'
          </section>

          <section aria-labelledby="song-dossier-components">
'@

$identityWithAutosave = @'
          </section>

          <RecordingAutosavePanel recordingId={recordingId} />

          <section aria-labelledby="song-dossier-components">
'@

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx" `
    $identityClose `
    $identityWithAutosave `
    "<RecordingAutosavePanel recordingId={recordingId} />" `
    "panel autoguardado en UI-MVP-019"

$ciOld = @'
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

$ciNew = @'
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

      - name: Verify editorial autosave and conflicts
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL052_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/editorial/verify-editorial-autosave-conflicts.sh
'@

Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify editorial autosave and conflicts" `
    "puerta CI BL-MVP-052"

$formatTargets = @(
    "apps/web/src/routes/editorial/RecordingAutosavePanel.tsx",
    "apps/web/src/routes/editorial/SongEditorialDossierPage.tsx",
    "apps/web/src/routes/editorial/recording-autosave.css",
    "apps/web/src/routes/editorial/useEditorialAutosave.ts",
    "tests/E2ETests/editorial-autosave-conflict.spec.ts",
    "README/BL-MVP-052_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-052.md",
    "docs/engineering/editorial/editorial-autosave-concurrency.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL052"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/editorial/verify-editorial-autosave-conflicts.sh"
Assert-LastExitCode "bash -n BL052"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL052"

Write-Host "Ejecutando Playwright focal BL046/052..."
npm.cmd run test:e2e -- tests/E2ETests/editorial-dossier.spec.ts tests/E2ETests/editorial-autosave-conflict.spec.ts
Assert-LastExitCode "Playwright focal BL052"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-052..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL052"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-052..."
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
        BL052_USE_DOCKER_PSQL = $env:BL052_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL052_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/editorial/verify-editorial-autosave-conflicts.sh"
        Assert-LastExitCode "Smoke BL-MVP-052"
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
Assert-LastExitCode "git diff --check BL052"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-052 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-052 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 14 rutas BL-MVP-052."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-052 instalado y validado localmente."
Write-Host "Incluye Guardando/Guardado/Conflicto, ETag/If-Match y comparacion antes de rebase."
Write-Host "PENDIENTE: reinicio normal y revision visual real de UI-MVP-019 antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

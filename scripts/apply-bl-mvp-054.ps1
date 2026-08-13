[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "7ab4a063159c4faa9c7fae787346baa171dbd0a1"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-054.md",
    "README/BL-MVP-054_README.md",
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs",
    "apps/web/src/routes/editorial/LyricsStructurePage.tsx",
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx",
    "apps/web/src/routes/editorial/lyrics-structured-editor.css",
    "docs/engineering/content/lyrics-structured-editor.md",
    "scripts/apply-bl-mvp-054.ps1",
    "scripts/ci/content/verify-lyrics-structured-editor.sh",
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs",
    "tests/E2ETests/lyrics-structure.spec.ts",
    "tests/E2ETests/lyrics-structured-editor.spec.ts"
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
            throw "Ruta fuera del inventario BL-MVP-054: $path"
        }
    }
}

function Assert-Contains(
    [string]$RelativePath,
    [string]$Marker,
    [string]$Description) {

    if (-not (Read-Normalized $RelativePath).Contains($Marker)) {
        throw "El archivo autoritativo BL054 no contiene $Description en $RelativePath."
    }

    Write-Host "OK: $Description confirmado."
}

Write-Host "BL-MVP-054: editor estructurado de letra japonesa..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-054 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-054 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-054 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object { $_ -ne ".github/workflows/ci.yml" }) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

$legacyLocatorOld = @(
    "    await expect(page.getByText('が 怪獣', { exact: true })).toBeVisible();",
    "    await expect(page.getByText('が 怪獣', { exact: true })).toBeVisible();"
) -join "`n"

$legacyLocatorNew = @(
    "    const structureTree = page.getByLabel('Árbol estructural');",
    "    await expect(structureTree.getByText('が 怪獣', { exact: true })).toBeVisible();",
    "    await expect(structureTree.getByText('が 怪獣', { exact: true })).toBeVisible();"
) -join "`n"

Replace-ExactOnce `
    "tests/E2ETests/lyrics-structure.spec.ts" `
    $legacyLocatorOld `
    $legacyLocatorNew `
    "const structureTree = page.getByLabel('Árbol estructural');" `
    "regresion BL053 por texto duplicado en editor BL054"

Assert-Contains `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    "EnsureExpectedRevision(latest, expected);" `
    "comparacion de version de letra"

Assert-Contains `
    "src/Modules/Content/Infrastructure/Administration/LyricsStructureAdministrationService.cs" `
    "[UNKNOWN:PENDING_TRANSCRIPTION]" `
    "marcadores cerrados de contenido desconocido"

Assert-Contains `
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs" `
    "StatusCodes.Status412PreconditionFailed" `
    "conflicto HTTP 412"

Assert-Contains `
    "apps/api/Endpoints/Editorial/LyricsStructureAdministrationEndpoints.cs" `
    'context.Response.Headers["ETag"]' `
    "ETag de revisión"

Assert-Contains `
    "apps/web/src/routes/editorial/LyricsStructurePage.tsx" `
    "<LyricsStructuredEditor" `
    "editor en UI-MVP-021"

$ciOld = @'
      - name: Verify lyrics revision structure
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL053_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-structure-model.sh
'@

$ciNew = @'
      - name: Verify lyrics revision structure
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL053_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-structure-model.sh

      - name: Verify structured Japanese lyrics editor
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL054_USE_DOCKER_PSQL: 'false'
        run: bash scripts/ci/content/verify-lyrics-structured-editor.sh
'@

Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify structured Japanese lyrics editor" `
    "puerta CI BL-MVP-054"

$formatTargets = @(
    "apps/web/src/routes/editorial/LyricsStructurePage.tsx",
    "apps/web/src/routes/editorial/LyricsStructuredEditor.tsx",
    "apps/web/src/routes/editorial/lyrics-structured-editor.css",
    "tests/E2ETests/lyrics-structure.spec.ts",
    "tests/E2ETests/lyrics-structured-editor.spec.ts",
    "README/BL-MVP-054_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-054.md",
    "docs/engineering/content/lyrics-structured-editor.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL054"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/content/verify-lyrics-structured-editor.sh"
Assert-LastExitCode "bash -n BL054"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL054"

Write-Host "Ejecutando Playwright focal BL053/054..."
npm.cmd run test:e2e -- tests/E2ETests/lyrics-structure.spec.ts tests/E2ETests/lyrics-structured-editor.spec.ts
Assert-LastExitCode "Playwright focal BL054"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-054..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL054"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-054..."
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
        BL054_USE_DOCKER_PSQL = $env:BL054_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL054_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/content/verify-lyrics-structured-editor.sh"
        Assert-LastExitCode "Smoke BL-MVP-054"
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
Assert-LastExitCode "git diff --check BL054"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-054 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-054 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 13 rutas BL-MVP-054."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-054 instalado y validado localmente."
Write-Host "Incluye secciones, lineas, voces, contenido desconocido, previsualizacion y conflicto ETag."
Write-Host "No implementa todavia segmentacion manual BL055, sincronizacion ni publicacion."
Write-Host "PENDIENTE: reinicio normal y revision visual real de UI-MVP-021 antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

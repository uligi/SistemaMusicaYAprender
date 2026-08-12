[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "17eaa2ab0b729328b678a2404011b11b3dd3ed81"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/PublicCatalog/PublicCatalogSearchEndpoints.cs",
    "apps/api/Program.cs",
    "apps/worker/MusicaAprender.Worker.csproj",
    "apps/worker/Program.cs",
    "apps/worker/Workers/PublicCatalogProjectionWorker.cs",
    "apps/worker/packages.lock.json",
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/public/PublicSongCatalogPage.tsx",
    "apps/web/src/routes/public/public-song-catalog.css",
    "database/postgresql/security/02_database_access.sql",
    "database/postgresql/security/access-matrix.json",
    "docs/engineering/catalog/postgresql-public-search.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-042.md",
    "README/BL-MVP-042_README.md",
    "scripts/apply-bl-mvp-042.ps1",
    "scripts/ci/catalog/verify-public-catalog-search.sh",
    "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs",
    "tests/E2ETests/public-catalog-search.spec.ts",
    "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs"
)

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
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
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $content.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $path = Join-Path $RepoRoot $RelativePath
    [System.IO.File]::WriteAllText(
        $path,
        $Content.Replace("`r`n", "`n").Replace("`r", "`n"),
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
    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }
    $old = $OldText.Replace("`r`n", "`n").Replace("`r", "`n")
    $new = $NewText.Replace("`r`n", "`n").Replace("`r", "`n")
    $first = $content.IndexOf($old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }
    $second = $content.IndexOf($old, $first + $old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "El bloque para $Description aparece mas de una vez en $RelativePath."
    }
    $updated = $content.Remove($first, $old.Length).Insert($first, $new)
    Write-Utf8NoBomLf -RelativePath $RelativePath -Content $updated
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
        Write-Host "Restaurado $relativePath por ser salida incremental."
    }
}

function Get-ChangedPaths {
    $tracked = @(git diff --name-only)
    Assert-LastExitCode "Inventario tracked"
    $untracked = @(git ls-files --others --exclude-standard)
    Assert-LastExitCode "Inventario untracked"
    return @($tracked + $untracked | Where-Object { $_ } | Sort-Object -Unique)
}

function Assert-InventorySubset {
    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($path in $PermanentPaths) {
        [void]$allowed.Add($path)
    }
    $outside = @(Get-ChangedPaths | Where-Object { -not $allowed.Contains($_) })
    if ($outside.Count -gt 0) {
        throw "BL-MVP-042 encontro cambios fuera de su inventario: $($outside -join ', ')"
    }
}

function Get-DotEnvValue {
    param([string]$Name, [string]$DefaultValue)
    if (-not (Test-Path ".env")) {
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

Write-Host "BL-MVP-042: busqueda interna PostgreSQL, UI-MVP-002/003 y paginacion estable..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"
if ($head -cne $ExpectedBase) {
    throw "BL-MVP-042 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-042 debe ejecutarse desde main; rama actual: '$branch'."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-042 requiere indice sin staging."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object { $_ -notin @(
    ".github/workflows/ci.yml",
    "apps/api/Program.cs",
    "apps/worker/packages.lock.json",
    "database/postgresql/security/02_database_access.sql",
    "database/postgresql/security/access-matrix.json",
    "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs"
) }) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta $required. Extraiga nuevamente el paquete BL-MVP-042."
    }
}

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "using MusicaAprender.Modules.Catalog.Infrastructure.Administration;`n" `
    -NewText "using MusicaAprender.Modules.Catalog.Infrastructure.Administration;`nusing MusicaAprender.Modules.Catalog.Infrastructure.Search;`n" `
    -AlreadyMarker "using MusicaAprender.Modules.Catalog.Infrastructure.Search;" `
    -Description "namespace busqueda publica API"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "builder.Services.AddSingleton<PublicCatalogProjectionService>();`n" `
    -NewText "builder.Services.AddSingleton<PublicCatalogProjectionService>();`nbuilder.Services.AddSingleton<PublicCatalogSearchService>();`n" `
    -AlreadyMarker "builder.Services.AddSingleton<PublicCatalogSearchService>();" `
    -Description "servicio busqueda publica API"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "app.MapPublicCatalogProjection();`n" `
    -NewText "app.MapPublicCatalogProjection();`napp.MapPublicCatalogSearch();`n" `
    -AlreadyMarker "app.MapPublicCatalogSearch();" `
    -Description "endpoint busqueda publica API"

$accessAnchor = @'
DO $public_catalog_projection_access$
BEGIN
    IF to_regclass('editorial.published_package_projection') IS NOT NULL THEN
        GRANT DELETE ON TABLE editorial.published_package_projection TO jp_worker;
    END IF;
END;
$public_catalog_projection_access$;
'@

$accessReplacement = @'
DO $public_catalog_projection_access$
BEGIN
    IF to_regclass('editorial.published_package_projection') IS NOT NULL THEN
        GRANT DELETE ON TABLE editorial.published_package_projection TO jp_worker;
    END IF;
END;
$public_catalog_projection_access$;

-- BL-MVP-042. song_search_document es una proyeccion derivada. El worker
-- puede retirar exclusivamente documentos obsoletos; la API conserva lectura.
DO $public_catalog_search_access$
BEGIN
    IF to_regclass('catalog.song_search_document') IS NOT NULL THEN
        GRANT DELETE ON TABLE catalog.song_search_document TO jp_worker;
    END IF;
END;
$public_catalog_search_access$;
'@

Replace-ExactOnce `
    -RelativePath "database/postgresql/security/02_database_access.sql" `
    -OldText $accessAnchor `
    -NewText $accessReplacement `
    -AlreadyMarker "DO `$public_catalog_search_access`$" `
    -Description "DELETE minimo indice reconstruible"

Replace-ExactOnce `
    -RelativePath "database/postgresql/security/access-matrix.json" `
    -OldText '      "DELETE: editorial.published_package_projection only (reconstructible public catalog)"' `
    -NewText '      "DELETE: editorial.published_package_projection and catalog.song_search_document only (reconstructible public projections)"' `
    -AlreadyMarker '"DELETE: editorial.published_package_projection and catalog.song_search_document only (reconstructible public projections)"' `
    -Description "matriz minimo privilegio BL042"

$apiProbe = @'
        await ExpectPermissionDeniedAsync(
            "API no DELETE proyeccion publica",
            "jp_login_api",
            "postgres_api_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");
'@

$apiProbeNew = @'
        await ExpectPermissionDeniedAsync(
            "API no DELETE proyeccion publica",
            "jp_login_api",
            "postgres_api_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");

        await ExpectPermissionDeniedAsync(
            "API no DELETE indice busqueda publica",
            "jp_login_api",
            "postgres_api_password",
            "DELETE FROM catalog.song_search_document WHERE false;");
'@

Replace-ExactOnce `
    -RelativePath "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs" `
    -OldText $apiProbe `
    -NewText $apiProbeNew `
    -AlreadyMarker '"API no DELETE indice busqueda publica"' `
    -Description "prueba negativa API indice busqueda"

$workerProbe = @'
        await ExpectSuccessAsync(
            "Worker DELETE proyeccion publica reconstruible",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");
'@

$workerProbeNew = @'
        await ExpectSuccessAsync(
            "Worker DELETE proyeccion publica reconstruible",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");

        await ExpectSuccessAsync(
            "Worker DELETE indice busqueda reconstruible",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM catalog.song_search_document WHERE false;");
'@

Replace-ExactOnce `
    -RelativePath "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs" `
    -OldText $workerProbe `
    -NewText $workerProbeNew `
    -AlreadyMarker '"Worker DELETE indice busqueda reconstruible"' `
    -Description "prueba positiva worker indice busqueda"

$ciAnchor = @'
      - name: Verify eligible and rebuildable public catalog projection
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL041_USE_DOCKER_PSQL: 'false'
          BL041_API_URL: https://localhost:5456
        run: bash scripts/ci/catalog/verify-public-catalog-projection.sh
'@

$ciReplacement = @'
      - name: Verify eligible and rebuildable public catalog projection
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL041_USE_DOCKER_PSQL: 'false'
          BL041_API_URL: https://localhost:5456
        run: bash scripts/ci/catalog/verify-public-catalog-projection.sh

      - name: Verify internal PostgreSQL public catalog search
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL042_USE_DOCKER_PSQL: 'false'
          BL042_API_URL: https://localhost:5457
        run: bash scripts/ci/catalog/verify-public-catalog-search.sh
'@

Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText $ciAnchor `
    -NewText $ciReplacement `
    -AlreadyMarker "Verify internal PostgreSQL public catalog search" `
    -Description "puerta CI BL-MVP-042"

$bash = Resolve-GitBash
Write-Host "Validando sintaxis del smoke BL-MVP-042..."
& $bash -n "scripts/ci/catalog/verify-public-catalog-search.sh"
Assert-LastExitCode "bash -n smoke BL042"

Write-Host "Actualizando packages.lock del Worker por referencia a Catalog..."
dotnet restore MusicaAprender.sln
Assert-LastExitCode "dotnet restore para lockfiles"

$workerLock = Get-Content "apps/worker/packages.lock.json" -Raw | ConvertFrom-Json
$catalogDependency = $workerLock.dependencies.'net9.0'.PSObject.Properties[
    'MusicaAprender.Modules.Catalog'
]
if ($null -eq $catalogDependency -or
    [string]$catalogDependency.Value.type -cne "Project") {
    throw "apps/worker/packages.lock.json no refleja Catalog como Project."
}
Write-Host "OK: packages.lock worker contiene Catalog como Project."

$formatTargets = @(
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/public/PublicSongCatalogPage.tsx",
    "apps/web/src/routes/public/public-song-catalog.css",
    "tests/E2ETests/public-catalog-search.spec.ts",
    "README/BL-MVP-042_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-042.md",
    "docs/engineering/catalog/postgresql-public-search.md"
)
npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL042"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

if (-not $SkipQualityGate) {
    Write-Host "Ejecutando puerta local completa de calidad..."
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para smoke..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL042"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-042..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
    $databaseUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"

    & "$RepoRoot/scripts/database/prepare-database-access.ps1" -Database $database

    Write-Host "Verificando minimo privilegio actualizado BL-MVP-042..."
    dotnet run `
        --project tools/DatabaseAccessVerifier/MusicaAprender.DatabaseAccessVerifier.csproj `
        --configuration Release `
        --no-build `
        --no-restore `
        -- `
        --host localhost `
        --port 5432 `
        --database $database `
        --secret-directory secrets/local
    Assert-LastExitCode "DatabaseAccessVerifier BL042"

    $postgresPassword = [System.IO.File]::ReadAllText(
        (Join-Path $RepoRoot "secrets/local/postgres_password")).Trim()

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL042_USE_DOCKER_PSQL = $env:BL042_USE_DOCKER_PSQL
        BL042_SKIP_ACCESS_PREP = $env:BL042_SKIP_ACCESS_PREP
        BL042_API_URL = $env:BL042_API_URL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL042_USE_DOCKER_PSQL = "true"
        $env:BL042_SKIP_ACCESS_PREP = "true"
        $env:BL042_API_URL = "https://localhost:5457"

        Write-Host "Ejecutando smoke real de busqueda publica..."
        & $bash "scripts/ci/catalog/verify-public-catalog-search.sh"
        Assert-LastExitCode "Smoke BL-MVP-042"
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
Assert-LastExitCode "git diff --check BL042"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-042 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-042 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 20 rutas BL-MVP-042."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-042 instalado y validado localmente."
Write-Host "Incluye busqueda PostgreSQL, UI-MVP-002/003, Unicode, cursor estable y revalidacion."
Write-Host "PENDIENTE: reinicio normal y revision visual de /canciones y /canciones?consulta= antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "c6ee8afcb1acbc56654294a9b9fcd3e183b0973c"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/PublicCatalog/PublicCatalogProjectionEndpoints.cs",
    "apps/api/Program.cs",
    "apps/worker/MusicaAprender.Worker.csproj",
    "apps/worker/packages.lock.json",
    "apps/worker/Program.cs",
    "apps/worker/Workers/PublicCatalogProjectionWorker.cs",
    "database/postgresql/security/02_database_access.sql",
    "database/postgresql/security/access-matrix.json",
    "docs/engineering/catalog/public-catalog-projection.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-041.md",
    "README/BL-MVP-041_README.md",
    "scripts/apply-bl-mvp-041.ps1",
    "scripts/ci/catalog/verify-public-catalog-projection.sh",
    "src/Modules/Editorial/Infrastructure/Publication/PublicCatalogProjectionService.cs",
    "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs"
)

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
    $parent = Split-Path -Parent $path
    if (-not (Test-Path $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

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
    $tracked = git ls-files --error-unmatch -- $relativePath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tracked) {
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
    param([Parameter(Mandatory = $true)][string]$Stage)

    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($path in $PermanentPaths) {
        [void]$allowed.Add($path)
    }

    $outside = @(
        Get-ChangedPaths |
            Where-Object { -not $allowed.Contains($_) }
    )

    if ($outside.Count -gt 0) {
        throw "$Stage encontro cambios fuera de BL-MVP-041: $($outside -join ', ')"
    }
}

function Assert-FinalInventory {
    Restore-GeneratedTypeScriptState
    $actual = @(Get-ChangedPaths)
    $expected = @($PermanentPaths | Sort-Object -Unique)

    if ($actual.Count -ne $expected.Count) {
        throw "Inventario final BL-MVP-041 esperaba $($expected.Count) rutas y obtuvo $($actual.Count)."
    }

    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ($actual[$index] -cne $expected[$index]) {
            throw "Inventario final BL-MVP-041 no coincide. Esperado '$($expected[$index])', obtenido '$($actual[$index])'."
        }
    }

    Write-Host "OK: inventario final exacto de 16 rutas BL-MVP-041."
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

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

Write-Host "BL-MVP-041: construyendo proyeccion publica elegible y revalidacion canonica..."

Assert-Command -Name "git.exe" -Correction "Instale Git for Windows."
Assert-Command -Name "docker.exe" -Correction "Instale/inicie Docker Desktop."
Assert-Command -Name "dotnet.exe" -Correction "Instale el SDK fijado por global.json."
Assert-Command -Name "node.exe" -Correction "Instale Node segun .nvmrc."
Assert-Command -Name "npm.cmd" -Correction "Instale npm junto con Node."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"
if ($head -cne $ExpectedBase) {
    throw "BL-MVP-041 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-041 debe aplicarse desde main; rama actual: '$branch'."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-041 requiere indice sin staging."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset -Stage "BL-MVP-041 antes de aplicar"

foreach ($requiredNewFile in @(
    "apps/api/Endpoints/PublicCatalog/PublicCatalogProjectionEndpoints.cs",
    "apps/worker/Workers/PublicCatalogProjectionWorker.cs",
    "src/Modules/Editorial/Infrastructure/Publication/PublicCatalogProjectionService.cs",
    "scripts/ci/catalog/verify-public-catalog-projection.sh",
    "README/BL-MVP-041_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-041.md",
    "docs/engineering/catalog/public-catalog-projection.md"
)) {
    if (-not (Test-Path $requiredNewFile -PathType Leaf)) {
        throw "El paquete BL-MVP-041 esta incompleto: falta $requiredNewFile."
    }
}

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.Api.Endpoints.Identity;
using MusicaAprender.Api.Endpoints.Security;
'@ `
    -NewText @'
using MusicaAprender.Api.Endpoints.Identity;
using MusicaAprender.Api.Endpoints.PublicCatalog;
using MusicaAprender.Api.Endpoints.Security;
'@ `
    -AlreadyMarker "using MusicaAprender.Api.Endpoints.PublicCatalog;" `
    -Description "namespace endpoint proyeccion publica"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
'@ `
    -NewText @'
using MusicaAprender.Modules.Editorial.Infrastructure.Administration;
using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;" `
    -Description "namespace servicio proyeccion publica"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<RightsAdministrationService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -NewText @'
builder.Services.AddSingleton<RightsAdministrationService>();
builder.Services.AddSingleton<PublicCatalogProjectionService>();
builder.Services.AddSingleton<ConfigurationAdministrationService>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<PublicCatalogProjectionService>();" `
    -Description "registro servicio proyeccion publica API"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapRightsAdministration();

app.Run();
'@ `
    -NewText @'
app.MapRightsAdministration();
app.MapPublicCatalogProjection();

app.Run();
'@ `
    -AlreadyMarker "app.MapPublicCatalogProjection();" `
    -Description "endpoint lectura proyeccion publica"

Replace-ExactOnce `
    -RelativePath "apps/worker/Program.cs" `
    -OldText @'
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
'@ `
    -NewText @'
using MusicaAprender.BuildingBlocks.Infrastructure.Reliability.DependencyInjection;
using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;
using MusicaAprender.Modules.Security.Infrastructure.Registration;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Editorial.Infrastructure.PublicCatalog;" `
    -Description "namespace proyeccion publica worker"

Replace-ExactOnce `
    -RelativePath "apps/worker/Program.cs" `
    -OldText @'
builder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);
builder.Services.AddHostedService<HeartbeatWorker>();
'@ `
    -NewText @'
builder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);
builder.Services.AddSingleton<PublicCatalogProjectionService>();
builder.Services.AddHostedService<PublicCatalogProjectionWorker>();
builder.Services.AddHostedService<HeartbeatWorker>();
'@ `
    -AlreadyMarker "builder.Services.AddHostedService<PublicCatalogProjectionWorker>();" `
    -Description "worker reconstruccion proyeccion publica"

Replace-ExactOnce `
    -RelativePath "apps/worker/MusicaAprender.Worker.csproj" `
    -OldText @'
    <ProjectReference Include="..\..\src\Modules\Security\MusicaAprender.Modules.Security.csproj" />
'@ `
    -NewText @'
    <ProjectReference Include="..\..\src\Modules\Security\MusicaAprender.Modules.Security.csproj" />
    <ProjectReference Include="..\..\src\Modules\Editorial\MusicaAprender.Modules.Editorial.csproj" />
'@ `
    -AlreadyMarker "..\..\src\Modules\Editorial\MusicaAprender.Modules.Editorial.csproj" `
    -Description "referencia Editorial desde worker"

Replace-ExactOnce `
    -RelativePath "database/postgresql/security/02_database_access.sql" `
    -OldText @'
-- EF Core mantiene __EFMigrationsHistory en public. Solo el rol de migracion
'@ `
    -NewText @'
-- BL-MVP-041. La proyeccion publica es derivada y reconstruible. El worker
-- puede retirar exclusivamente filas obsoletas de esta proyeccion; no recibe
-- DELETE sobre publication, availability, catalogo ni evidencia canonica.
DO $public_catalog_projection_access$
BEGIN
    IF to_regclass('editorial.published_package_projection') IS NOT NULL THEN
        GRANT DELETE ON TABLE editorial.published_package_projection TO jp_worker;
    END IF;
END;
$public_catalog_projection_access$;

-- EF Core mantiene __EFMigrationsHistory en public. Solo el rol de migracion
'@ `
    -AlreadyMarker "DO `$public_catalog_projection_access`$" `
    -Description "DELETE minimo de proyeccion publica reconstruible"

Replace-ExactOnce `
    -RelativePath "database/postgresql/security/access-matrix.json" `
    -OldText @'
      "SELECT/INSERT/UPDATE/DELETE: ops",
      "INSERT/UPDATE: selected projections"
'@ `
    -NewText @'
      "SELECT/INSERT/UPDATE/DELETE: ops",
      "INSERT/UPDATE: selected projections",
      "DELETE: editorial.published_package_projection only (reconstructible public catalog)"
'@ `
    -AlreadyMarker "DELETE: editorial.published_package_projection only" `
    -Description "matriz minimo privilegio BL041"

Replace-ExactOnce `
    -RelativePath "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs" `
    -OldText @'
        await ExpectPermissionDeniedAsync(
            "API no DDL catalog",
            "jp_login_api",
            "postgres_api_password",
            "CREATE TABLE catalog.bl_mvp_012_probe(id integer);",
            "DROP TABLE IF EXISTS catalog.bl_mvp_012_probe;");

        await ExpectSuccessAsync(
'@ `
    -NewText @'
        await ExpectPermissionDeniedAsync(
            "API no DDL catalog",
            "jp_login_api",
            "postgres_api_password",
            "CREATE TABLE catalog.bl_mvp_012_probe(id integer);",
            "DROP TABLE IF EXISTS catalog.bl_mvp_012_probe;");

        await ExpectPermissionDeniedAsync(
            "API no DELETE proyeccion publica",
            "jp_login_api",
            "postgres_api_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");

        await ExpectSuccessAsync(
'@ `
    -AlreadyMarker "API no DELETE proyeccion publica" `
    -Description "prueba negativa API proyeccion publica"

Replace-ExactOnce `
    -RelativePath "tools/DatabaseAccessVerifier/DatabaseAccessChecks.cs" `
    -OldText @'
        await ExpectSuccessAsync(
            "Worker DML ops permitido",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM ops.idempotency_record WHERE false;");

        await ExpectPermissionDeniedAsync(
'@ `
    -NewText @'
        await ExpectSuccessAsync(
            "Worker DML ops permitido",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM ops.idempotency_record WHERE false;");

        await ExpectSuccessAsync(
            "Worker DELETE proyeccion publica reconstruible",
            "jp_login_worker",
            "postgres_worker_password",
            "DELETE FROM editorial.published_package_projection WHERE false;");

        await ExpectPermissionDeniedAsync(
'@ `
    -AlreadyMarker "Worker DELETE proyeccion publica reconstruible" `
    -Description "prueba positiva worker proyeccion publica"

Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify encrypted private object storage
'@ `
    -NewText @'
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

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "Verify eligible and rebuildable public catalog projection" `
    -Description "puerta CI BL-MVP-041"

Assert-InventorySubset -Stage "BL-MVP-041 despues de aplicar"

Write-Host "Validando sintaxis del smoke BL-MVP-041..."
$bash = Resolve-GitBash
& $bash -n "scripts/ci/catalog/verify-public-catalog-projection.sh"
Assert-LastExitCode "bash -n BL-MVP-041"

Write-Host "Ejecutando puerta local completa de calidad..."
& "$RepoRoot/scripts/check-quality.ps1"

Write-Host "Compilando Release para smoke sin rebuild..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "dotnet build Release"

Write-Host "Preparando PostgreSQL local para smoke BL-MVP-041..."
if (-not (Test-Path ".env" -PathType Leaf)) {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env desde .env.example con configuracion no secreta."
}
& "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
& "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
& "$RepoRoot/scripts/database/apply-bootstrap.ps1"
& "$RepoRoot/scripts/database/apply-login-identities.ps1"
& "$RepoRoot/scripts/database/apply-initial-migration.ps1"

$databaseName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$databaseUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
& "$RepoRoot/scripts/database/prepare-database-access.ps1" -Database $databaseName

Write-Host "Verificando minimo privilegio actualizado BL-MVP-041..."
dotnet run `
    --project tools/DatabaseAccessVerifier/MusicaAprender.DatabaseAccessVerifier.csproj `
    --configuration Release `
    --no-build `
    --no-restore `
    -- `
    --host 127.0.0.1 `
    --port 5432 `
    --database $databaseName `
    --secret-directory secrets/local
Assert-LastExitCode "DatabaseAccessVerifier BL-MVP-041"

Write-Host "Ejecutando smoke real de proyeccion publica..."
$previousEnv = @{
    PGHOST = $env:PGHOST
    PGPORT = $env:PGPORT
    PGUSER = $env:PGUSER
    PGPASSWORD = $env:PGPASSWORD
    PGDATABASE = $env:PGDATABASE
    BL041_USE_DOCKER_PSQL = $env:BL041_USE_DOCKER_PSQL
    BL041_SKIP_ACCESS_PREP = $env:BL041_SKIP_ACCESS_PREP
    BL041_API_URL = $env:BL041_API_URL
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = "5432"
    $env:PGUSER = $databaseUser
    $env:PGPASSWORD = "unused-docker-exec"
    $env:PGDATABASE = $databaseName
    $env:BL041_USE_DOCKER_PSQL = "true"
    $env:BL041_SKIP_ACCESS_PREP = "true"
    $env:BL041_API_URL = "https://localhost:5456"

    & $bash "scripts/ci/catalog/verify-public-catalog-projection.sh"
    Assert-LastExitCode "Smoke BL-MVP-041"
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

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check"
Assert-FinalInventory

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status

Write-Host ""
Write-Host "OK: BL-MVP-041 instalado y validado localmente."
Write-Host "Incluye proyeccion publica reconstruible, minimo privilegio y revalidacion canonica al abrir."
Write-Host "No implementa aun busqueda publica, ficha publica ni UI-MVP-017."
Write-Host "No se ejecuto git add, commit ni push."

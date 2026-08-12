[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "f12d5328f53d08dfcfbe2849cbdd224bf11df358"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/PublicCatalog/PublicSongDetailEndpoints.cs",
    "apps/api/Program.cs",
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/public/PublicSongCatalogPage.tsx",
    "apps/web/src/routes/public/PublicSongDetailPage.tsx",
    "apps/web/src/routes/public/public-song-detail.css",
    "docs/engineering/catalog/public-song-detail.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-043.md",
    "README/BL-MVP-043_README.md",
    "scripts/apply-bl-mvp-043.ps1",
    "scripts/ci/catalog/verify-public-catalog-search.sh",
    "scripts/ci/catalog/verify-public-song-detail.sh",
    "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs",
    "src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs",
    "tests/E2ETests/public-catalog-search.spec.ts",
    "tests/E2ETests/public-song-detail.spec.ts"
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

function Replace-LiteralAll {
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
    if (-not $content.Contains($OldText)) {
        throw "No se encontro el texto esperado para $Description en $RelativePath."
    }
    $updated = $content.Replace($OldText, $NewText)
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
        throw "BL-MVP-043 encontro cambios fuera de su inventario: $($outside -join ', ')"
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

Write-Host "BL-MVP-043: ficha publica de cancion, slug legible y revalidacion segura..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"
if ($head -cne $ExpectedBase) {
    throw "BL-MVP-043 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-043 debe ejecutarse desde main; rama actual: '$branch'."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-043 requiere indice sin staging."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

$newFiles = @(
    "apps/api/Endpoints/PublicCatalog/PublicSongDetailEndpoints.cs",
    "apps/web/src/routes/public/PublicSongDetailPage.tsx",
    "apps/web/src/routes/public/public-song-detail.css",
    "docs/engineering/catalog/public-song-detail.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-043.md",
    "README/BL-MVP-043_README.md",
    "scripts/apply-bl-mvp-043.ps1",
    "scripts/ci/catalog/verify-public-song-detail.sh",
    "src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs",
    "tests/E2ETests/public-song-detail.spec.ts"
)
foreach ($required in $newFiles) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta $required. Extraiga nuevamente el paquete BL-MVP-043."
    }
}

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "builder.Services.AddSingleton<PublicCatalogSearchService>();`n" `
    -NewText "builder.Services.AddSingleton<PublicCatalogSearchService>();`nbuilder.Services.AddSingleton<PublicSongDetailService>();`n" `
    -AlreadyMarker "builder.Services.AddSingleton<PublicSongDetailService>();" `
    -Description "servicio ficha publica"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText "app.MapPublicCatalogSearch();`n" `
    -NewText "app.MapPublicCatalogSearch();`napp.MapPublicSongDetail();`n" `
    -AlreadyMarker "app.MapPublicSongDetail();" `
    -Description "endpoint ficha publica"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicArea.tsx" `
    -OldText "import { PublicSongCatalogPage } from './PublicSongCatalogPage';`n" `
    -NewText "import { PublicSongCatalogPage } from './PublicSongCatalogPage';`nimport { PublicSongDetailPage } from './PublicSongDetailPage';`n" `
    -AlreadyMarker "import { PublicSongDetailPage } from './PublicSongDetailPage';" `
    -Description "import UI-MVP-004"

$areaAnchor = @'
  if (match.route.id === 'UI-MVP-002' || match.route.id === 'UI-MVP-003') {
    return <PublicSongCatalogPage routeId={match.route.id} />;
  }
'@
$areaReplacement = @'
  if (match.route.id === 'UI-MVP-002' || match.route.id === 'UI-MVP-003') {
    return <PublicSongCatalogPage routeId={match.route.id} />;
  }

  if (match.route.id === 'UI-MVP-004') {
    return <PublicSongDetailPage slug={match.params.slug ?? ''} />;
  }
'@
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicArea.tsx" `
    -OldText $areaAnchor `
    -NewText $areaReplacement `
    -AlreadyMarker "return <PublicSongDetailPage slug={match.params.slug ?? ''} />;" `
    -Description "UI-MVP-004 funcional"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx" `
    -OldText "import { useEffect, useRef, useState } from 'react';`n" `
    -NewText "import { useEffect, useRef, useState } from 'react';`nimport { AppLink } from '../../app/router/navigation';`n" `
    -AlreadyMarker "import { AppLink } from '../../app/router/navigation';" `
    -Description "navegacion a ficha publica"

$oldSearchType = @'
type PublicCatalogSearchItem = {
  publicationId: string;
  recordingId: string;
  workId: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  artistId: string;
  artistName: string;
  providerCode: string;
  externalRef: string;
  territoryCode: string;
  languageTag: string | null;
  indexedAt: string;
};
'@
$newSearchType = @'
type PublicCatalogSearchItem = {
  slug: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  artistName: string;
  providerCode: string;
  territoryCode: string;
  languageTag: string | null;
  indexedAt: string;
};
'@
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx" `
    -OldText $oldSearchType `
    -NewText $newSearchType `
    -AlreadyMarker "  slug: string;" `
    -Description "contrato publico minimo busqueda"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx" `
    -OldText "            {state.data.items.map((item) => (`n              <li key={item.recordingId}>" `
    -NewText "            {state.data.items.map((item) => (`n              <li key={item.slug}>" `
    -AlreadyMarker "<li key={item.slug}>" `
    -Description "key publica por slug"

$availabilityAnchor = @'
                  <p className="public-catalog__availability">
                    Disponible · {item.territoryCode}
                    {item.languageTag ? ` · ${item.languageTag}` : ''}
                  </p>
'@
$availabilityReplacement = @'
                  <p className="public-catalog__availability">
                    Disponible · {item.territoryCode}
                    {item.languageTag ? ` · ${item.languageTag}` : ''}
                  </p>
                  <AppLink
                    className="public-catalog__open"
                    href={`/canciones/${encodeURIComponent(item.slug)}`}
                  >
                    Abrir ficha de {item.canonicalTitle} · {item.recordingTitle ?? 'Grabación principal'}
                  </AppLink>
'@
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx" `
    -OldText $availabilityAnchor `
    -NewText $availabilityReplacement `
    -AlreadyMarker 'className="public-catalog__open"' `
    -Description "enlace de resultado a UI-MVP-004"

$handoff = @'

          <p className="public-catalog__handoff">
            La apertura de la ficha pública UI-MVP-004 se completa en BL-MVP-043; esta pantalla no
            inventa un slug ni expone identificadores internos.
          </p>
'@
$content = Read-Normalized -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx"
if ($content.Contains($handoff)) {
    Write-Utf8NoBomLf `
        -RelativePath "apps/web/src/routes/public/PublicSongCatalogPage.tsx" `
        -Content $content.Replace($handoff, "`n")
    Write-Host "OK: handoff temporal BL043 retirado."
}
elseif ($content.Contains("La apertura de la ficha pública UI-MVP-004 se completa en BL-MVP-043")) {
    throw "El handoff BL043 existe pero no coincide con el bloque esperado."
}
else {
    Write-Host "OK: handoff temporal BL043 ya estaba retirado."
}

$oldRecord = @'
public sealed record PublicCatalogSearchItem(
    Guid PublicationId,
    Guid RecordingId,
    Guid WorkId,
    string CanonicalTitle,
    string? RecordingTitle,
    Guid ArtistId,
    string ArtistName,
    string ProviderCode,
    string ExternalRef,
    string TerritoryCode,
    string? LanguageTag,
    DateTime IndexedAt);
'@
$newRecord = @'
public sealed record PublicCatalogSearchItem(
    string Slug,
    string CanonicalTitle,
    string? RecordingTitle,
    string ArtistName,
    string ProviderCode,
    string TerritoryCode,
    string? LanguageTag,
    DateTime IndexedAt);
'@
Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText $oldRecord `
    -NewText $newRecord `
    -AlreadyMarker "    string Slug," `
    -Description "DTO publico de busqueda sin UUID"

$slugSqlOld = @'
                    availability.language_tag,
                    document.indexed_at,
                    CASE
'@
$slugSqlNew = @'
                    availability.language_tag,
                    document.indexed_at,
                    substring(
                        md5(recording.recording_id::text || ':public-song-v1')
                        from 1 for 20
                    ) AS slug_key,
                    CASE
'@
Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText $slugSqlOld `
    -NewText $slugSqlNew `
    -AlreadyMarker ") AS slug_key," `
    -Description "clave publica derivada en busqueda"

$selectOld = @'
                language_tag,
                indexed_at,
                match_priority,
'@
$selectNew = @'
                language_tag,
                indexed_at,
                slug_key,
                match_priority,
'@
Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText $selectOld `
    -NewText $selectNew `
    -AlreadyMarker "                slug_key,`n                match_priority," `
    -Description "seleccion slug de busqueda"

$rowsOld = @'
            rows.Add(new SearchRow(
                new PublicCatalogSearchItem(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetGuid(2),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetGuid(5),
                    reader.GetString(6),
                    reader.GetString(7),
                    reader.GetString(8),
                    reader.GetString(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.GetDateTime(11)),
                reader.GetInt32(12),
                reader.GetString(13),
                reader.GetString(14),
                reader.GetString(15)));
'@
$rowsNew = @'
            rows.Add(new SearchRow(
                new PublicCatalogSearchItem(
                    PublicSongSlug.Compose(reader.GetString(3), reader.GetString(12)),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetString(6),
                    reader.GetString(7),
                    reader.GetString(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.GetDateTime(11)),
                reader.GetGuid(1),
                reader.GetInt32(13),
                reader.GetString(14),
                reader.GetString(15),
                reader.GetString(16)));
'@
Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText $rowsOld `
    -NewText $rowsNew `
    -AlreadyMarker "PublicSongSlug.Compose(reader.GetString(3), reader.GetString(12))" `
    -Description "materializacion segura resultado busqueda"

Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText "                last.Item.RecordingId));" `
    -NewText "                last.RecordingId));" `
    -AlreadyMarker "                last.RecordingId));" `
    -Description "cursor conserva UUID solo server-side"

$searchRowOld = @'
    private sealed record SearchRow(
        PublicCatalogSearchItem Item,
        int Priority,
        string Title,
        string Artist,
        string Recording);
'@
$searchRowNew = @'
    private sealed record SearchRow(
        PublicCatalogSearchItem Item,
        Guid RecordingId,
        int Priority,
        string Title,
        string Artist,
        string Recording);
'@
Replace-ExactOnce `
    -RelativePath "src/Modules/Catalog/Infrastructure/Search/PublicCatalogSearchService.cs" `
    -OldText $searchRowOld `
    -NewText $searchRowNew `
    -AlreadyMarker "        Guid RecordingId," `
    -Description "identidad cursor interna"

$firstSmokeOld = 'process.stdout.write(`${item.recordingId}\n${page.nextCursor}\n`);'
$firstSmokeNew = @(
    "if (typeof item.slug !== 'string' || !/-[0-9a-f]{20}$/.test(item.slug)) process.exit(1);"
    "if (Object.keys(item).some((key) => /Id$/.test(key) || key === 'externalRef')) process.exit(1);"
    'process.stdout.write(`${item.slug}\n${page.nextCursor}\n`);'
) -join "`n"
Replace-ExactOnce `
    -RelativePath "scripts/ci/catalog/verify-public-catalog-search.sh" `
    -OldText $firstSmokeOld `
    -NewText $firstSmokeNew `
    -AlreadyMarker "typeof item.slug !== 'string'" `
    -Description "smoke BL042 actualizado al contrato slug"

Replace-ExactOnce `
    -RelativePath "scripts/ci/catalog/verify-public-catalog-search.sh" `
    -OldText 'first_recording="${first_values[0]}"' `
    -NewText 'first_slug="${first_values[0]}"' `
    -AlreadyMarker 'first_slug="${first_values[0]}"' `
    -Description "variable primera pagina slug"

$secondSmokeOld = @'
second_recording="$(
  node - "$second_page" <<'NODE'
const fs = require('node:fs');
const page = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(page.items) || page.items.length !== 1) process.exit(1);
if (page.hasMore || page.nextCursor !== null) process.exit(1);
process.stdout.write(page.items[0].recordingId);
NODE
)"

if [[ "$first_recording" == "$second_recording" ]]; then
  fail_check "La paginacion estable repitio la misma grabacion."
fi
'@
$secondSmokeNew = @'
second_slug="$(
  node - "$second_page" <<'NODE'
const fs = require('node:fs');
const page = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!Array.isArray(page.items) || page.items.length !== 1) process.exit(1);
if (page.hasMore || page.nextCursor !== null) process.exit(1);
const item = page.items[0];
if (typeof item.slug !== 'string') process.exit(1);
if (Object.keys(item).some((key) => /Id$/.test(key) || key === 'externalRef')) process.exit(1);
process.stdout.write(item.slug);
NODE
)"

if [[ "$first_slug" == "$second_slug" ]]; then
  fail_check "La paginacion estable repitio la misma grabacion."
fi
'@
Replace-ExactOnce `
    -RelativePath "scripts/ci/catalog/verify-public-catalog-search.sh" `
    -OldText $secondSmokeOld `
    -NewText $secondSmokeNew `
    -AlreadyMarker 'second_slug="$(' `
    -Description "segunda pagina BL042 usa slug publico"

Replace-LiteralAll `
    -RelativePath "tests/E2ETests/public-catalog-search.spec.ts" `
    -OldText "              publicationId: '11111111-1111-4111-8111-111111111111'," `
    -NewText "              slug: '怪獣-11111111111111111111',`n              publicationId: '11111111-1111-4111-8111-111111111111'," `
    -AlreadyMarker "slug: '怪獣-11111111111111111111'" `
    -Description "fixtures BL042 con slug primera grabacion"

Replace-LiteralAll `
    -RelativePath "tests/E2ETests/public-catalog-search.spec.ts" `
    -OldText "              publicationId: '55555555-5555-4555-8555-555555555555'," `
    -NewText "              slug: '怪獣-55555555555555555555',`n              publicationId: '55555555-5555-4555-8555-555555555555'," `
    -AlreadyMarker "slug: '怪獣-55555555555555555555'" `
    -Description "fixture BL042 con slug segunda grabacion"

$ciAnchor = @'
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
$ciReplacement = @'
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
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText $ciAnchor `
    -NewText $ciReplacement `
    -AlreadyMarker "Verify public song detail by readable slug" `
    -Description "puerta CI BL-MVP-043"

$bash = Resolve-GitBash
Write-Host "Validando sintaxis de smokes BL042/BL043..."
& $bash -n "scripts/ci/catalog/verify-public-catalog-search.sh"
Assert-LastExitCode "bash -n smoke BL042"
& $bash -n "scripts/ci/catalog/verify-public-song-detail.sh"
Assert-LastExitCode "bash -n smoke BL043"

Write-Host "Restaurando dependencias en modo bloqueado..."
dotnet restore MusicaAprender.sln --locked-mode
Assert-LastExitCode "dotnet restore locked BL043"
npm.cmd ci
Assert-LastExitCode "npm ci BL043"

$formatTargets = @(
    "apps/web/src/routes/public/PublicArea.tsx",
    "apps/web/src/routes/public/PublicSongCatalogPage.tsx",
    "apps/web/src/routes/public/PublicSongDetailPage.tsx",
    "apps/web/src/routes/public/public-song-detail.css",
    "tests/E2ETests/public-catalog-search.spec.ts",
    "tests/E2ETests/public-song-detail.spec.ts",
    "README/BL-MVP-043_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F2_BL-MVP-043.md",
    "docs/engineering/catalog/public-song-detail.md"
)
npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL043"

dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "dotnet format BL043"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes de Playwright focal..."
npm.cmd run build
Assert-LastExitCode "Build frontend BL043"

Write-Host "Ejecutando Playwright focal BL042/BL043..."
npm.cmd run test:e2e -- tests/E2ETests/public-catalog-search.spec.ts tests/E2ETests/public-song-detail.spec.ts
Assert-LastExitCode "Playwright focal BL043"

if (-not $SkipQualityGate) {
    Write-Host "Ejecutando puerta local completa de calidad..."
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para smoke..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL043"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-043..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = Get-DotEnvValue "POSTGRES_DB" "musica_aprender"
    $databaseUser = Get-DotEnvValue "POSTGRES_USER" "musica_local"
    & "$RepoRoot/scripts/database/prepare-database-access.ps1" -Database $database

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL043_USE_DOCKER_PSQL = $env:BL043_USE_DOCKER_PSQL
        BL043_SKIP_ACCESS_PREP = $env:BL043_SKIP_ACCESS_PREP
        BL043_API_URL = $env:BL043_API_URL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL043_USE_DOCKER_PSQL = "true"
        $env:BL043_SKIP_ACCESS_PREP = "true"
        $env:BL043_API_URL = "https://localhost:5458"

        Write-Host "Ejecutando smoke real de ficha publica..."
        & $bash "scripts/ci/catalog/verify-public-song-detail.sh"
        Assert-LastExitCode "Smoke BL-MVP-043"
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
Assert-LastExitCode "git diff --check BL043"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)
if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-043 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}
for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-043 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 17 rutas BL-MVP-043."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-043 instalado y validado localmente."
Write-Host "Incluye UI-MVP-004, slug legible, contrato publico minimo y revalidacion al abrir."
Write-Host "PENDIENTE: reinicio normal y revision visual de /canciones y /canciones/{slug} antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

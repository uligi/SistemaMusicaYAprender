[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "c21dd7b6688e60390d437f91695dda6a32639645"
$ExpectedPrettier = "3.9.6"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    $gitCommand = Get-Command "git.exe" -ErrorAction Stop
    $gitDirectory = Split-Path -Parent $gitCommand.Source

    foreach ($candidate in @(
        (Join-Path $gitDirectory "..\bin\bash.exe"),
        (Join-Path $gitDirectory "..\usr\bin\bash.exe")
    )) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Git Bash no esta disponible junto a git.exe."
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
        Where-Object {
            $_ -match "^\s*$([regex]::Escape($Name))\s*="
        } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

function Normalize-LineEndings {
    param([Parameter(Mandatory = $true)][string]$Text)

    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Read-Utf8 {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $fullPath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) {
        throw "No se encontro $RelativePath."
    }

    $content = [System.IO.File]::ReadAllText(
        $fullPath,
        [System.Text.Encoding]::UTF8)

    return Normalize-LineEndings -Text $content
}

function Write-Utf8 {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $normalized = Normalize-LineEndings -Text $Content

    [System.IO.File]::WriteAllText(
        (Join-Path $RepoRoot $RelativePath),
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

    $content = Read-Utf8 $RelativePath
    $oldNormalized = Normalize-LineEndings -Text $OldText
    $newNormalized = Normalize-LineEndings -Text $NewText
    $alreadyNormalized = Normalize-LineEndings -Text $AlreadyMarker

    if ($content.Contains($alreadyNormalized)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf(
        $oldNormalized,
        [System.StringComparison]::Ordinal)

    if ($first -lt 0) {
        throw "No se encontro el marcador esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $oldNormalized,
        $first + $oldNormalized.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "El marcador de $Description aparece mas de una vez en $RelativePath."
    }

    $updated =
        $content.Substring(0, $first) +
        $newNormalized +
        $content.Substring($first + $oldNormalized.Length)

    Write-Utf8 $RelativePath $updated
    Write-Host "OK: $Description aplicado."
}

function Add-AfterExactOnce {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Anchor,
        [Parameter(Mandatory = $true)][string]$Addition,
        [Parameter(Mandatory = $true)][string]$AlreadyMarker,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $content = Read-Utf8 $RelativePath
    $anchorNormalized = Normalize-LineEndings -Text $Anchor
    $additionNormalized = Normalize-LineEndings -Text $Addition
    $alreadyNormalized = Normalize-LineEndings -Text $AlreadyMarker

    if ($content.Contains($alreadyNormalized)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf(
        $anchorNormalized,
        [System.StringComparison]::Ordinal)

    if ($first -lt 0) {
        throw "No se encontro el ancla de $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $anchorNormalized,
        $first + $anchorNormalized.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "El ancla de $Description aparece mas de una vez en $RelativePath."
    }

    $updated = $content.Insert(
        $first + $anchorNormalized.Length,
        $additionNormalized)

    Write-Utf8 $RelativePath $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $staged = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"

    if ($staged.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $tracked = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"

    if ($tracked.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de tsconfig.app.tsbuildinfo"

    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Get-StatusPath {
    param([Parameter(Mandatory = $true)][string]$StatusLine)

    if ($StatusLine.Length -lt 4) {
        return ""
    }

    $raw = $StatusLine.Substring(3).Trim()

    if ($raw.Contains(" -> ")) {
        $raw = ($raw -split " -> ", 2)[1]
    }

    if ($raw.StartsWith('"') -and $raw.EndsWith('"')) {
        $raw = $raw.Substring(1, $raw.Length - 2)
    }

    return $raw.Replace("\", "/")
}

function Get-CurrentStatusEntries {
    $entries = @(
        git status --porcelain=v1 --untracked-files=all |
            ForEach-Object {
                $path = Get-StatusPath -StatusLine $_
                if ($path) {
                    [PSCustomObject]@{
                        Path = $path
                        Raw = "$_"
                    }
                }
            }
    )
    Assert-LastExitCode "Inventario Git"
    return $entries
}

function Assert-OnlyExpectedPaths {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$Allowed,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$Baseline,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $unexpected = @(
        Get-CurrentStatusEntries |
            Where-Object {
                -not $Allowed.Contains($_.Path) -and
                -not $Baseline.Contains($_.Path)
            } |
            ForEach-Object {
                $_.Raw
            }
    )

    if ($unexpected.Count -gt 0) {
        throw "Inventario inesperado durante ${Phase}:`n$($unexpected -join "`n")"
    }
}

Write-Host "BL-MVP-032: MFA TOTP y reautenticacion para acciones privilegiadas..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"

if ($currentBranch -ne "main") {
    throw "BL-MVP-032 debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"

if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$packagePaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
@(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-032.md",
    "README/BL-MVP-032_README.md",
    "apps/api/Endpoints/Security/PrivilegedMfaEndpoints.cs",
    "apps/api/Security/PrivilegedAssuranceEndpointFilter.cs",
    "apps/web/src/routes/administration/PrivilegedAssurancePanel.tsx",
    "docs/engineering/security/privileged-mfa.md",
    "scripts/apply-bl-mvp-032.ps1",
    "scripts/ci/security/verify-privileged-mfa.sh",
    "src/Modules/Security/Infrastructure/Mfa/MfaSecretReferenceCodec.cs",
    "src/Modules/Security/Infrastructure/Mfa/PrivilegedMfaService.cs",
    "src/Modules/Security/Infrastructure/Mfa/TotpService.cs",
    "src/BuildingBlocks/Infrastructure/ObjectStorage/MinioPrivateObjectStore.cs",
    "tools/ObjectStoreVerifier/ObjectStoreChecks.cs",
    "tests/E2ETests/privileged-mfa.spec.ts",
    "tests/UnitTests/Modules/Security/TotpServiceTests.cs"
) | ForEach-Object {
    [void]$packagePaths.Add($_)
}

@(
    ".github/workflows/ci.yml",
    "apps/api/Program.cs",
    "apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs",
    "apps/web/src/routes/administration/RoleManagementPage.tsx",
    "apps/web/src/routes/administration/role-management.css",
    "database/postgresql/security/02_database_access.sql",
    "scripts/ci/security/verify-role-assignments.sh",
    "tests/E2ETests/role-management.spec.ts"
) | ForEach-Object {
    [void]$packagePaths.Add($_)
}

$baselinePaths =
    [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)

foreach ($entry in Get-CurrentStatusEntries) {
    if (-not $packagePaths.Contains($entry.Path)) {
        [void]$baselinePaths.Add($entry.Path)
    }
}

if ($baselinePaths.Count -gt 0) {
    Write-Host "INFO: se preservaran $($baselinePaths.Count) rutas preexistentes fuera de BL-MVP-032."
}

Assert-OnlyExpectedPaths `
    -Allowed $packagePaths `
    -Baseline $baselinePaths `
    -Phase "previo a aplicar BL-MVP-032"

# Program.cs
Add-AfterExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -Anchor "using MusicaAprender.Modules.Security.Infrastructure.Credentials;`n" `
    -Addition "using MusicaAprender.Modules.Security.Infrastructure.Mfa;`n" `
    -AlreadyMarker "using MusicaAprender.Modules.Security.Infrastructure.Mfa;" `
    -Description "namespace MFA en API"

Add-AfterExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -Anchor "builder.Services.AddSingleton<RoleAssignmentAdministrationService>();`n" `
    -Addition "builder.Services.AddSingleton<PrivilegedMfaService>();`n" `
    -AlreadyMarker "builder.Services.AddSingleton<PrivilegedMfaService>();" `
    -Description "servicio MFA"

Add-AfterExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -Anchor "app.MapRoleAssignments();`n" `
    -Addition "app.MapPrivilegedMfa();`n" `
    -AlreadyMarker "app.MapPrivilegedMfa();" `
    -Description "endpoints MFA"

# BL-MVP-032O: MinIO 7.0.0 expone un callback async real de dos parametros
# (Stream, CancellationToken). El overload de un parametro es Action<Stream>;
# una lambda `async source =>` termina siendo async void y GetObjectAsync puede
# regresar antes de que termine la copia. MFA requiere lecturas repetidas fiables.
Replace-ExactOnce `
    -RelativePath "src/BuildingBlocks/Infrastructure/ObjectStorage/MinioPrivateObjectStore.cs" `
    -OldText @'
                .WithCallbackStream(
                    async source =>
                    {
                        await using var file = new FileStream(
                            encryptedPath,
                            FileMode.CreateNew,
                            FileAccess.Write,
                            FileShare.None,
                            81920,
                            FileOptions.Asynchronous | FileOptions.SequentialScan);

                        await source.CopyToAsync(file, cancellationToken);
                        await file.FlushAsync(cancellationToken);
                    });
'@ `
    -NewText @'
                .WithCallbackStream(
                    async (source, callbackToken) =>
                    {
                        await using var file = new FileStream(
                            encryptedPath,
                            FileMode.CreateNew,
                            FileAccess.Write,
                            FileShare.None,
                            81920,
                            FileOptions.Asynchronous | FileOptions.SequentialScan);

                        await source.CopyToAsync(file, callbackToken);
                        await file.FlushAsync(callbackToken);
                    });
'@ `
    -AlreadyMarker "async (source, callbackToken) =>" `
    -Description "callback MinIO awaitable para lecturas privadas repetidas"

Replace-ExactOnce `
    -RelativePath "tools/ObjectStoreVerifier/ObjectStoreChecks.cs" `
    -OldText @'
        var args = new GetObjectArgs()
            .WithBucket(options.Bucket)
            .WithObject(descriptor.StorageKey)
            .WithCallbackStream(
                stream => stream.CopyToAsync(raw));
'@ `
    -NewText @'
        var args = new GetObjectArgs()
            .WithBucket(options.Bucket)
            .WithObject(descriptor.StorageKey)
            .WithCallbackStream(
                (stream, cancellationToken) =>
                    stream.CopyToAsync(raw, cancellationToken));
'@ `
    -AlreadyMarker "(stream, cancellationToken) =>" `
    -Description "verificador MinIO usa callback awaitable"

Replace-ExactOnce `
    -RelativePath "tools/ObjectStoreVerifier/ObjectStoreChecks.cs" `
    -OldText @'
    private static async Task VerifyAuthorizedRoundTripAsync(
        MinioPrivateObjectStore objectStore,
        StoredObjectDescriptor descriptor,
        byte[] plaintext)
    {
        await using var destination = new MemoryStream();

        await objectStore.ReadAsync(
            descriptor,
            new ObjectStoreAccessContext(
                OwnerModule,
                PurposeCode),
            destination);

        var restored = destination.ToArray();

        if (!restored.AsSpan().SequenceEqual(plaintext))
        {
            throw new InvalidOperationException(
                "El round-trip autorizado no devolvio exactamente el plaintext original.");
        }

        CryptographicOperations.ZeroMemory(restored);
    }
'@ `
    -NewText @'
    private static async Task VerifyAuthorizedRoundTripAsync(
        MinioPrivateObjectStore objectStore,
        StoredObjectDescriptor descriptor,
        byte[] plaintext)
    {
        for (var attempt = 1; attempt <= 2; attempt++)
        {
            await using var destination = new MemoryStream();

            await objectStore.ReadAsync(
                descriptor,
                new ObjectStoreAccessContext(
                    OwnerModule,
                    PurposeCode),
                destination);

            var restored = destination.ToArray();

            try
            {
                if (!restored.AsSpan().SequenceEqual(plaintext))
                {
                    throw new InvalidOperationException(
                        $"La lectura autorizada repetida {attempt} no devolvio exactamente el plaintext original.");
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(restored);
            }
        }
    }
'@ `
    -AlreadyMarker "for (var attempt = 1; attempt <= 2; attempt++)" `
    -Description "verificador exige dos lecturas privadas consecutivas"

# Las cuatro operaciones de roles requieren permiso efectivo + assurance reciente.
$roleEndpointPath =
    "apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs"
$roleEndpointContent = Read-Utf8 $roleEndpointPath
$assuranceMarker = ".RequireRecentPrivilegedAssurance()"

if (-not $roleEndpointContent.Contains($assuranceMarker)) {
    $permissionNeedle =
        '.RequireEffectivePermission("SECURITY.MANAGE_ROLES")'

    $count = [regex]::Matches(
        $roleEndpointContent,
        [regex]::Escape($permissionNeedle)).Count

    if ($count -ne 4) {
        throw "Se esperaban 4 puertas SECURITY.MANAGE_ROLES y se encontraron $count."
    }

    $roleEndpointContent = $roleEndpointContent.Replace(
        $permissionNeedle,
        $permissionNeedle +
            "`n            .RequireRecentPrivilegedAssurance()")

    Write-Utf8 $roleEndpointPath $roleEndpointContent
    Write-Host "OK: las 4 operaciones de roles exigen step-up reciente."
}
else {
    Write-Host "OK: step-up de roles ya estaba aplicado."
}

# Acceso DB: MFA puede resolver la misma sesión y solo el dueño puede DML su factor.
Replace-ExactOnce `
    -RelativePath "database/postgresql/security/02_database_access.sql" `
    -OldText "                  AND session.assurance_level = 'PASSWORD'`n" `
    -NewText "                  AND session.assurance_level IN ('PASSWORD', 'MFA')`n" `
    -AlreadyMarker "session.assurance_level IN ('PASSWORD', 'MFA')" `
    -Description "resolucion de sesion PASSWORD/MFA"

$dbAccessMarker = @'
-- EF Core mantiene __EFMigrationsHistory en public.
'@

$dbAccessAddition = @'

-- BL-MVP-032. El runtime administra solamente su propio método MFA.
-- security.mfa_method conserva RLS forzado por account_id.
DO $mfa_runtime_access$
BEGIN
    IF to_regclass('security.mfa_method') IS NOT NULL THEN
        GRANT SELECT, INSERT, UPDATE
            ON TABLE security.mfa_method
            TO jp_app;
    END IF;
END;
$mfa_runtime_access$;

'@

$databaseAccess = Read-Utf8 "database/postgresql/security/02_database_access.sql"
$dbAccessMarker = Normalize-LineEndings -Text $dbAccessMarker
$dbAccessAddition = Normalize-LineEndings -Text $dbAccessAddition

if (-not $databaseAccess.Contains("mfa_runtime_access")) {
    $index = $databaseAccess.IndexOf(
        $dbAccessMarker,
        [System.StringComparison]::Ordinal)

    if ($index -lt 0) {
        throw "No se encontro el marcador EF Core para insertar acceso MFA."
    }

    $databaseAccess = $databaseAccess.Insert(
        $index,
        $dbAccessAddition)

    Write-Utf8 `
        "database/postgresql/security/02_database_access.sql" `
        $databaseAccess
    Write-Host "OK: grant MFA acotado por RLS agregado."
}
else {
    Write-Host "OK: grant MFA acotado por RLS ya estaba aplicado."
}

# UI-MVP-029: panel de assurance y ocultamiento del formulario hasta step-up.
Add-AfterExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -Anchor "import { createHttpClient } from '../../data/http';`n" `
    -Addition "import { PrivilegedAssurancePanel } from './PrivilegedAssurancePanel';`n" `
    -AlreadyMarker "import { PrivilegedAssurancePanel }" `
    -Description "panel MFA importado"

Add-AfterExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -Anchor "  const [busy, setBusy] = useState(false);`n" `
    -Addition "  const [privilegedReady, setPrivilegedReady] = useState(false);`n" `
    -AlreadyMarker "setPrivilegedReady" `
    -Description "estado de assurance en UI"

$catalogEffectOld = @'
  useEffect(() => {
    let active = true;

    void (async () => {
'@

$catalogEffectNew = @'
  useEffect(() => {
    if (!privilegedReady) {
      setCatalog(null);
      return;
    }

    let active = true;

    void (async () => {
'@

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -OldText $catalogEffectOld `
    -NewText $catalogEffectNew `
    -AlreadyMarker "if (!privilegedReady)" `
    -Description "catalogo condicionado a step-up"

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -OldText "  }, []);`n`n  const targetValid" `
    -NewText "  }, [privilegedReady]);`n`n  const targetValid" `
    -AlreadyMarker "}, [privilegedReady]);" `
    -Description "dependencia de assurance del catalogo"

Add-AfterExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -Anchor "      </header>`n`n" `
    -Addition "      <PrivilegedAssurancePanel onReadyChange={setPrivilegedReady} />`n`n" `
    -AlreadyMarker "<PrivilegedAssurancePanel" `
    -Description "panel MFA visible en UI-029"

$privilegedGridOpen = @'
      {privilegedReady ? (
        <div className="role-management__grid">
'@

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -OldText '      <div className="role-management__grid">' `
    -NewText $privilegedGridOpen `
    -AlreadyMarker "{privilegedReady ? (" `
    -Description "apertura de contenido privilegiado"

$privilegedGridClose = @'
        </div>
      ) : (
        <p className="role-management__locked">
          Confirma la verificación reforzada para consultar o modificar asignaciones.
        </p>
      )}
    </section>
'@

Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/administration/RoleManagementPage.tsx" `
    -OldText "      </div>`n    </section>`n" `
    -NewText $privilegedGridClose `
    -AlreadyMarker 'className="role-management__locked"' `
    -Description "cierre de contenido privilegiado"

# Estilos usando tokens de diseño existentes.
$cssPath =
    "apps/web/src/routes/administration/role-management.css"
$cssContent = Read-Utf8 $cssPath

if (-not $cssContent.Contains(".role-management__assurance {")) {
    $cssContent += @'

.role-management__assurance {
  display: grid;
  gap: var(--ma-space-4);
  max-width: 52rem;
  padding: var(--ma-space-5);
  border: var(--ma-border-width-thin) solid var(--ma-color-border);
  border-radius: var(--ma-radius-panel);
  background: var(--ma-color-surface);
}

.role-management__assurance h2,
.role-management__assurance p,
.role-management__locked {
  margin: 0;
}

.role-management__assurance-form {
  display: grid;
  gap: var(--ma-space-3);
  max-width: 36rem;
}

.role-management__assurance-ok {
  font-weight: var(--ma-font-weight-semibold);
}

.role-management__totp-secret {
  overflow-wrap: anywhere;
  user-select: all;
}

.role-management__locked {
  max-width: 52rem;
  padding: var(--ma-space-4);
  border: var(--ma-border-width-thin) solid var(--ma-color-border);
  border-radius: var(--ma-radius-control);
  color: var(--ma-color-muted);
  background: var(--ma-color-surface);
}
'@

    Write-Utf8 $cssPath $cssContent
    Write-Host "OK: estilos MFA agregados con tokens versionados."
}
else {
    Write-Host "OK: estilos MFA ya estaban aplicados."
}

# La regresión UI de BL031 recibe assurance vigente del servidor simulado.
$roleSpecPath = "tests/E2ETests/role-management.spec.ts"
$roleSpec = Read-Utf8 $roleSpecPath

if (-not $roleSpec.Contains("**/api/v1/security/mfa/status")) {
    $anchor =
        "    await page.route('**/api/v1/auth/csrf', async (route) => {`n"

    $index = $roleSpec.IndexOf(
        $anchor,
        [System.StringComparison]::Ordinal)

    if ($index -lt 0) {
        throw "No se encontro el ancla CSRF en role-management.spec.ts."
    }

    $addition = @'
    await page.route('**/api/v1/security/mfa/status', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          enrolled: true,
          recentAssurance: true,
          methodType: 'TOTP',
          assuranceExpiresAt: '2099-08-11T15:00:00Z',
        }),
      });
    });

'@

    $roleSpec = $roleSpec.Insert(
        $index,
        $addition)

    Write-Utf8 $roleSpecPath $roleSpec
    Write-Host "OK: E2E BL031 conoce assurance vigente."
}
else {
    Write-Host "OK: E2E BL031 ya conoce assurance vigente."
}

# El smoke cerrado de BL031 conserva su propósito: DBA prepara solo el
# prerequisito MFA sintético y las reglas de asignación siguen pasando por API.
$bl031SmokePath =
    "scripts/ci/security/verify-role-assignments.sh"
$bl031Smoke = Read-Utf8 $bl031SmokePath

if (-not $bl031Smoke.Contains("BL-MVP-032 prerequisito MFA sintetico")) {
    $anchor = "refresh_authenticated_csrf() {"

    $index = $bl031Smoke.IndexOf(
        $anchor,
        [System.StringComparison]::Ordinal)

    if ($index -lt 0) {
        throw "No se encontro la funcion refresh_authenticated_csrf en el smoke BL031."
    }

    $addition = @'
# BL-MVP-032 prerequisito MFA sintetico.
# El smoke BL031 sigue probando exclusivamente administración de roles.
session_id="$(
  "${psql_base[@]}" --command="
SELECT session_id
FROM security.session
WHERE account_id = '$admin_account_id'::uuid
  AND revoked_at IS NULL
ORDER BY created_at DESC
LIMIT 1;
" | tr -d '[:space:]'
)"

[[ "$session_id" =~ ^[0-9a-f-]{36}$ ]] \
  || fail_check "No se resolvió la sesión sintética para assurance."

session_key="${session_id//-/}"

"${psql_base[@]}" --command="
INSERT INTO security.mfa_method (
    account_id,
    method_type,
    secret_ref,
    enrolled_at,
    disabled_at
)
VALUES (
    '$admin_account_id'::uuid,
    'TOTP',
    'BL031-SYNTHETIC-MFA-NOT-USED',
    CURRENT_TIMESTAMP,
    NULL
);

UPDATE security.session
SET
    assurance_level = 'MFA',
    idle_expires_at = LEAST(
        idle_expires_at,
        CURRENT_TIMESTAMP + INTERVAL '15 minutes',
        absolute_expires_at,
        created_at + INTERVAL '8 hours'
    ),
    absolute_expires_at = LEAST(
        absolute_expires_at,
        created_at + INTERVAL '8 hours'
    )
WHERE session_id = '$session_id'::uuid
  AND account_id = '$admin_account_id'::uuid;

INSERT INTO ops.idempotency_record (
    account_id,
    operation_code,
    idempotency_key,
    request_digest,
    response_code,
    response_ref,
    created_at,
    expires_at
)
VALUES (
    '$admin_account_id'::uuid,
    'SECURITY.MFA.ASSURANCE',
    '$session_key',
    decode(repeat('a1', 32), 'hex'),
    200,
    jsonb_build_object(
        'assurance', 'MFA',
        'purpose', 'PRIVILEGED',
        'source', 'BL031-regression'
    ),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '15 minutes'
)
ON CONFLICT (
    account_id,
    operation_code,
    idempotency_key
)
DO UPDATE SET
    response_code = 200,
    response_ref = EXCLUDED.response_ref,
    created_at = CURRENT_TIMESTAMP,
    expires_at = CURRENT_TIMESTAMP + INTERVAL '15 minutes';
" >/dev/null

'@

    $bl031Smoke = $bl031Smoke.Insert(
        $index,
        $addition + "`n")

    Write-Utf8 $bl031SmokePath $bl031Smoke
    Write-Host "OK: regresion BL031 recibe prerequisito MFA sintetico."
}
else {
    Write-Host "OK: prerequisito MFA del smoke BL031 ya estaba aplicado."
}

# CI: MinIO debe existir antes de BL032 y el smoke corre después de BL031.
$ciPath = ".github/workflows/ci.yml"
$ci = Read-Utf8 $ciPath

if (-not $ci.Contains("Verify privileged MFA and recent reauthentication")) {
    $oldBlock = @'
      - name: Verify audited role assignment administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL031_USE_DOCKER_PSQL: 'false'
          BL031_API_URL: https://localhost:5447
        run: bash scripts/ci/security/verify-role-assignments.sh

      - name: Start private development object store
        shell: bash
        run: |
          docker compose up --detach object-store
          for attempt in $(seq 1 30); do
            if curl --fail --silent http://127.0.0.1:9000/minio/health/ready >/dev/null; then
              exit 0
            fi
            sleep 1
          done
          docker compose logs object-store
          exit 1

      - name: Verify encrypted private object storage
'@

    $newBlock = @'
      - name: Start private development object store
        shell: bash
        run: |
          docker compose up --detach object-store
          for attempt in $(seq 1 30); do
            if curl --fail --silent http://127.0.0.1:9000/minio/health/ready >/dev/null; then
              exit 0
            fi
            sleep 1
          done
          docker compose logs object-store
          exit 1

      - name: Verify audited role assignment administration
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL031_USE_DOCKER_PSQL: 'false'
          BL031_API_URL: https://localhost:5447
        run: bash scripts/ci/security/verify-role-assignments.sh

      - name: Verify privileged MFA and recent reauthentication
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL032_USE_DOCKER_PSQL: 'false'
          BL032_API_URL: https://localhost:5448
        run: bash scripts/ci/security/verify-privileged-mfa.sh

      - name: Verify encrypted private object storage
'@

    $oldBlock = Normalize-LineEndings -Text $oldBlock
    $newBlock = Normalize-LineEndings -Text $newBlock

    $first = $ci.IndexOf(
        $oldBlock,
        [System.StringComparison]::Ordinal)

    if ($first -lt 0) {
        throw "No se encontro la secuencia CI BL031/MinIO esperada."
    }

    $second = $ci.IndexOf(
        $oldBlock,
        $first + $oldBlock.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "La secuencia CI BL031/MinIO aparece mas de una vez."
    }

    $ci =
        $ci.Substring(0, $first) +
        $newBlock +
        $ci.Substring($first + $oldBlock.Length)

    Write-Utf8 $ciPath $ci
    Write-Host "OK: CI ejecuta MinIO antes de BL031/032 y agrega smoke MFA."
}
else {
    Write-Host "OK: CI BL032 ya estaba aplicado."
}

& "$PSScriptRoot/check-toolchain.ps1"
& "$PSScriptRoot/local/ensure-local-secrets.ps1"

$objectStoreSecret = Join-Path `
    $RepoRoot `
    "secrets\local\object_store_encryption_key"
if (-not (Test-Path $objectStoreSecret -PathType Leaf)) {
    throw "Falta secrets/local/object_store_encryption_key."
}

npm.cmd ci
Assert-LastExitCode "npm ci BL-MVP-032"

$prettier = Join-Path `
    $RepoRoot `
    "node_modules\.bin\prettier.cmd"

$prettierVersion = (& $prettier --version).Trim()
Assert-LastExitCode "Consulta de version Prettier"

if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Prettier inesperado. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

$formatTargets = @(
    "apps/web/src/routes/administration/RoleManagementPage.tsx",
    "apps/web/src/routes/administration/PrivilegedAssurancePanel.tsx",
    "apps/web/src/routes/administration/role-management.css",
    "tests/E2ETests/role-management.spec.ts",
    "tests/E2ETests/privileged-mfa.spec.ts",
    "docs/engineering/security/privileged-mfa.md",
    "README/BL-MVP-032_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-032.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-032"

& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-032"
Write-Host "OK: archivos web/documentales BL-MVP-032 formateados."

$bashPath = Resolve-GitBash

& $bashPath -n "./scripts/ci/security/verify-role-assignments.sh"
Assert-LastExitCode "Sintaxis smoke BL-MVP-031"

& $bashPath -n "./scripts/ci/security/verify-privileged-mfa.sh"
Assert-LastExitCode "Sintaxis smoke BL-MVP-032"
Write-Host "OK: sintaxis bash BL031/BL032 aprobada."

npm.cmd run test:e2e:install
Assert-LastExitCode "Instalacion Chromium Playwright BL-MVP-032"

Write-Host "Ejecutando la puerta local completa de calidad..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host "Iniciando el entorno local reproducible..."
& "$PSScriptRoot/local/start.ps1"
& "$PSScriptRoot/local/verify-running.ps1"

$dbUser = Get-DotEnvValue `
    -Name "POSTGRES_USER" `
    -DefaultValue "musica_local"
$dbName = Get-DotEnvValue `
    -Name "POSTGRES_DB" `
    -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue `
    -Name "POSTGRES_PORT" `
    -DefaultValue "5432"
$webPort = Get-DotEnvValue `
    -Name "WEB_PORT" `
    -DefaultValue "5173"

$passwordPath = Join-Path `
    $RepoRoot `
    "secrets\local\postgres_password"
if (-not (Test-Path $passwordPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

$environmentNames = @(
    "PGHOST",
    "PGPORT",
    "PGUSER",
    "PGDATABASE",
    "PGPASSWORD",
    "BL030_USE_RUNNING_API",
    "BL030_USE_DOCKER_PSQL",
    "BL030_API_URL",
    "BL031_USE_RUNNING_API",
    "BL031_USE_DOCKER_PSQL",
    "BL031_API_URL",
    "BL032_USE_RUNNING_API",
    "BL032_USE_DOCKER_PSQL",
    "BL032_API_URL"
)

$previous = @{}
foreach ($name in $environmentNames) {
    $previous[$name] =
        [Environment]::GetEnvironmentVariable(
            $name,
            "Process")
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = $dbPort
    $env:PGUSER = $dbUser
    $env:PGDATABASE = $dbName
    $env:PGPASSWORD =
        [System.IO.File]::ReadAllText(
            $passwordPath).Trim()

    $env:BL030_USE_RUNNING_API = "true"
    $env:BL030_USE_DOCKER_PSQL = "true"
    $env:BL030_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-effective-authorization.sh"
    Assert-LastExitCode "Regresion BL-MVP-030"

    $env:BL031_USE_RUNNING_API = "true"
    $env:BL031_USE_DOCKER_PSQL = "true"
    $env:BL031_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-role-assignments.sh"
    Assert-LastExitCode "Regresion BL-MVP-031"

    $env:BL032_USE_RUNNING_API = "true"
    $env:BL032_USE_DOCKER_PSQL = "true"
    $env:BL032_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-privileged-mfa.sh"
    Assert-LastExitCode "Smoke BL-MVP-032"
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            "Process")
    }
}

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check BL-MVP-032"

$finalAllowed =
    [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)

foreach ($path in $packagePaths) {
    [void]$finalAllowed.Add($path)
}

@(
    ".github/workflows/ci.yml",
    "apps/api/Program.cs",
    "apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs",
    "apps/web/src/routes/administration/RoleManagementPage.tsx",
    "apps/web/src/routes/administration/role-management.css",
    "database/postgresql/security/02_database_access.sql",
    "scripts/ci/security/verify-role-assignments.sh",
    "tests/E2ETests/role-management.spec.ts"
) | ForEach-Object {
    [void]$finalAllowed.Add($_)
}

Assert-OnlyExpectedPaths `
    -Allowed $finalAllowed `
    -Baseline $baselinePaths `
    -Phase "inventario final BL-MVP-032"

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-only
Write-Host ""

Write-Host "OK: BL-MVP-032 instalado y validado localmente con MFA TOTP y step-up privilegiado."
Write-Host "No se ejecuto git add, commit ni push."

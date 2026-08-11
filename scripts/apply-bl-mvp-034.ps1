[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "8d143e2cb10b89537fb8be2763decc609237ea16"
$ExpectedDotNet = "9.0.314"
$ExpectedNode = "v24.18.0"
$ExpectedNpm = "11.16.0"
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
    $content = $content.Replace("`r`n", "`n")
    return $content.Replace("`r", "`n")
}

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $path = Join-Path $RepoRoot $RelativePath
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
    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta de indice TypeScript"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento TypeScript"
    if ($trackedPaths.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de salida incremental TypeScript"
    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion TypeScript incremental"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
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
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

Write-Host "BL-MVP-034: perfil basico y preferencias iniciales seguras..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-034 debe ejecutarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

Restore-GeneratedTypeScriptState

git diff --quiet
Assert-LastExitCode "Comprobacion de working tree tracked limpio"

$requiredNew = @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-034.md",
    "README/BL-MVP-034_README.md",
    "apps/api/Endpoints/Identity/PersonalPreferencesEndpoints.cs",
    "apps/web/src/routes/student/PersonalPreferencesPage.tsx",
    "apps/web/src/routes/student/student-area.css",
    "docs/engineering/identity/personal-preferences.md",
    "scripts/apply-bl-mvp-034.ps1",
    "scripts/ci/identity/verify-personal-preferences.sh",
    "src/Modules/Identity/Application/Preferences/PersonalPreferencePolicy.cs",
    "src/Modules/Identity/Infrastructure/Preferences/PersonalPreferenceService.cs",
    "tests/E2ETests/personal-preferences.spec.ts",
    "tests/UnitTests/Modules/Identity/PersonalPreferencePolicyTests.cs"
)

foreach ($path in $requiredNew) {
    if (-not (Test-Path (Join-Path $RepoRoot $path) -PathType Leaf)) {
        throw "Paquete incompleto: falta $path."
    }
}

# BL030 elimina roles del ticket; el contexto RLS no debe confundir ausencia de claim con ausencia de sesión.
Replace-ExactOnce `
    -RelativePath "apps/api/Security/HttpDatabaseSessionContextFactory.cs" `
    -OldText @'
using System.Security.Claims;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
'@ `
    -NewText @'
using System.Security.Claims;
using MusicaAprender.BuildingBlocks.Infrastructure.Database;
using MusicaAprender.Modules.Security.Infrastructure.Authentication;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Security.Infrastructure.Authentication;" `
    -Description "SafeRoleCode para contexto RLS autenticado"

Replace-ExactOnce `
    -RelativePath "apps/api/Security/HttpDatabaseSessionContextFactory.cs" `
    -OldText @'
        else
        {
            var fallbackRoles = ReadDistinctClaims(
                httpContext.User,
                ClaimTypes.Role,
                RoleClaim);

            if (fallbackRoles.Count != 1)
            {
                throw new InvalidOperationException(
                    "La identidad autenticada debe resolver exactamente un rol activo.");
            }

            roleCode = fallbackRoles[0];
        }
'@ `
    -NewText @'
        else
        {
            var fallbackRoles = ReadDistinctClaims(
                httpContext.User,
                ClaimTypes.Role,
                RoleClaim);

            if (fallbackRoles.Count > 1)
            {
                throw new InvalidOperationException(
                    "La identidad autenticada contiene mas de un rol de respaldo.");
            }

            // BL-MVP-030: el ticket de sesión prueba identidad, no autoridad,
            // y por diseño no reconstruye claims de rol. SafeRoleCode solo
            // etiqueta el contexto RLS; permisos/roles efectivos se recalculan
            // por operación contra PostgreSQL.
            roleCode = fallbackRoles.Count == 1
                ? fallbackRoles[0]
                : SecuritySessionPolicy.SafeRoleCode;
        }
'@ `
    -AlreadyMarker "SafeRoleCode solo" `
    -Description "fallback no autoritativo del contexto RLS"

# UnitTests: BL034 prueba reglas pertenecientes a M01 Identity.
Replace-ExactOnce `
    -RelativePath "tests/UnitTests/MusicaAprender.UnitTests.csproj" `
    -OldText @'
  <ItemGroup>
    <ProjectReference Include="..\..\src\BuildingBlocks\Domain\MusicaAprender.BuildingBlocks.Domain.csproj" />
    <ProjectReference Include="..\..\src\Modules\Security\MusicaAprender.Modules.Security.csproj" />
  </ItemGroup>
'@ `
    -NewText @'
  <ItemGroup>
    <ProjectReference Include="..\..\src\BuildingBlocks\Domain\MusicaAprender.BuildingBlocks.Domain.csproj" />
    <ProjectReference Include="..\..\src\Modules\Identity\MusicaAprender.Modules.Identity.csproj" />
    <ProjectReference Include="..\..\src\Modules\Security\MusicaAprender.Modules.Security.csproj" />
  </ItemGroup>
'@ `
    -AlreadyMarker '..\..\src\Modules\Identity\MusicaAprender.Modules.Identity.csproj' `
    -Description "referencia UnitTests a modulo Identity"

# Program: DI + endpoint.
Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
'@ `
    -NewText @'
using MusicaAprender.Modules.Configuration.Infrastructure.Publication;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Security.Infrastructure.Administration;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Identity.Infrastructure.Preferences;" `
    -Description "namespace de preferencias en API"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
builder.Services.AddSingleton<PersonalAccountLoginService>();
builder.Services.AddSingleton<MinimumPublishedConfigurationReader>();
'@ `
    -NewText @'
builder.Services.AddSingleton<PersonalAccountLoginService>();
builder.Services.AddSingleton<PersonalPreferenceService>();
builder.Services.AddSingleton<MinimumPublishedConfigurationReader>();
'@ `
    -AlreadyMarker "builder.Services.AddSingleton<PersonalPreferenceService>();" `
    -Description "servicio de preferencias"

Replace-ExactOnce `
    -RelativePath "apps/api/Program.cs" `
    -OldText @'
app.MapPersonalAccountLogout();
app.MapAuthorizationCatalog();
'@ `
    -NewText @'
app.MapPersonalAccountLogout();
app.MapPersonalPreferences();
app.MapAuthorizationCatalog();
'@ `
    -AlreadyMarker "app.MapPersonalPreferences();" `
    -Description "endpoint de preferencias"

# Registro: cada cuenta nueva recibe su revisión inicial.
Replace-ExactOnce `
    -RelativePath "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs" `
    -OldText @'
using MusicaAprender.Modules.Identity.Application.Consent;
using MusicaAprender.Modules.Identity.Infrastructure.Registration;
'@ `
    -NewText @'
using MusicaAprender.Modules.Identity.Application.Consent;
using MusicaAprender.Modules.Identity.Infrastructure.Preferences;
using MusicaAprender.Modules.Identity.Infrastructure.Registration;
'@ `
    -AlreadyMarker "using MusicaAprender.Modules.Identity.Infrastructure.Preferences;" `
    -Description "namespace de preferencias en registro"

Replace-ExactOnce `
    -RelativePath "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs" `
    -OldText @'
                    await IdentityProfileRegistrationWriter.CreateMinimalAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        token);

                    await IdentityConsentRegistrationWriter.CreateAcceptedAsync(
'@ `
    -NewText @'
                    await IdentityProfileRegistrationWriter.CreateMinimalAsync(
                        connection,
                        transaction,
                        proposedAccountId,
                        token);

                    var preferencesCreated =
                        await PersonalPreferenceService.TryCreateInitialAsync(
                            connection,
                            transaction,
                            proposedAccountId,
                            token);

                    if (!preferencesCreated)
                    {
                        throw new InvalidOperationException(
                            "La cuenta nueva ya contiene una cabeza de preferencias inesperada.");
                    }

                    await IdentityConsentRegistrationWriter.CreateAcceptedAsync(
'@ `
    -AlreadyMarker "PersonalPreferenceService.TryCreateInitialAsync(" `
    -Description "preferencias iniciales atomicas en registro"

# UI-008 real.
Replace-ExactOnce `
    -RelativePath "apps/web/src/routes/student/StudentArea.tsx" `
    -OldText @'
import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';

export type StudentAreaProps = {
  match: RouteMatch;
};

export default function StudentArea({ match }: StudentAreaProps) {
  return (
    <RoutePlaceholder
      areaLabel="Área estudiante"
      description="La experiencia de estudiante conserva la frontera entre contenido público y datos privados. Persistir preferencias, respuestas o progreso requiere una sesión confirmada por el servidor."
      match={match}
    />
  );
}
'@ `
    -NewText @'
import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { PersonalPreferencesPage } from './PersonalPreferencesPage';
import './student-area.css';

export type StudentAreaProps = {
  match: RouteMatch;
};

export default function StudentArea({ match }: StudentAreaProps) {
  if (match.route.id === 'UI-MVP-008') {
    return <PersonalPreferencesPage />;
  }

  return (
    <RoutePlaceholder
      areaLabel="Área estudiante"
      description="La experiencia de estudiante conserva la frontera entre contenido público y datos privados. Persistir preferencias, respuestas o progreso requiere una sesión confirmada por el servidor."
      match={match}
    />
  );
}
'@ `
    -AlreadyMarker "PersonalPreferencesPage" `
    -Description "UI-MVP-008 preferencias reales"

# CI smoke.
Replace-ExactOnce `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText @'
      - name: Verify primary security and audit events
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL033_USE_DOCKER_PSQL: 'false'
          BL033_API_URL: https://localhost:5449
        run: bash scripts/ci/security/verify-primary-audit.sh

      - name: Verify encrypted private object storage
'@ `
    -NewText @'
      - name: Verify primary security and audit events
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL033_USE_DOCKER_PSQL: 'false'
          BL033_API_URL: https://localhost:5449
        run: bash scripts/ci/security/verify-primary-audit.sh

      - name: Verify basic profile and safe personal preferences
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL034_USE_DOCKER_PSQL: 'false'
          BL034_API_URL: https://localhost:5450
        run: bash scripts/ci/identity/verify-personal-preferences.sh

      - name: Verify encrypted private object storage
'@ `
    -AlreadyMarker "Verify basic profile and safe personal preferences" `
    -Description "smoke BL034 en CI"

$contextFactory = Read-Normalized -RelativePath "apps/api/Security/HttpDatabaseSessionContextFactory.cs"
if (-not $contextFactory.Contains("SecuritySessionPolicy.SafeRoleCode")) {
    throw "HttpDatabaseSessionContextFactory no conserva fallback seguro para tickets sin roles."
}
if ($contextFactory.Contains("fallbackRoles.Count != 1")) {
    throw "HttpDatabaseSessionContextFactory conserva la exigencia incompatible de exactamente un rol."
}

Write-Host "OK: contexto RLS autenticado alineado con tickets BL-MVP-030 sin claims de rol."

Write-Host "Actualizando lockfile de UnitTests por la nueva referencia a Identity..."
& dotnet restore `
    "tests/UnitTests/MusicaAprender.UnitTests.csproj"
Assert-LastExitCode "Restore UnitTests y packages.lock BL-MVP-034"

Write-Host "Ejecutando preflight de compilacion BL-MVP-034..."
& dotnet build `
    "apps/api/MusicaAprender.Api.csproj" `
    --no-restore
Assert-LastExitCode "Preflight API BL-MVP-034"

& dotnet build `
    "tests/UnitTests/MusicaAprender.UnitTests.csproj" `
    --no-restore
Assert-LastExitCode "Preflight UnitTests BL-MVP-034"

Write-Host "OK: API y UnitTests BL034 compilan con referencias modulares explicitas."

& "$PSScriptRoot/check-toolchain.ps1"

$dotnetVersion = (& dotnet --version).Trim()
$nodeVersion = (& node --version).Trim()
$npmVersion = (& npm.cmd --version).Trim()

if (($dotnetVersion -ne $ExpectedDotNet) -or ($nodeVersion -ne $ExpectedNode) -or ($npmVersion -ne $ExpectedNpm)) {
    throw "Toolchain inesperada despues de check-toolchain."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

npm.cmd ci
Assert-LastExitCode "npm ci BL-MVP-034"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$formatTargets = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-034.md",
    "README/BL-MVP-034_README.md",
    "apps/web/src/routes/student/PersonalPreferencesPage.tsx",
    "apps/web/src/routes/student/StudentArea.tsx",
    "apps/web/src/routes/student/student-area.css",
    "docs/engineering/identity/personal-preferences.md",
    "tests/E2ETests/personal-preferences.spec.ts"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-034"
& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-034"

$studentCss = Read-Normalized -RelativePath "apps/web/src/routes/student/student-area.css"
if ($studentCss -match 'var\(--(space|color|radius)-') {
    throw "student-area.css usa tokens fuera del namespace --ma-*."
}

$preferencesPage = Read-Normalized -RelativePath "apps/web/src/routes/student/PersonalPreferencesPage.tsx"
foreach ($requiredProblemField in @(
    "status: null",
    "code: 'identity.preferences.japanese-layer.required'",
    "cause:",
    "retryable: false"
)) {
    if (-not $preferencesPage.Contains($requiredProblemField)) {
        throw "ClientProblem local incompleto: falta $requiredProblemField."
    }
}

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/identity/verify-personal-preferences.sh"
Assert-LastExitCode "Sintaxis smoke BL-MVP-034"

npm.cmd run test:e2e:install
Assert-LastExitCode "Instalacion Chromium BL-MVP-034"

Write-Host "Ejecutando preflight frontend y E2E focalizado BL-MVP-034..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Preflight build frontend BL-MVP-034"

$playwright = Join-Path $RepoRoot "node_modules\.bin\playwright.cmd"
& $playwright `
    test `
    "tests/E2ETests/personal-preferences.spec.ts" `
    --config "tests/E2ETests/playwright.config.ts"
Assert-LastExitCode "Preflight E2E preferencias BL-MVP-034"

Write-Host "OK: flujo UI-MVP-008 interactivo supera el E2E focalizado."

Write-Host "Ejecutando puerta local completa..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host "Iniciando entorno local reproducible..."
& "$PSScriptRoot/local/start.ps1"
& "$PSScriptRoot/local/verify-running.ps1"

$dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
$dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
$webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

$passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
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
    "BL032_API_URL",
    "BL033_USE_RUNNING_API",
    "BL033_USE_DOCKER_PSQL",
    "BL033_API_URL",
    "BL034_USE_RUNNING_API",
    "BL034_USE_DOCKER_PSQL",
    "BL034_API_URL"
)

$previous = @{}
foreach ($name in $environmentNames) {
    $previous[$name] =
        [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = $dbPort
    $env:PGUSER = $dbUser
    $env:PGDATABASE = $dbName
    $env:PGPASSWORD =
        [System.IO.File]::ReadAllText($passwordPath).Trim()

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
    Assert-LastExitCode "Regresion BL-MVP-032"

    $env:BL033_USE_RUNNING_API = "true"
    $env:BL033_USE_DOCKER_PSQL = "true"
    $env:BL033_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-primary-audit.sh"
    Assert-LastExitCode "Regresion BL-MVP-033"

    $env:BL034_USE_RUNNING_API = "true"
    $env:BL034_USE_DOCKER_PSQL = "true"
    $env:BL034_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/identity/verify-personal-preferences.sh"
    Assert-LastExitCode "Smoke BL-MVP-034"
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
Assert-LastExitCode "git diff --check BL-MVP-034"

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-only
Write-Host ""

Write-Host "OK: BL-MVP-034 instalado y validado localmente con perfil y preferencias seguras."
Write-Host "No se ejecuto git add, commit ni push."

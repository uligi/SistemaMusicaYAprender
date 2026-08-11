[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "73fff5fe4982085ba090316c883587ef987e746f"
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
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1
    if ($null -eq $match) {
        return $DefaultValue
    }
    return (($match -split "=", 2)[1]).Trim()
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"

    $stagedPaths = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta del indice para tsconfig.app.tsbuildinfo"
    if ($stagedPaths.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $trackedPaths = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de seguimiento de tsconfig.app.tsbuildinfo"
    if ($trackedPaths.Count -eq 0) {
        return
    }

    $generatedState = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta del archivo incremental TypeScript"
    if ($generatedState.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Replace-ExactText {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$OldText,
        [Parameter(Mandatory = $true)][string]$NewText,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $path = Join-Path $RepoRoot $RelativePath
    $content = [System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)

    if ($content.Contains($NewText)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    if (-not $content.Contains($OldText)) {
        throw "No se encontro el ancla exacta para: $Description"
    }

    $updated = $content.Replace($OldText, $NewText)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $path,
        $updated,
        $utf8NoBom)
    Write-Host "OK: $Description."
}

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-030 debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

Restore-GeneratedTypeScriptState

$allowedPaths = @(
    ".github/workflows/ci.yml",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030A.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030B.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030C.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030D.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030E.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030F.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030G.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030H.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030I.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030J.md",
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-030K.md",
    "README/BL-MVP-030_README.md",
    "README/BL-MVP-030A_README.md",
    "README/BL-MVP-030B_README.md",
    "README/BL-MVP-030C_README.md",
    "README/BL-MVP-030D_README.md",
    "README/BL-MVP-030E_README.md",
    "README/BL-MVP-030F_README.md",
    "README/BL-MVP-030G_README.md",
    "README/BL-MVP-030H_README.md",
    "README/BL-MVP-030I_README.md",
    "README/BL-MVP-030J_README.md",
    "README/BL-MVP-030K_README.md",
    "apps/api/Endpoints/Identity/PersonalAccountLoginEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountLoginResponse.cs",
    "apps/api/Endpoints/Security/AuthorizationCatalogEndpoint.cs",
    "apps/api/Program.cs",
    "apps/api/Security/EffectivePermissionEndpointFilter.cs",
    "apps/api/Security/SecuritySessionTicketStore.cs",
    "apps/web/src/app/access/AccessContext.tsx",
    "apps/web/src/app/router/route-manifest.ts",
    "docs/engineering/security/effective-authorization.md",
    "scripts/apply-bl-mvp-030.ps1",
    "scripts/apply-bl-mvp-030a.ps1",
    "scripts/apply-bl-mvp-030b.ps1",
    "scripts/apply-bl-mvp-030c.ps1",
    "scripts/apply-bl-mvp-030d.ps1",
    "scripts/apply-bl-mvp-030e.ps1",
    "scripts/apply-bl-mvp-030f.ps1",
    "scripts/apply-bl-mvp-030g.ps1",
    "scripts/apply-bl-mvp-030h.ps1",
    "scripts/apply-bl-mvp-030i.ps1",
    "scripts/apply-bl-mvp-030j.ps1",
    "scripts/apply-bl-mvp-030k.ps1",
    "scripts/ci/security/verify-effective-authorization.sh",
    "src/Modules/Security/Infrastructure/Authorization/AuthorizationDecision.cs",
    "src/Modules/Security/Infrastructure/Authorization/AuthorizationScope.cs",
    "src/Modules/Security/Infrastructure/Authorization/AuthorizationScopeMatcher.cs",
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAccessSnapshot.cs",
    "src/Modules/Security/Infrastructure/Authorization/EffectiveAuthorizationService.cs",
    "tests/E2ETests/effective-authorization.spec.ts",
    "tests/E2ETests/personal-logout.spec.ts",
    "tests/UnitTests/Modules/Security/AuthorizationScopeMatcherTests.cs"
)

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($path in $allowedPaths) {
    [void]$allowed.Add($path.Replace("\", "/"))
}

$unexpected = [System.Collections.Generic.List[string]]::new()
$statusLines = @(git status --porcelain=v1 --untracked-files=all)
Assert-LastExitCode "Inventario Git previo"

foreach ($line in $statusLines) {
    if ($line.Length -lt 4) {
        [void]$unexpected.Add($line)
        continue
    }

    $relativePath = $line.Substring(3).Trim('"').Replace("\", "/")
    if ($relativePath.Contains(" -> ")) {
        $relativePath = ($relativePath -split " -> ", 2)[1]
    }

    if (-not $allowed.Contains($relativePath)) {
        [void]$unexpected.Add($relativePath)
    }
}

if ($unexpected.Count -gt 0) {
    throw "Hay cambios ajenos al paquete BL-MVP-030: $($unexpected -join ', ')."
}

$programOldUsing = @'
using MusicaAprender.Api.Endpoints.Identity;
'@
$programNewUsing = @'
using MusicaAprender.Api.Endpoints.Identity;
using MusicaAprender.Api.Endpoints.Security;
'@
Replace-ExactText `
    -RelativePath "apps/api/Program.cs" `
    -OldText $programOldUsing `
    -NewText $programNewUsing `
    -Description "namespace de endpoint de autorizacion"

$programOldService = @'
builder.Services.AddSingleton<MinimumRoleCatalogReader>();
'@
$programNewService = @'
builder.Services.AddSingleton<MinimumRoleCatalogReader>();
builder.Services.AddSingleton<EffectiveAuthorizationService>();
'@
Replace-ExactText `
    -RelativePath "apps/api/Program.cs" `
    -OldText $programOldService `
    -NewText $programNewService `
    -Description "motor de permisos efectivos registrado"

$programOldMap = @'
app.MapPersonalAccountLogout();

app.Run();
'@
$programNewMap = @'
app.MapPersonalAccountLogout();
app.MapAuthorizationCatalog();

app.Run();
'@
Replace-ExactText `
    -RelativePath "apps/api/Program.cs" `
    -OldText $programOldMap `
    -NewText $programNewMap `
    -Description "consulta protegida de catalogo de autorizacion"

$routePath = "apps/web/src/app/router/route-manifest.ts"
$routeReplacements = @(
    @("requiredCapabilities: ['editorial:access'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW', 'EDITORIAL.PUBLISH', 'EDITORIAL.CORRECT'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['catalog:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['rights:edit', 'rights:review'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['lyrics:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['timing:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['translation:edit', 'translation:review'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['analysis:edit', 'analysis:review'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['exercise:edit'],",
      "requiredCapabilities: ['EDITORIAL.DRAFT'],"),
    @("requiredCapabilities: ['package:edit', 'package:review'],",
      "requiredCapabilities: ['EDITORIAL.SUBMIT', 'EDITORIAL.REVIEW'],`n    capabilityMode: 'any',"),
    @("requiredCapabilities: ['publication:review'],",
      "requiredCapabilities: ['EDITORIAL.PUBLISH'],"),
    @("requiredCapabilities: ['publication:correct'],",
      "requiredCapabilities: ['EDITORIAL.CORRECT'],"),
    @("requiredCapabilities: ['security:roles'],",
      "requiredCapabilities: ['SECURITY.MANAGE_ROLES'],"),
    @("requiredCapabilities: ['configuration:manage'],",
      "requiredCapabilities: ['CONFIG.MANAGE'],"),
    @("requiredCapabilities: ['audit:read'],",
      "requiredCapabilities: ['SECURITY.READ_AUDIT'],")
)

foreach ($replacement in $routeReplacements) {
    $routeFile = Join-Path $RepoRoot $routePath
    $routeContent = [System.IO.File]::ReadAllText(
        $routeFile,
        [System.Text.Encoding]::UTF8)

    if ($routeContent.Contains($replacement[0])) {
        $updated = $routeContent.Replace(
            $replacement[0],
            $replacement[1])
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText(
            $routeFile,
            $updated,
            $utf8NoBom)
        Write-Host "OK: reemplazado alias legacy $($replacement[0])."
    }
}

$routeContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $routePath),
    [System.Text.Encoding]::UTF8)

$legacyCapabilityMarkers = @(
    "editorial:access",
    "catalog:edit",
    "rights:edit",
    "rights:review",
    "lyrics:edit",
    "timing:edit",
    "translation:edit",
    "translation:review",
    "analysis:edit",
    "analysis:review",
    "exercise:edit",
    "package:edit",
    "package:review",
    "publication:review",
    "publication:correct",
    "security:roles",
    "configuration:manage",
    "audit:read"
)

$canonicalCapabilityMarkers = @(
    "EDITORIAL.DRAFT",
    "EDITORIAL.REVIEW",
    "EDITORIAL.PUBLISH",
    "EDITORIAL.CORRECT",
    "EDITORIAL.SUBMIT",
    "SECURITY.MANAGE_ROLES",
    "CONFIG.MANAGE",
    "SECURITY.READ_AUDIT"
)

$legacyPresent = @(
    $legacyCapabilityMarkers |
        Where-Object { $routeContent.Contains($_) }
)

$canonicalMissing = @(
    $canonicalCapabilityMarkers |
        Where-Object { -not $routeContent.Contains($_) }
)

if ($legacyPresent.Count -gt 0 -or $canonicalMissing.Count -gt 0) {
    throw "El route-manifest no quedo reconciliado. Legacy=$($legacyPresent -join ', '); faltan=$($canonicalMissing -join ', ')."
}

Write-Host "OK: capacidades UI canonicas reconciliadas sin falsos positivos por destino repetido."

$workflowOld = @'
      - name: Verify login abuse limits and session bounds
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
        run: bash scripts/ci/identity/verify-login-abuse.sh

      - name: Start private development object store
'@
$workflowNew = @'
      - name: Verify login abuse limits and session bounds
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
        run: bash scripts/ci/identity/verify-login-abuse.sh

      - name: Verify effective permissions, scope and current validity
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGUSER: postgres
          PGPASSWORD: postgres
          PGDATABASE: musica_aprender_ci
          BL030_USE_DOCKER_PSQL: 'false'
          BL030_API_URL: https://localhost:5446
        run: bash scripts/ci/security/verify-effective-authorization.sh

      - name: Start private development object store
'@
Replace-ExactText `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText $workflowOld `
    -NewText $workflowNew `
    -Description "smoke BL-MVP-030 agregado a CI"

& "$PSScriptRoot/check-toolchain.ps1"
& "$PSScriptRoot/local/ensure-local-secrets.ps1"

npm.cmd ci
Assert-LastExitCode "npm ci"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
& $prettier --write `
    "apps/web/src/app/router/route-manifest.ts" `
    "docs/engineering/security/effective-authorization.md"
Assert-LastExitCode "Prettier de archivos BL-MVP-030"

& $prettier --check `
    "apps/web/src/app/router/route-manifest.ts" `
    "docs/engineering/security/effective-authorization.md"
Assert-LastExitCode "Prettier check de archivos BL-MVP-030"

npm.cmd run test:e2e:install
Assert-LastExitCode "Instalacion Chromium Playwright"

Write-Host "Ejecutando la puerta local completa de calidad..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host "Iniciando el entorno local reproducible..."
& "$PSScriptRoot/local/start.ps1"
& "$PSScriptRoot/local/verify-running.ps1"

$bashPath = Resolve-GitBash
$dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
$dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
$webPort = Get-DotEnvValue -Name "WEB_PORT" -DefaultValue "5173"

$passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
if (-not (Test-Path $passwordPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

$names = @(
    "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
    "BL026_USE_RUNNING_API", "BL026_USE_DOCKER_PSQL", "BL026_API_URL",
    "BL027_USE_RUNNING_API", "BL027_USE_DOCKER_PSQL", "BL027_API_URL",
    "BL029_USE_DOCKER_PSQL", "BL029_API_URL",
    "BL030_USE_DOCKER_PSQL", "BL030_API_URL"
)
$previous = @{}
foreach ($name in $names) {
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

    $env:BL026_USE_RUNNING_API = "true"
    $env:BL026_USE_DOCKER_PSQL = "true"
    $env:BL026_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/identity/verify-personal-login.sh"
    Assert-LastExitCode "Regresion BL-MVP-026"

    $env:BL027_USE_RUNNING_API = "true"
    $env:BL027_USE_DOCKER_PSQL = "true"
    $env:BL027_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/identity/verify-personal-logout.sh"
    Assert-LastExitCode "Regresion BL-MVP-027"

    $env:BL029_USE_DOCKER_PSQL = "true"
    $env:BL029_API_URL = "https://localhost:5445"
    & $bashPath "./scripts/ci/identity/verify-login-abuse.sh"
    Assert-LastExitCode "Regresion BL-MVP-029"

    $env:BL030_USE_DOCKER_PSQL = "true"
    $env:BL030_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-effective-authorization.sh"
    Assert-LastExitCode "Smoke BL-MVP-030"
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            "Process")
    }
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-only
Write-Host ""
Write-Host "OK: BL-MVP-030 instalado y validado localmente con autorizacion server-side y alcance vigente."
Write-Host "No se ejecuto git add, commit ni push."

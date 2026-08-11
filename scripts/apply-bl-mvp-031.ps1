[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af"
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
    $staged = @(git diff --cached --name-only -- $relativePath)
    Assert-LastExitCode "Consulta de indice tsbuildinfo"
    if ($staged.Count -gt 0) {
        throw "$relativePath contiene cambios staged."
    }

    $tracked = @(git ls-files -- $relativePath)
    Assert-LastExitCode "Consulta de tracking tsbuildinfo"
    if ($tracked.Count -eq 0) {
        return
    }

    $state = @(git status --porcelain=v1 -- $relativePath)
    Assert-LastExitCode "Consulta de tsbuildinfo"
    if ($state.Count -gt 0) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restauracion de tsbuildinfo"
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
    throw "BL-MVP-031 debe aplicarse sobre main. Rama actual: '$currentBranch'."
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
    "compose.yml",
    "apps/api/Program.cs",
    "apps/api/Endpoints/Security/RoleAssignmentEndpoints.cs",
    "apps/api/Security/BackofficeSecurityTransactionExecutor.cs",
    "apps/web/src/routes/administration/AdministrationArea.tsx",
    "apps/web/src/routes/administration/RoleManagementPage.tsx",
    "apps/web/src/routes/administration/role-management.css",
    "docs/engineering/security/role-assignment-administration.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031A.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031B.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031C.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031D.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031E.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031F.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031G.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031H.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031I.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031J.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031K.md",
    "README/BL-MVP-031_README.md",
    "README/BL-MVP-031A_README.md",
    "README/BL-MVP-031B_README.md",
    "README/BL-MVP-031C_README.md",
    "README/BL-MVP-031D_README.md",
    "README/BL-MVP-031E_README.md",
    "README/BL-MVP-031F_README.md",
    "README/BL-MVP-031G_README.md",
    "README/BL-MVP-031H_README.md",
    "README/BL-MVP-031I_README.md",
    "README/BL-MVP-031J_README.md",
    "README/BL-MVP-031K_README.md",
    "scripts/apply-bl-mvp-031.ps1",
    "scripts/apply-bl-mvp-031a.ps1",
    "scripts/apply-bl-mvp-031b.ps1",
    "scripts/apply-bl-mvp-031c.ps1",
    "scripts/apply-bl-mvp-031d.ps1",
    "scripts/apply-bl-mvp-031e.ps1",
    "scripts/apply-bl-mvp-031f.ps1",
    "scripts/apply-bl-mvp-031g.ps1",
    "scripts/apply-bl-mvp-031h.ps1",
    "scripts/apply-bl-mvp-031i.ps1",
    "scripts/apply-bl-mvp-031j.ps1",
    "scripts/apply-bl-mvp-031k.ps1",
    "scripts/ci/security/verify-role-assignments.sh",
    "src/Modules/Security/Infrastructure/Administration/IPrivilegedSecurityTransactionExecutor.cs",
    "src/Modules/Security/Infrastructure/Administration/RoleAssignmentAdministrationService.cs",
    "tests/E2ETests/role-management.spec.ts"
)

$allowed = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal)
foreach ($path in $allowedPaths) {
    [void]$allowed.Add($path)
}

function Test-IsInstructionOrganizationPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return $RelativePath -match '^INSTRUCCIONES_[^/]+\.md$' -or
        $RelativePath -match '^Instrucciones/INSTRUCCIONES_[^/]+\.md$'
}

$unexpected = @(
    git status --porcelain=v1 --untracked-files=all |
        ForEach-Object {
            if ($_.Length -lt 4) { return }
            $raw = $_.Substring(3).Trim()
            if ($raw.StartsWith('"') -and $raw.EndsWith('"')) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
            $raw.Replace("\", "/")
        } |
        Where-Object {
            -not $allowed.Contains($_) -and
            -not (Test-IsInstructionOrganizationPath -RelativePath $_)
        }
)

if ($unexpected.Count -gt 0) {
    throw "Hay cambios ajenos al paquete BL-MVP-031: $($unexpected -join ', ')."
}

# El ZIP ya deposita Program.cs y AdministrationArea.tsx completos.
if (-not (
    [System.IO.File]::ReadAllText(
        (Join-Path $RepoRoot "apps/api/Program.cs"),
        [System.Text.Encoding]::UTF8
    ).Contains("app.MapRoleAssignments();")
)) {
    throw "Program.cs del paquete BL-MVP-031 no fue extraido correctamente."
}

if (-not (
    [System.IO.File]::ReadAllText(
        (Join-Path $RepoRoot "apps/web/src/routes/administration/AdministrationArea.tsx"),
        [System.Text.Encoding]::UTF8
    ).Contains("RoleManagementPage")
)) {
    throw "AdministrationArea.tsx del paquete BL-MVP-031 no fue extraido correctamente."
}

$composeOld = @'
      - postgres_api_password
      - object_store_access_key
'@
$composeNew = @'
      - postgres_api_password
      - postgres_backoffice_password
      - object_store_access_key
'@
Replace-ExactText `
    -RelativePath "compose.yml" `
    -OldText $composeOld `
    -NewText $composeNew `
    -Description "credencial backoffice montada solo para el pool privilegiado de la API"

$workflowOld = @'
        run: bash scripts/ci/security/verify-effective-authorization.sh

      - name: Start private development object store
'@
$workflowNew = @'
        run: bash scripts/ci/security/verify-effective-authorization.sh

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
'@
Replace-ExactText `
    -RelativePath ".github/workflows/ci.yml" `
    -OldText $workflowOld `
    -NewText $workflowNew `
    -Description "smoke BL-MVP-031 agregado a CI"

& "$PSScriptRoot/check-toolchain.ps1"
& "$PSScriptRoot/local/ensure-local-secrets.ps1"

$backofficeSecret = Join-Path $RepoRoot "secrets\local\postgres_backoffice_password"
if (-not (Test-Path $backofficeSecret -PathType Leaf)) {
    throw "Falta secrets/local/postgres_backoffice_password."
}

npm.cmd ci
Assert-LastExitCode "npm ci"

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$formatTargets = @(
    "apps/web/src/routes/administration/AdministrationArea.tsx",
    "apps/web/src/routes/administration/RoleManagementPage.tsx",
    "apps/web/src/routes/administration/role-management.css",
    "tests/E2ETests/role-management.spec.ts",
    "docs/engineering/security/role-assignment-administration.md",
    "README/BL-MVP-031_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-031"

& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-031"

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
    "BL030_USE_RUNNING_API", "BL030_USE_DOCKER_PSQL", "BL030_API_URL",
    "BL031_USE_RUNNING_API", "BL031_USE_DOCKER_PSQL", "BL031_API_URL"
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

    $env:BL030_USE_RUNNING_API = "true"
    $env:BL030_USE_DOCKER_PSQL = "true"
    $env:BL030_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-effective-authorization.sh"
    Assert-LastExitCode "Regresion BL-MVP-030"

    $env:BL031_USE_RUNNING_API = "true"
    $env:BL031_USE_DOCKER_PSQL = "true"
    $env:BL031_API_URL = "http://localhost:$webPort"
    & $bashPath "./scripts/ci/security/verify-role-assignments.sh"
    Assert-LastExitCode "Smoke BL-MVP-031"
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previous[$name],
            "Process")
    }
}

Restore-GeneratedTypeScriptState

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-only
Write-Host ""
Write-Host "OK: BL-MVP-031 instalado y validado localmente con asignacion/revocacion auditada y minimo privilegio."
Write-Host "No se ejecuto git add, commit ni push."

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "3f1ae3d64b3a0c20c5b2ba1af7003a9cc4b305af"
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
        Write-Host "OK: tsconfig.app.tsbuildinfo restaurado."
    }
}

function Normalize-InstructionDirectory {
    $instructionDirectory = Join-Path $RepoRoot "Instrucciones"
    [void](New-Item -ItemType Directory -Force -Path $instructionDirectory)

    $rootInstructions = @(
        Get-ChildItem -Path $RepoRoot -File -Filter "INSTRUCCIONES_*.md"
    )

    foreach ($source in $rootInstructions) {
        $target = Join-Path $instructionDirectory $source.Name

        if (Test-Path $target -PathType Leaf) {
            $sourceHash = (Get-FileHash -Algorithm SHA256 -Path $source.FullName).Hash
            $targetHash = (Get-FileHash -Algorithm SHA256 -Path $target).Hash
            if ($sourceHash -ne $targetHash) {
                throw "Conflicto al organizar $($source.Name): raiz e Instrucciones tienen contenido distinto."
            }
            Remove-Item -Force $source.FullName
        }
        else {
            Move-Item -Path $source.FullName -Destination $target
        }
    }

    Write-Host "OK: archivos INSTRUCCIONES_*.md normalizados bajo Instrucciones/."
}

Write-Host "BL-MVP-031K: renovando CSRF autenticado del smoke y normalizando Instrucciones/..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-031K debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

Normalize-InstructionDirectory
Restore-GeneratedTypeScriptState

$smokePath = Join-Path $RepoRoot "scripts\ci\security\verify-role-assignments.sh"
$mainPath = Join-Path $RepoRoot "scripts\apply-bl-mvp-031.ps1"

foreach ($path in @($smokePath, $mainPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "No se encontro $path."
    }
}

$smokeContent = [System.IO.File]::ReadAllText(
    $smokePath,
    [System.Text.Encoding]::UTF8)

foreach ($marker in @(
    "refresh_authenticated_csrf",
    'refresh_authenticated_csrf "grant"',
    'refresh_authenticated_csrf "revoke"',
    "target_lookup_hex",
    "Respuesta HTTP del grant autorizado"
)) {
    if (-not $smokeContent.Contains($marker)) {
        throw "El smoke BL-MVP-031 no contiene el marcador esperado: $marker"
    }
}

$mainContent = [System.IO.File]::ReadAllText(
    $mainPath,
    [System.Text.Encoding]::UTF8)

foreach ($marker in @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031K.md",
    "README/BL-MVP-031K_README.md",
    "scripts/apply-bl-mvp-031k.ps1",
    "Test-IsInstructionOrganizationPath"
)) {
    if (-not $mainContent.Contains($marker)) {
        throw "La puerta BL-MVP-031 no contiene el marcador esperado: $marker"
    }
}

& "$PSScriptRoot/check-toolchain.ps1"

if (-not (Test-Path "node_modules" -PathType Container)) {
    npm.cmd ci
    Assert-LastExitCode "npm ci"
}

$prettier = Join-Path $RepoRoot "node_modules\.bin\prettier.cmd"
$prettierVersion = (& $prettier --version).Trim()
Assert-LastExitCode "Consulta de version Prettier"
if ($prettierVersion -ne $ExpectedPrettier) {
    throw "Prettier inesperado. Se esperaba $ExpectedPrettier y se encontro $prettierVersion."
}

$formatTargets = @(
    "README/BL-MVP-031K_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-031K.md"
)

& $prettier --write @formatTargets
Assert-LastExitCode "Prettier BL-MVP-031K"

& $prettier --check @formatTargets
Assert-LastExitCode "Prettier check BL-MVP-031K"
Write-Host "OK: archivos 031K formateados."

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/security/verify-role-assignments.sh"
Assert-LastExitCode "Sintaxis bash smoke BL-MVP-031"
Write-Host "OK: sintaxis bash del smoke BL-MVP-031."

& "$PSScriptRoot/local/verify-running.ps1"

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

    $env:BL031_USE_RUNNING_API = "true"
    $env:BL031_USE_DOCKER_PSQL = "true"
    $env:BL031_API_URL = "http://localhost:$webPort"

    & $bashPath "./scripts/ci/security/verify-role-assignments.sh"
    Assert-LastExitCode "Smoke BL-MVP-031 corregido"
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
Assert-LastExitCode "git diff --check BL-MVP-031K"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "OK: BL-MVP-031K aplicado y smoke BL-MVP-031 validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply-bl-mvp-031.ps1"

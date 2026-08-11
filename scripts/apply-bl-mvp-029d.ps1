[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "147e86ffe9b53435d7f277282f6c091aef3523d0"
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

Write-Host "BL-MVP-029D: desacoplando umbrales 5/20 de la ventana corta de recuperacion..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-029D debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedBase) {
    throw "Base incorrecta. Se esperaba $ExpectedBase y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$smokePath = "scripts/ci/identity/verify-login-abuse.sh"
$baseInstallerPath = "scripts/apply-bl-mvp-029.ps1"

$smokeContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $smokePath),
    [System.Text.Encoding]::UTF8)

foreach ($marker in @(
    "threshold_window_seconds=300",
    "recovery_window_seconds=5",
    'start_api "$threshold_window_seconds"',
    'start_api "$recovery_window_seconds"',
    "persistencia de cinco fallos conocidos",
    "eventos de umbral 5/20 seudonimizados"
)) {
    if (-not $smokeContent.Contains($marker)) {
        throw "El smoke 029D no contiene el marcador requerido: $marker"
    }
}

$baseContent = [System.IO.File]::ReadAllText(
    (Join-Path $RepoRoot $baseInstallerPath),
    [System.Text.Encoding]::UTF8)

foreach ($artifact in @(
    "INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-029D.md",
    "README/BL-MVP-029D_README.md",
    "scripts/apply-bl-mvp-029d.ps1"
)) {
    if (-not $baseContent.Contains('"' + $artifact + '"')) {
        throw "El instalador base no reconoce el artefacto 029D: $artifact"
    }
}

$bashPath = Resolve-GitBash
& $bashPath -n "./scripts/ci/identity/verify-login-abuse.sh"
Assert-LastExitCode "bash -n del smoke BL-MVP-029D"
Write-Host "OK: bash -n aprobado."

& "$PSScriptRoot/check-toolchain.ps1"
& "$PSScriptRoot/local/ensure-local-secrets.ps1"

docker compose up --detach postgres
Assert-LastExitCode "Inicio PostgreSQL para BL-MVP-029D"

dotnet build apps/api/MusicaAprender.Api.csproj --configuration Release
Assert-LastExitCode "Build Release API para BL-MVP-029D"

$dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
$dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"
$passwordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
if (-not (Test-Path $passwordPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

$names = @(
    "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD",
    "BL029_API_URL", "BL029_USE_DOCKER_PSQL"
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = $dbPort
    $env:PGUSER = $dbUser
    $env:PGDATABASE = $dbName
    $env:PGPASSWORD = [System.IO.File]::ReadAllText($passwordPath).Trim()
    $env:BL029_API_URL = "https://localhost:5445"
    $env:BL029_USE_DOCKER_PSQL = "true"

    & $bashPath "./scripts/ci/identity/verify-login-abuse.sh"
    Assert-LastExitCode "Smoke standalone BL-MVP-029D"
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
    }
}

git diff --check -- $smokePath $baseInstallerPath
Assert-LastExitCode "git diff --check de BL-MVP-029D"

Write-Host ""
Write-Host "OK: BL-MVP-029D validado con umbrales 5/20 y recuperacion desacoplada del costo Argon2id."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-029.ps1"

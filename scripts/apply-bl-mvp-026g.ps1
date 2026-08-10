[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "4d515484b8597615b9665be4b0c5bded43565a6e"
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

Write-Host "BL-MVP-026G: corrigiendo el lanzamiento HTTPS del smoke standalone de CI..."

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama Git"
if ($currentBranch -ne "main") {
    throw "BL-MVP-026G debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de revision Git"
if ($currentHead -ne $ExpectedHead) {
    throw "Base incorrecta para BL-MVP-026G. Se esperaba $ExpectedHead y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice Git sin staging previo"

$targetRelative = "scripts/ci/identity/verify-personal-login.sh"
$target = Join-Path $RepoRoot $targetRelative
if (-not (Test-Path $target -PathType Leaf)) {
    throw "No se encontro $targetRelative."
}

# No se sobreescriben cambios funcionales inesperados en el verificador.
$targetStatus = @(git status --porcelain=v1 -- $targetRelative)
Assert-LastExitCode "Consulta de estado del verificador"
if ($targetStatus.Count -gt 0) {
    throw "$targetRelative ya contiene cambios locales. Restaure o respalde ese archivo antes de aplicar BL-MVP-026G."
}

$content = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

$alreadyPatched = $content.Contains("--no-launch-profile")
if ($alreadyPatched) {
    Write-Host "OK: --no-launch-profile ya esta presente."
}
else {
    $pattern = '(?m)^  dotnet run \\\r?\n    --project apps/api/MusicaAprender\.Api\.csproj \\\r?$'
    $matches = [regex]::Matches($content, $pattern)

    if ($matches.Count -ne 1) {
        throw "Se esperaba exactamente un bloque dotnet run del smoke y se encontraron $($matches.Count). No se modifico el archivo."
    }

    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $replacement =
        '  dotnet run \' + $newline +
        '    --no-launch-profile \' + $newline +
        '    --project apps/api/MusicaAprender.Api.csproj \'

    $updated = [regex]::Replace($content, $pattern, $replacement, 1)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($target, $updated, $utf8NoBom)

    Write-Host "OK: se agrego --no-launch-profile al lanzamiento standalone del smoke."
}

$bashPath = Resolve-GitBash
Write-Host "Git Bash: $bashPath"

& $bashPath -n "./$targetRelative"
Assert-LastExitCode "bash -n de verify-personal-login.sh"
Write-Host "OK: bash -n aprobado."

git diff --check -- $targetRelative
Assert-LastExitCode "git diff --check de BL-MVP-026G"
Write-Host "OK: git diff --check aprobado."

Write-Host "Preparando prueba local equivalente al camino standalone de CI..."

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

docker compose up --detach postgres
Assert-LastExitCode "Inicio de PostgreSQL local"

dotnet build apps/api/MusicaAprender.Api.csproj --configuration Release
Assert-LastExitCode "Compilacion Release de la API"

$dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
$dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"
$dbPort = Get-DotEnvValue -Name "POSTGRES_PORT" -DefaultValue "5432"

$postgresPasswordPath = Join-Path $RepoRoot "secrets\local\postgres_password"
if (-not (Test-Path $postgresPasswordPath -PathType Leaf)) {
    throw "Falta secrets/local/postgres_password."
}

$environmentNames = @(
    "PGHOST",
    "PGPORT",
    "PGUSER",
    "PGDATABASE",
    "PGPASSWORD",
    "BL026_API_URL",
    "BL026_USE_RUNNING_API",
    "BL026_USE_DOCKER_PSQL"
)
$previousEnvironment = @{}

foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $env:PGHOST = "127.0.0.1"
    $env:PGPORT = $dbPort
    $env:PGUSER = $dbUser
    $env:PGDATABASE = $dbName
    $env:PGPASSWORD = [System.IO.File]::ReadAllText($postgresPasswordPath).Trim()

    # Puerto independiente del API Docker local. Reproduce el modo CI:
    # el propio script inicia Kestrel y consume HTTPS con certificado local.
    $env:BL026_API_URL = "https://localhost:5443"
    $env:BL026_USE_RUNNING_API = "false"
    $env:BL026_USE_DOCKER_PSQL = "true"

    & $bashPath "./scripts/ci/identity/verify-personal-login.sh"
    Assert-LastExitCode "Smoke standalone HTTPS BL-MVP-026"
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $previousEnvironment[$name],
            "Process")
    }
}

Write-Host ""
Write-Host "OK: BL-MVP-026G validado localmente contra el camino standalone HTTPS usado por CI."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host ""
Write-Host "Siguiente revision:"
Write-Host "  git status --short --untracked-files=all"
Write-Host "  git diff --check"
Write-Host "  git diff -- scripts/ci/identity/verify-personal-login.sh"

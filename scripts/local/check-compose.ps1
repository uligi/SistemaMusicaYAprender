$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$required = @(
    "compose.yml",
    ".env.example",
    ".dockerignore",
    "infrastructure\containers\api\Dockerfile",
    "infrastructure\containers\worker\Dockerfile",
    "infrastructure\containers\web\Dockerfile",
    "infrastructure\containers\web\nginx.conf",
    "infrastructure\containers\otel\otel-collector.yaml"
)

foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        throw "Falta archivo requerido de BL-MVP-006: $path"
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker no esta instalado o no esta disponible en PATH."
}

docker compose version
Assert-LastExitCode "Docker Compose"

docker compose config --quiet
Assert-LastExitCode "Validacion de compose.yml"

$config = docker compose config
Assert-LastExitCode "Lectura normalizada de compose.yml"

$services = @("web", "api", "worker", "postgres", "object-store", "smtp-sink", "otel-collector")
foreach ($service in $services) {
    if (-not ($config -match "(?m)^\s{2}$([regex]::Escape($service)):\s*$")) {
        throw "El Compose no contiene el servicio requerido: $service"
    }
}

Write-Host "OK: Docker Compose BL-MVP-006 contiene los 7 servicios y es valido."

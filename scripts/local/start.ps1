$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker no esta instalado o no esta disponible en PATH. Instale/inicie Docker Desktop y vuelva a ejecutar."
}

docker version *> $null
Assert-LastExitCode "Docker Engine"

docker compose version *> $null
Assert-LastExitCode "Docker Compose"

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env desde .env.example con credenciales SOLO de desarrollo local."
}

Write-Host "Construyendo y levantando el entorno local..."
docker compose up --build --detach
Assert-LastExitCode "docker compose up"

Write-Host ""
docker compose ps
Assert-LastExitCode "docker compose ps"

Write-Host ""
Write-Host "Entorno local iniciado."
Write-Host "Web:          http://localhost:5173"
Write-Host "API:          http://localhost:5080"
Write-Host "MinIO API:    http://localhost:9000"
Write-Host "MinIO consola:http://localhost:9001"
Write-Host "Mailpit UI:   http://localhost:8025"
Write-Host "OTel health:  http://localhost:13133"

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$expected = @("web", "api", "worker", "postgres", "object-store", "smtp-sink", "otel-collector")
$running = @(docker compose ps --status running --services)
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo consultar el estado de Docker Compose."
}

$missing = @($expected | Where-Object { $_ -notin $running })
if ($missing.Count -gt 0) {
    throw "Servicios que no estan en ejecucion: $($missing -join ', ')"
}

$api = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:5080/" -TimeoutSec 10
if ($api.StatusCode -ne 200) {
    throw "La API no respondio HTTP 200."
}

$web = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:5173/" -TimeoutSec 10
if ($web.StatusCode -ne 200) {
    throw "La web no respondio HTTP 200."
}

$otel = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:13133/" -TimeoutSec 10
if ($otel.StatusCode -ne 200) {
    throw "El health endpoint del collector no respondio HTTP 200."
}

Write-Host "OK: los 7 servicios estan ejecutandose y web/API/collector responden."

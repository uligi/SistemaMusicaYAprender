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

$web = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:5173/" -TimeoutSec 10
if ($web.StatusCode -ne 200) {
    throw "La web no respondio HTTP 200."
}

$live = Invoke-RestMethod -Uri "http://localhost:5080/health/live" -TimeoutSec 10
if ($live.status -ne "Healthy") {
    throw "La API no reporta liveness Healthy. Estado: $($live.status)"
}

$ready = Invoke-RestMethod -Uri "http://localhost:5080/health/ready" -TimeoutSec 10
if ($ready.status -ne "Healthy") {
    throw "La API no reporta readiness Healthy. Estado: $($ready.status)"
}

$dependencies = Invoke-RestMethod -Uri "http://localhost:5080/health/dependencies" -TimeoutSec 10
if ($dependencies.status -ne "Healthy") {
    throw "Las dependencias no reportan Healthy. Estado: $($dependencies.status)"
}

$otel = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:13133/" -TimeoutSec 10
if ($otel.StatusCode -ne 200) {
    throw "El health endpoint del collector no respondio HTTP 200."
}

Write-Host "OK: los 7 servicios estan ejecutandose; liveness, readiness y dependencias estan Healthy."

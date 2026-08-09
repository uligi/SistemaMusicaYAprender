$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$expected = @(
    "web",
    "api",
    "worker",
    "postgres",
    "object-store",
    "smtp-sink",
    "otel-collector"
)

$running = @(docker compose ps --status running --services)
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo consultar Docker Compose."
}

$missing = @($expected | Where-Object { $_ -notin $running })
if ($missing.Count -gt 0) {
    throw "Servicios que no estan en ejecucion: $($missing -join ', ')"
}

$correlationId = "blmvp008-" + [Guid]::NewGuid().ToString("N")

Write-Host "Generando solicitud correlacionada hacia la API..."
$response = Invoke-WebRequest `
    -UseBasicParsing `
    -Uri "http://localhost:5173/api/health/live" `
    -Headers @{ "X-Correlation-Id" = $correlationId } `
    -TimeoutSec 10

if ($response.StatusCode -ne 200) {
    throw "La API no respondio HTTP 200."
}

if ($response.Headers["X-Correlation-Id"] -ne $correlationId) {
    throw "La API no devolvio el mismo X-Correlation-Id."
}

Write-Host ""
Write-Host "Abra http://localhost:5173 en el navegador."
Write-Host "Deje la pagina abierta al menos 10 segundos para ejecutar la telemetria del cliente."
Write-Host ""
Read-Host "Presione ENTER cuando la pagina haya estado abierta al menos 10 segundos"

$requiredMarkers = @(
    "musica-aprender-api",
    "musica-aprender-worker",
    "musica-aprender-web",
    "musica_aprender.api.requests",
    "musica_aprender.worker.heartbeats",
    "musica_aprender.client.startups",
    $correlationId
)

$forbiddenValues = @(
    "musica-local-postgres",
    "musica-local-object-store"
)

$lastMissing = @()

for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Seconds 3

    $collectorLogs = docker compose logs otel-collector --since 10m
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron leer los logs del OpenTelemetry Collector."
    }

    foreach ($forbidden in $forbiddenValues) {
        if ($collectorLogs -match [regex]::Escape($forbidden)) {
            throw "La telemetria contiene un secreto local prohibido."
        }
    }

    $lastMissing = @(
        $requiredMarkers |
            Where-Object { -not ($collectorLogs -match [regex]::Escape($_)) }
    )

    if ($lastMissing.Count -eq 0) {
        Write-Host "OK: API, worker y cliente emitieron telemetria al collector."
        Write-Host "OK: trazas, metricas, logs y correlacion estan presentes sin secretos locales."
        exit 0
    }

    Write-Host "Esperando exportacion OpenTelemetry... intento $attempt/10."
}

throw "Falta evidencia de telemetria para: $($lastMissing -join ', ')"

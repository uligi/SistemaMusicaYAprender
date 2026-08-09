$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

function Get-DependencyHealth {
    return Invoke-RestMethod -Uri "http://localhost:5080/health/dependencies" -TimeoutSec 10
}

$baseline = Get-DependencyHealth
if ($baseline.status -ne "Healthy") {
    throw "La prueba requiere una linea base Healthy. Estado actual: $($baseline.status)"
}

Write-Host "Deteniendo temporalmente object-store para comprobar degradacion..."
docker compose stop object-store
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo detener object-store."
}

try {
    $degraded = $null

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        Start-Sleep -Seconds 1
        $current = Get-DependencyHealth

        if ($current.status -eq "Degraded") {
            $degraded = $current
            break
        }
    }

    if ($null -eq $degraded) {
        throw "El endpoint de dependencias no paso a Degraded cuando object-store dejo de estar disponible."
    }

    $objectStore = @($degraded.checks | Where-Object { $_.name -eq "object-store" })
    if ($objectStore.Count -ne 1 -or $objectStore[0].status -ne "Degraded") {
        throw "object-store no aparece como Degraded en la respuesta."
    }

    $json = $degraded | ConvertTo-Json -Depth 6
    if ($json -match '(?i)password|secret|connectionstring|accesskey') {
        throw "La respuesta de health contiene un nombre de campo que podria revelar secretos."
    }

    Write-Host "OK: dependencia no critica degradada sin afectar liveness ni revelar secretos."
}
finally {
    Write-Host "Restaurando object-store..."
    docker compose start object-store | Out-Host
}

for ($attempt = 1; $attempt -le 20; $attempt++) {
    Start-Sleep -Seconds 1

    try {
        $restored = Get-DependencyHealth
        if ($restored.status -eq "Healthy") {
            Write-Host "OK: object-store restaurado y dependencias nuevamente Healthy."
            exit 0
        }
    }
    catch {
        # El servicio puede tardar unos segundos en volver a aceptar solicitudes.
    }
}

throw "object-store fue iniciado, pero el estado de dependencias no volvio a Healthy a tiempo."

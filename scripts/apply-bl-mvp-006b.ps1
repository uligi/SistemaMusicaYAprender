$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$ComposePath = Join-Path $RepoRoot "compose.yml"
if (-not (Test-Path $ComposePath)) {
    throw "No se encontro compose.yml en la raiz del repositorio."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$compose = [System.IO.File]::ReadAllText($ComposePath, $Utf8NoBom)

$old = "postgres-data:/var/lib/postgresql/data"
$new = "postgres-data:/var/lib/postgresql"

if ($compose.Contains($old)) {
    $compose = $compose.Replace($old, $new)
    [System.IO.File]::WriteAllText($ComposePath, $compose, $Utf8NoBom)
    Write-Host "Corregido compose.yml para PostgreSQL 18."
}
elseif ($compose.Contains($new)) {
    Write-Host "compose.yml ya contiene el montaje correcto de PostgreSQL 18."
}
else {
    throw "No se encontro el montaje esperado de PostgreSQL en compose.yml."
}

$DocPath = Join-Path $RepoRoot "docs\engineering\local-environment\README.md"
if (Test-Path $DocPath) {
    $doc = [System.IO.File]::ReadAllText($DocPath, $Utf8NoBom)
    $marker = "## PostgreSQL 18 y persistencia"
    if (-not $doc.Contains($marker)) {
        $doc += @"

## PostgreSQL 18 y persistencia

PostgreSQL 18 usa directorios de datos específicos por versión dentro de `/var/lib/postgresql`.
Por ello el volumen local se monta en `/var/lib/postgresql`, no en `/var/lib/postgresql/data`.
Este diseño también evita cruzar límites de montaje durante futuras operaciones de `pg_upgrade`.
"@
        [System.IO.File]::WriteAllText($DocPath, $doc, $Utf8NoBom)
    }
}

Write-Host ""
Write-Host "Deteniendo el entorno local para recrear SOLO PostgreSQL..."
docker compose down
Assert-LastExitCode "docker compose down"

$volumeIds = @(docker volume ls `
    --filter "label=com.docker.compose.project=musica-aprender-local" `
    --filter "label=com.docker.compose.volume=postgres-data" `
    --quiet)

if ($LASTEXITCODE -ne 0) {
    throw "No se pudo consultar el volumen local de PostgreSQL."
}

foreach ($volumeId in $volumeIds) {
    if (-not [string]::IsNullOrWhiteSpace($volumeId)) {
        Write-Host "Eliminando volumen PostgreSQL de desarrollo: $volumeId"
        docker volume rm $volumeId
        Assert-LastExitCode "Eliminacion del volumen PostgreSQL"
    }
}

docker compose config --quiet
Assert-LastExitCode "Validacion de compose.yml"

Write-Host ""
Write-Host "OK: BL-MVP-006B aplicado."
Write-Host "Se elimino unicamente el volumen local de PostgreSQL si existia."
Write-Host "Los volumenes de MinIO y Mailpit se conservaron."
Write-Host "Ahora ejecute: .\scripts\local\start.ps1"

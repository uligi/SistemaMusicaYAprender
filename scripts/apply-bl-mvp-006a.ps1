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

$old = "quay.io/minio/minio:RELEASE.2025-10-15T17-29-55Z"
$new = "quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z"

if ($compose.Contains($old)) {
    $compose = $compose.Replace($old, $new)
    [System.IO.File]::WriteAllText($ComposePath, $compose, $Utf8NoBom)
    Write-Host "Corregido compose.yml: imagen MinIO actualizada."
}
elseif ($compose.Contains($new)) {
    Write-Host "compose.yml ya contiene la imagen MinIO corregida."
}
else {
    throw "No se encontro ni la imagen anterior ni la imagen corregida de MinIO en compose.yml."
}

$DocPath = Join-Path $RepoRoot "docs\engineering\local-environment\README.md"
if (Test-Path $DocPath) {
    $doc = [System.IO.File]::ReadAllText($DocPath, $Utf8NoBom)
    $doc = $doc.Replace(
        "MinIO: `RELEASE.2025-10-15T17-29-55Z`, únicamente como S3-compatible de desarrollo.",
        "MinIO: `RELEASE.2025-04-22T22-12-26Z`, versión comunitaria usada únicamente como S3-compatible de desarrollo."
    )
    [System.IO.File]::WriteAllText($DocPath, $doc, $Utf8NoBom)
}

Write-Host "Validando que la imagen exista..."
docker pull quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z
Assert-LastExitCode "Descarga de MinIO"

Write-Host "Validando Docker Compose..."
docker compose config --quiet
Assert-LastExitCode "Validacion de compose.yml"

Write-Host ""
Write-Host "OK: BL-MVP-006A aplicado."
Write-Host "Ahora ejecute: .\scripts\local\start.ps1"

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$files = @(
    "BL-MVP-006_README.md",
    "docs\engineering\local-environment\README.md"
)

foreach ($relative in $files) {
    $path = Join-Path $RepoRoot $relative

    if (-not (Test-Path $path)) {
        throw "No se encontro el archivo esperado: $relative"
    }

    $content = [System.IO.File]::ReadAllText($path, $Utf8NoBom)

    # Las marcas filecite son referencias internas de ChatGPT y no deben vivir en el repositorio.
    $content = [regex]::Replace($content, "\s*filecite[^]+", "")

    # La documentación debe reflejar la imagen que realmente usa compose.yml.
    $content = $content.Replace(
        "MinIO: `RELEASE.2025-10-15T17-29-55Z`, únicamente como S3-compatible de desarrollo.",
        "MinIO: `RELEASE.2025-04-22T22-12-26Z`, usado únicamente como S3-compatible de desarrollo."
    )

    [System.IO.File]::WriteAllText($path, $content.TrimEnd() + "`n", $Utf8NoBom)
    Write-Host "Corregido: $relative"
}

$composePath = Join-Path $RepoRoot "compose.yml"
$compose = [System.IO.File]::ReadAllText($composePath, $Utf8NoBom)

if (-not $compose.Contains("quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z")) {
    throw "compose.yml no contiene la imagen MinIO esperada."
}

npm.cmd exec -- prettier BL-MVP-006_README.md docs/engineering/local-environment/README.md --write
if ($LASTEXITCODE -ne 0) {
    throw "Prettier fallo con codigo de salida $LASTEXITCODE."
}

npm.cmd run format:check
if ($LASTEXITCODE -ne 0) {
    throw "La verificacion de formato fallo con codigo de salida $LASTEXITCODE."
}

Write-Host ""
Write-Host "OK: BL-MVP-006C limpio la documentacion y la alinea con compose.yml."

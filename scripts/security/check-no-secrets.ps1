$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$trackedFiles = @(git ls-files)
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo obtener la lista de archivos rastreados por Git."
}

$forbiddenTracked = @(
    $trackedFiles | Where-Object {
        $_ -match '^secrets/' -or
        ($_ -match '(^|/)\.env($|\.)' -and $_ -ne '.env.example')
    }
)

if ($forbiddenTracked.Count -gt 0) {
    throw "Git rastrea archivos de secretos/ambiente prohibidos: $($forbiddenTracked -join ', ')"
}

$textExtensions = @(
    ".cs", ".ts", ".tsx", ".js", ".json", ".yml", ".yaml",
    ".md", ".ps1", ".sh", ".sql", ".props", ".csproj", ".xml",
    ".conf", ".txt", ".example"
)

# Patrones genericos. No incluimos literales de credenciales heredadas porque el
# propio verificador terminaria detectando su codigo fuente como falso positivo.
$patterns = @(
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'github_pat_[A-Za-z0-9_]{20,}',
    'gh[pousr]_[A-Za-z0-9]{20,}',
    'AKIA[0-9A-Z]{16}',
    'sk-[A-Za-z0-9_-]{24,}'
)

# Si existen secretos locales, sus VALORES reales se agregan en memoria a la
# busqueda. De esta forma comprobamos filtraciones sin escribirlos en el repo.
$localSecretDirectory = Join-Path $Root "secrets\local"
$runtimeForbiddenValues = @()

if (Test-Path $localSecretDirectory) {
    Get-ChildItem $localSecretDirectory -File | ForEach-Object {
        $value = [System.IO.File]::ReadAllText($_.FullName).Trim()

        if ($value.Length -ge 16) {
            $runtimeForbiddenValues += $value
        }
    }
}

foreach ($file in $trackedFiles) {
    if (-not (Test-Path $file -PathType Leaf)) {
        continue
    }

    $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
    $leaf = [System.IO.Path]::GetFileName($file)

    if ($extension -notin $textExtensions -and $leaf -notin @(".env.example", "Dockerfile")) {
        continue
    }

    try {
        $content = [System.IO.File]::ReadAllText(
            (Join-Path $Root $file),
            [System.Text.Encoding]::UTF8)
    }
    catch {
        continue
    }

    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            throw "Posible secreto o credencial prohibida en archivo rastreado: $file"
        }
    }

    foreach ($forbiddenValue in $runtimeForbiddenValues) {
        if ($content.Contains($forbiddenValue)) {
            throw "Un valor del secret store local aparece en archivo rastreado: $file"
        }
    }
}

if (Test-Path ".env.example") {
    foreach ($line in Get-Content ".env.example") {
        if ($line -match '^\s*([A-Za-z0-9_]*(PASSWORD|SECRET|TOKEN|PRIVATE_KEY|ACCESS_KEY)[A-Za-z0-9_]*)\s*=\s*(.+)\s*$') {
            throw ".env.example contiene un valor para una clave sensible: $($matches[1])"
        }
    }
}

Write-Host "OK: no hay secretos rastreados ni valores del secret store local en el repositorio."

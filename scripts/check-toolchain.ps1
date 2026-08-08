$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

$dotnetVersion = (& dotnet --version).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "No se pudo detectar .NET SDK."
}

$nodeVersion = (& node --version).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "No se pudo detectar Node.js."
}

$npmVersion = (& npm.cmd --version).Trim()
if ($LASTEXITCODE -ne 0) {
    Fail "No se pudo detectar npm."
}

if ($nodeVersion -ne "v24.18.0") {
    Fail "Se requiere Node.js v24.18.0. Encontrado: $nodeVersion"
}

if ($npmVersion -ne "11.16.0") {
    Fail "Se requiere npm 11.16.0. Encontrado: $npmVersion"
}

if (-not $dotnetVersion.StartsWith("9.0.")) {
    Fail "Se requiere .NET SDK 9.0.x. Encontrado: $dotnetVersion"
}

Write-Host "Toolchain valida: .NET $dotnetVersion | Node $nodeVersion | npm $npmVersion"

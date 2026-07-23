$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

$dotnetVersion = (& dotnet --version).Trim()
if ($dotnetVersion -notmatch '^9\.0\.3\d{2}$') {
    Fail "Se requiere un SDK .NET de la banda 9.0.3xx. Encontrado: $dotnetVersion"
}

$nodeVersion = (& node --version).Trim()
if ($nodeVersion -ne 'v24.18.0') {
    Fail "Se requiere Node.js v24.18.0. Encontrado: $nodeVersion"
}

$npmVersion = (& npm --version).Trim()
if ($npmVersion -ne '11.16.0') {
    Fail "Se requiere npm 11.16.0. Encontrado: $npmVersion"
}

Write-Host "Toolchain válida: .NET $dotnetVersion | Node $nodeVersion | npm $npmVersion"

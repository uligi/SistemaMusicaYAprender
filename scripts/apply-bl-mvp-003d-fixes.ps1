$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$programPath = Join-Path $RepoRoot "apps\worker\Program.cs"
if (-not (Test-Path $programPath)) {
    throw "No se encontro apps\worker\Program.cs."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$content = @'
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using MusicaAprender.Worker.Workers;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddHostedService<HeartbeatWorker>();

var host = builder.Build();
await host.RunAsync();
'@

$content = ($content -replace "`r`n", "`n") -replace "`r", "`n"
if (-not $content.EndsWith("`n")) {
    $content += "`n"
}

[System.IO.File]::WriteAllText($programPath, $content, $Utf8NoBom)

Write-Host "Corregido: apps\worker\Program.cs"
Write-Host " - Microsoft.Extensions.Hosting"
Write-Host " - Microsoft.Extensions.DependencyInjection"
Write-Host " - UTF-8 sin BOM"
Write-Host " - finales de linea LF"
Write-Host ""
Write-Host "Ahora ejecute: .\scripts\check-quality.ps1"

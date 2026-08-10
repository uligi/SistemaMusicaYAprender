$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projects = Get-ChildItem (Join-Path $repoRoot "src/Modules") -Filter *.csproj -Recurse
$violations = @()

foreach ($project in $projects) {
    [xml]$xml = Get-Content $project.FullName -Raw
    $references = @($xml.SelectNodes("//*[local-name()='ProjectReference']"))

    foreach ($reference in $references) {
        $include = $reference.GetAttribute("Include")
        if ([string]::IsNullOrWhiteSpace($include)) {
            continue
        }

        $normalized = $include.Replace("\", "/")
        if ($normalized -match "/Modules/") {
            $relative = [System.IO.Path]::GetRelativePath($repoRoot, $project.FullName)
            $violations += "$relative -> $include"
        }
    }
}

if ($violations.Count -gt 0) {
    throw ("Se detectaron referencias directas entre modulos:`n- " + ($violations -join "`n- "))
}

Write-Host "OK: no existen ProjectReference directos entre modulos."

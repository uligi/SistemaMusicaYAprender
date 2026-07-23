$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projects = Get-ChildItem (Join-Path $repoRoot "src/Modules") -Filter *.csproj -Recurse
$violations = @()

foreach ($project in $projects) {
    [xml]$xml = Get-Content $project.FullName
    $references = $xml.Project.ItemGroup.ProjectReference

    foreach ($reference in $references) {
        $normalized = $reference.Include.Replace("\\", "/")
        if ($normalized -match "/Modules/") {
            $relative = [System.IO.Path]::GetRelativePath($repoRoot, $project.FullName)
            $violations += "$relative -> $($reference.Include)"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Error ("Se detectaron referencias directas entre módulos:`n- " + ($violations -join "`n- "))
}

Write-Host "OK: no existen ProjectReference directos entre módulos."

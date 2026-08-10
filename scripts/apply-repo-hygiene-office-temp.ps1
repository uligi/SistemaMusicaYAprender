[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "77d182bd75b7ac74e2021cc305090ddaa2d9183c"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

$currentBranch = (git branch --show-current).Trim()
Assert-LastExitCode "Consulta de rama"
if ($currentBranch -ne "main") {
    throw "La limpieza debe aplicarse sobre main. Rama actual: '$currentBranch'."
}

$currentHead = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Consulta de HEAD"
if ($currentHead -ne $ExpectedHead) {
    throw "Base inesperada. Se esperaba $ExpectedHead y HEAD es $currentHead."
}

git diff --cached --quiet
Assert-LastExitCode "Comprobacion de indice sin staging previo"

$tempRelative = "sistema de musica/~`$cklog_Implementacion_MVP.docx"
$tempPath = Join-Path $RepoRoot $tempRelative

$tracked = @(git ls-files -- "sistema de musica/~`$cklog_Implementacion_MVP.docx")
Assert-LastExitCode "Consulta de seguimiento del temporal Office"

if ($tracked.Count -eq 0) {
    Write-Host "INFO: el temporal Office ya no esta rastreado."
}
elseif (Test-Path $tempPath -PathType Leaf) {
    Remove-Item -LiteralPath $tempPath -Force
    Write-Host "OK: temporal Office eliminado del working tree; la eliminacion queda sin staging."
}
else {
    Write-Host "OK: el temporal Office ya no existe localmente; Git registrara su eliminacion."
}

$ignorePath = Join-Path $RepoRoot ".gitignore"
$ignoreContent = [System.IO.File]::ReadAllText($ignorePath, [System.Text.Encoding]::UTF8)
if ($ignoreContent -notmatch '(?m)^~\$\*\.docx$') {
    throw ".gitignore no contiene la regla esperada ~$*.docx. Extraiga de nuevo el paquete."
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short --untracked-files=all
Assert-LastExitCode "git status"

Write-Host ""
Write-Host "OK: limpieza de temporal Office preparada."
Write-Host "No se ejecuto git add, commit ni push."

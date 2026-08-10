[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    $gitCommand = Get-Command "git.exe" -ErrorAction Stop
    $gitDirectory = Split-Path -Parent $gitCommand.Source
    $candidates = @(
        (Join-Path $gitDirectory "..\bin\bash.exe"),
        (Join-Path $gitDirectory "..\usr\bin\bash.exe"),
        (Join-Path $gitDirectory "bash.exe"),
        (Join-Path $gitDirectory "..\..\usr\bin\bash.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Git Bash no esta disponible junto a git.exe. Repare Git for Windows y vuelva a ejecutar el instalador."
}

$TargetRelative = "scripts/ci/identity/verify-personal-login.sh"
$Target = Join-Path $RepoRoot $TargetRelative

Write-Host "BL-MVP-026E: corrigiendo la validacion de BL-MVP-026D para usar Git Bash real..."

if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
    throw "No se encontro $TargetRelative."
}

$content = [System.IO.File]::ReadAllText($Target, [System.Text.Encoding]::UTF8)

$oldAssert = @'
assert_contains_ci() {
  local check_name="$1"
  local expected="$2"
  local actual="$3"

  if ! grep -F -i -q -- "$expected" <<<"$actual"; then
    fail_check "$check_name no encontro '$expected'."
  fi
}
'@

$newAssert = @'
assert_contains_ci() {
  local check_name="$1"
  local expected="$2"
  local actual="$3"
  local expected_lower="${expected,,}"
  local actual_lower="${actual,,}"

  if [[ "$actual_lower" != *"$expected_lower"* ]]; then
    fail_check "$check_name no encontro '$expected'."
  fi
}
'@

$oldDomain = @'
  if grep -i -q -- '; domain=' <<<"$header_line"; then
    fail_check "$cookie_name no puede incluir Domain con el prefijo __Host-."
  fi
'@

$newDomain = @'
  local header_lower="${header_line,,}"
  if [[ "$header_lower" == *"; domain="* ]]; then
    fail_check "$cookie_name no puede incluir Domain con el prefijo __Host-."
  fi
'@

$alreadyPatched =
    $content.Contains($newAssert) -and
    $content.Contains($newDomain)

if ($alreadyPatched) {
    Write-Host "OK: cambio funcional de BL-MVP-026D ya presente."
}
else {
    if (-not $content.Contains($oldAssert)) {
        throw "No se encontro el bloque exacto assert_contains_ci esperado. No se modifico ningun archivo."
    }

    if (-not $content.Contains($oldDomain)) {
        throw "No se encontro el bloque exacto de comprobacion Domain esperado. No se modifico ningun archivo."
    }

    $updated = $content.Replace($oldAssert, $newAssert).Replace($oldDomain, $newDomain)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Target, $updated, $utf8NoBom)
    Write-Host "OK: cambio funcional de BL-MVP-026D aplicado por BL-MVP-026E."
}

$BashPath = Resolve-GitBash
Write-Host "Git Bash: $BashPath"

& $BashPath -n "./$TargetRelative"
Assert-LastExitCode "bash -n del verificador"
Write-Host "OK: bash -n aprobado con Git Bash."

git diff --check -- $TargetRelative
Assert-LastExitCode "git diff --check de BL-MVP-026D/026E"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Diff funcional:"
git diff -- $TargetRelative

Write-Host ""
Write-Host "OK: BL-MVP-026E validado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-026.ps1"

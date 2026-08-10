$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$TargetRelative = 'scripts/ci/identity/verify-personal-login.sh'
$Target = Join-Path $RepoRoot $TargetRelative

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

Write-Host "BL-MVP-026D: corrigiendo falso RED del verificador de cookies..."

if (-not (Test-Path -LiteralPath $Target)) {
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
    Write-Host "OK: BL-MVP-026D ya estaba aplicado; se validara el resultado."
}
else {
    if (-not $content.Contains($oldAssert)) {
        throw "No se encontro el bloque exacto assert_contains_ci esperado. No se modifico ningun archivo."
    }

    if (-not $content.Contains($oldDomain)) {
        throw "No se encontro el bloque exacto de comprobacion Domain esperado. No se modifico ningun archivo."
    }

    $updated = $content.Replace($oldAssert, $newAssert).Replace($oldDomain, $newDomain)

    if ($updated -eq $content) {
        throw "BL-MVP-026D no produjo cambios."
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Target, $updated, $utf8NoBom)
    Write-Host "OK: BL-MVP-026D aplicado sobre $TargetRelative."
}

if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    throw "bash no esta disponible en PATH."
}

& bash -n "./$TargetRelative"
Assert-LastExitCode "bash -n del verificador"
Write-Host "OK: bash -n aprobado."

git diff --check -- $TargetRelative
Assert-LastExitCode "git diff --check de BL-MVP-026D"
Write-Host "OK: git diff --check aprobado."

Write-Host ""
Write-Host "Inventario del correctivo:"
Write-Host "  M $TargetRelative"
Write-Host "  + scripts/apply-bl-mvp-026d.ps1"
Write-Host "  + README/BL-MVP-026D_README.md"
Write-Host "  + INSTRUCCIONES_INSTALACION_MVP_F1_BL-MVP-026D.md"

Write-Host ""
Write-Host "Diff funcional:"
git diff -- $TargetRelative

Write-Host ""
Write-Host "OK: BL-MVP-026D instalado."
Write-Host "No se ejecuto git add, commit ni push."
Write-Host "Siguiente paso obligatorio:"
Write-Host "  .\scripts\apply-bl-mvp-026.ps1"

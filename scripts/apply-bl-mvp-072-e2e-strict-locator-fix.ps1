param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "8181d2820edd50e9abd4cada30a272c6184d8040"
$Target = "tests/E2ETests/study-session-start.spec.ts"

function Fail([string]$Message) {
    throw "BL-MVP-072 E2E strict-locator fix: $Message"
}

function Normalize-Lf([string]$Value) {
    return ($Value -replace "`r`n", "`n" -replace "`r", "`n")
}

function Write-Utf8Lf([string]$Path, [string]$Content) {
    $normalized = Normalize-Lf $Content
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8)
}

$root = (Resolve-Path $RepoRoot).Path
Set-Location $root

$branch = (& git.exe branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    Fail "se requiere branch main; actual='$branch'."
}

$head = (& git.exe rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $ExpectedHead) {
    Fail "HEAD esperado $ExpectedHead; actual=$head."
}

$full = Join-Path $root $Target
if (-not (Test-Path $full -PathType Leaf)) {
    Fail "no existe $Target."
}

$text = Normalize-Lf ([System.IO.File]::ReadAllText($full))

$old = @'
    await expect(page.getByText('Todavía no hay una práctica publicada')).toBeVisible();
'@

$new = @'
    await expect(
      page.getByRole('heading', {
        name: 'Todavía no hay una práctica publicada',
        exact: true,
      }),
    ).toBeVisible();
'@

if ($text.Contains($new)) {
    Write-Host "OK: locator semántico ya estaba aplicado."
}
elseif ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
    Write-Utf8Lf $full $text
    Write-Host "OK: assertion ambigua reemplazada por heading exacto."
}
else {
    Fail "no se encontró la assertion esperada en $Target."
}

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detectó problemas."
}

Write-Host ""
Write-Host "OK: fix E2E BL-MVP-072 aplicado."
Write-Host "- No cambia producto, API, DB ni UX."
Write-Host "- El test ahora identifica el heading de bloqueo de forma semántica y exacta."
Write-Host "No se ejecutó git add, commit ni push."
Write-Host "Este .ps1 es temporal y debe eliminarse antes del staging."

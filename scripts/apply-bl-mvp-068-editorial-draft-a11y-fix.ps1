param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "1c47e5055fff3ecd8d8dcfa44f93ce94eb055ac3"

function Fail([string]$Message) {
    throw "BL-MVP-068 DRAFT a11y fix: $Message"
}

function Normalize-Lf([string]$Value) {
    return ($Value -replace "`r`n", "`n" -replace "`r", "`n")
}

function Write-Utf8Lf([string]$RelativePath, [string]$Content) {
    $full = Join-Path $script:Root $RelativePath
    $normalized = Normalize-Lf $Content
    if (-not $normalized.EndsWith("`n")) {
        $normalized += "`n"
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($full, $normalized, $utf8)
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$branch = (& git.exe branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    Fail "se requiere branch main; actual='$branch'."
}

$head = (& git.exe rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $ExpectedHead) {
    Fail "HEAD esperado $ExpectedHead; actual $head."
}

$path = "apps/web/src/routes/student/ContextualAnalysisPanel.tsx"
$full = Join-Path $script:Root $path
if (-not (Test-Path $full -PathType Leaf)) {
    Fail "no existe $path."
}

$text = Normalize-Lf ([System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8))

$oldStart = @'
  const draftPreview = Boolean(editorialRecordingId);

  return (
    <aside
      className="contextual-analysis"
'@

$newStart = @'
  const draftPreview = Boolean(editorialRecordingId);
  const PanelRoot = draftPreview ? 'div' : 'aside';

  return (
    <PanelRoot
      className="contextual-analysis"
'@

$oldEnd = @'
    </aside>
  );
}
'@

$newEnd = @'
    </PanelRoot>
  );
}
'@

if ($text.Contains($newStart) -and $text.Contains($newEnd)) {
    Write-Host "OK: corrección a11y ya aplicada."
}
else {
    if (-not $text.Contains($oldStart)) {
        Fail "no se encontró el bloque inicial esperado del panel."
    }

    if (-not $text.Contains($oldEnd)) {
        Fail "no se encontró el cierre esperado del panel."
    }

    $text = $text.Replace($oldStart, $newStart)
    $text = $text.Replace($oldEnd, $newEnd)
    Write-Utf8Lf $path $text
    Write-Host "OK: el panel DRAFT deja de ser landmark complementary anidado."
}

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detectó problemas."
}

Write-Host ""
Write-Host "OK: fix a11y BL068 aplicado."
Write-Host "Modo público conserva <aside>; modo editorial DRAFT usa <div> dentro del landmark del preview."
Write-Host "No se ejecutó git add, commit ni push."

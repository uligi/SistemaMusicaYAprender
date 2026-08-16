param(
    [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedHead = "8181d2820edd50e9abd4cada30a272c6184d8040"

function Fail([string]$Message) {
    throw "BL-MVP-072 resume fix: $Message"
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
    Write-Host "OK: $RelativePath"
}

function Replace-ExactBase64(
    [string]$RelativePath,
    [string]$OldBase64,
    [string]$NewBase64,
    [string]$Description
) {
    $full = Join-Path $script:Root $RelativePath
    if (-not (Test-Path $full -PathType Leaf)) {
        Fail "no existe $RelativePath."
    }

    $text = Normalize-Lf ([System.IO.File]::ReadAllText($full))
    $old = Normalize-Lf ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OldBase64)))
    $new = Normalize-Lf ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NewBase64)))

    if ($text.Contains($new)) {
        Write-Host "OK: $Description ya aplicado."
        return
    }

    $count = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($count -ne 1) {
        Fail "se esperaba una coincidencia para $Description en $RelativePath; encontradas=$count."
    }

    Write-Utf8Lf $RelativePath ($text.Replace($old, $new))
    Write-Host "OK: $Description aplicado."
}

$script:Root = (Resolve-Path $RepoRoot).Path
Set-Location $script:Root

$branch = (& git.exe branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    Fail "se requiere branch main; actual='$branch'."
}

$head = (& git.exe rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $ExpectedHead) {
    Fail "HEAD esperado $ExpectedHead; actual=$head."
}

$requiredPartial = @(
    "src/Modules/Learning/Infrastructure/Sessions/StudySessionStartService.cs",
    "apps/api/Endpoints/Learning/StudySessionEndpoints.cs",
    "apps/web/src/routes/student/StudyStartPage.tsx",
    "apps/web/src/routes/student/study-start.css",
    "tests/E2ETests/study-session-start.spec.ts",
    "scripts/ci/learning/verify-study-session-start.sh",
    "README/BL-MVP-072_README.md",
    "docs/engineering/learning/study-session-start.md"
)

foreach ($path in $requiredPartial) {
    if (-not (Test-Path (Join-Path $script:Root $path) -PathType Leaf)) {
        Fail "el apply parcial no dejó el archivo esperado: $path"
    }
}

$program = Normalize-Lf ([System.IO.File]::ReadAllText((Join-Path $script:Root "apps/api/Program.cs")))
foreach ($needle in @(
    "using MusicaAprender.Modules.Learning.Infrastructure.Sessions;",
    "using MusicaAprender.Api.Endpoints.Learning;",
    "builder.Services.AddSingleton<StudySessionStartService>();",
    "app.MapStudySessions();"
)) {
    if (-not $program.Contains($needle)) {
        Fail "Program.cs quedó incompleto; falta: $needle"
    }
}

$studentArea = Normalize-Lf ([System.IO.File]::ReadAllText((Join-Path $script:Root "apps/web/src/routes/student/StudentArea.tsx")))
foreach ($needle in @(
    "import { StudyStartPage } from './StudyStartPage';",
    "if (match.route.id === 'UI-MVP-011')"
)) {
    if (-not $studentArea.Contains($needle)) {
        Fail "StudentArea.tsx quedó incompleto; falta: $needle"
    }
}

Replace-ExactBase64 `
    "apps/web/src/routes/student/EducationalPlayerPage.tsx" `
    "ICAgICAgPEFwcExpbmsgaHJlZj17YC9jYW5jaW9uZXMvJHtlbmNvZGVVUklDb21wb25lbnQoc2x1Zyl9YH0+Vm9sdmVyIGEgbGEgZmljaGEgcMO6YmxpY2E8L0FwcExpbms+Cg==" `
    "ICAgICAgPG5hdiBhcmlhLWxhYmVsPSJBY2Npb25lcyBkZSBsYSBjYW5jacOzbiI+CiAgICAgICAgPEFwcExpbmsgaHJlZj17YC9jYW5jaW9uZXMvJHtlbmNvZGVVUklDb21wb25lbnQoc2x1Zyl9YH0+Vm9sdmVyIGEgbGEgZmljaGEgcMO6YmxpY2E8L0FwcExpbms+eycgwrcgJ30KICAgICAgICA8QXBwTGluayBocmVmPXtgL2VzdHVkaWFyLyR7ZW5jb2RlVVJJQ29tcG9uZW50KHNsdWcpfWB9PlByYWN0aWNhciBlc3RhIGNhbmNpw7NuPC9BcHBMaW5rPgogICAgICA8L25hdj4K" `
    "entrada visible a práctica"

Replace-ExactBase64 `
    ".github/workflows/ci.yml" `
    "ICAgICAgLSBuYW1lOiBWZXJpZnkgZmlsbC1ibGFuayBEUkFGVCBhdXRob3JpbmcKICAgICAgICBzaGVsbDogYmFzaAogICAgICAgIGVudjoKICAgICAgICAgIFBHSE9TVDogMTI3LjAuMC4xCiAgICAgICAgICBQR1BPUlQ6ICc1NDMyJwogICAgICAgICAgUEdVU0VSOiBwb3N0Z3JlcwogICAgICAgICAgUEdQQVNTV09SRDogcG9zdGdyZXMKICAgICAgICAgIFBHREFUQUJBU0U6IG11c2ljYV9hcHJlbmRlcl9jaQogICAgICAgICAgQkwwNzFfVVNFX0RPQ0tFUl9QU1FMOiAnZmFsc2UnCiAgICAgICAgcnVuOiBiYXNoIHNjcmlwdHMvY2kvbGVhcm5pbmcvdmVyaWZ5LWZpbGwtYmxhbmstZXhlcmNpc2UtYXV0aG9yaW5nLnNoCgo=" `
    "ICAgICAgLSBuYW1lOiBWZXJpZnkgZmlsbC1ibGFuayBEUkFGVCBhdXRob3JpbmcKICAgICAgICBzaGVsbDogYmFzaAogICAgICAgIGVudjoKICAgICAgICAgIFBHSE9TVDogMTI3LjAuMC4xCiAgICAgICAgICBQR1BPUlQ6ICc1NDMyJwogICAgICAgICAgUEdVU0VSOiBwb3N0Z3JlcwogICAgICAgICAgUEdQQVNTV09SRDogcG9zdGdyZXMKICAgICAgICAgIFBHREFUQUJBU0U6IG11c2ljYV9hcHJlbmRlcl9jaQogICAgICAgICAgQkwwNzFfVVNFX0RPQ0tFUl9QU1FMOiAnZmFsc2UnCiAgICAgICAgcnVuOiBiYXNoIHNjcmlwdHMvY2kvbGVhcm5pbmcvdmVyaWZ5LWZpbGwtYmxhbmstZXhlcmNpc2UtYXV0aG9yaW5nLnNoCgogICAgICAtIG5hbWU6IFZlcmlmeSBwcml2YXRlIHB1Ymxpc2hlZCBzdHVkeS1zZXNzaW9uIHN0YXJ0CiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDcyX1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2xlYXJuaW5nL3ZlcmlmeS1zdHVkeS1zZXNzaW9uLXN0YXJ0LnNoCgo=" `
    "gate CI BL072"

& git.exe diff --check
if ($LASTEXITCODE -ne 0) {
    Fail "git diff --check detectó problemas."
}

Write-Host ""
Write-Host "OK: BL-MVP-072 reanudado después del fallo de interpolación PowerShell."
Write-Host "- EducationalPlayerPage enlaza a UI-MVP-011."
Write-Host "- CI incluye verify-study-session-start.sh."
Write-Host "- El apply parcial previo fue validado antes de continuar."
Write-Host "No se ejecutó git add, commit ni push."
Write-Host "Ambos .ps1 temporales deben eliminarse antes del staging."

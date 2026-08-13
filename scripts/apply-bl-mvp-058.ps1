[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "dc7f19caecc43f770c6fbf55ef750cbd529d9a84"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/student/StudentArea.tsx",
    "src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-058.md",
    "README/BL-MVP-058_README.md",
    "apps/web/src/integrations/youtube/YouTubeIframeAdapter.tsx",
    "apps/web/src/integrations/youtube/youtube-iframe-adapter.css",
    "apps/web/src/routes/student/EducationalPlayerPage.tsx",
    "apps/web/src/routes/student/educational-player.css",
    "docs/engineering/integrations/youtube-iframe-adapter.md",
    "scripts/apply-bl-mvp-058.ps1",
    "scripts/ci/content/verify-youtube-iframe-adapter.sh",
    "tests/E2ETests/youtube-iframe-adapter.spec.ts"
)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Decode-Utf8Base64([string]$Value) {
    return [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($Value))
}

function Read-Normalized([string]$RelativePath) {
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta $RelativePath."
    }

    return ([System.IO.File]::ReadAllText(
        $path,
        [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8NoBomLf([string]$RelativePath, [string]$Content) {
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoRoot $RelativePath),
        $Content.Replace("`r`n", "`n").Replace("`r", "`n"),
        [System.Text.UTF8Encoding]::new($false))
}

function Replace-ExactOnce(
    [string]$RelativePath,
    [string]$OldText,
    [string]$NewText,
    [string]$AlreadyMarker,
    [string]$Description) {

    $content = Read-Normalized $RelativePath

    if ($content.Contains($AlreadyMarker)) {
        Write-Host "OK: $Description ya estaba aplicado."
        return
    }

    $first = $content.IndexOf($OldText, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "No se encontro el bloque esperado para $Description en $RelativePath."
    }

    $second = $content.IndexOf(
        $OldText,
        $first + $OldText.Length,
        [System.StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "El bloque de $Description aparece mas de una vez en $RelativePath."
    }

    $updated = $content.Remove($first, $OldText.Length).Insert($first, $NewText)
    Write-Utf8NoBomLf $RelativePath $updated
    Write-Host "OK: $Description aplicado."
}

function Restore-GeneratedTypeScriptState {
    $relativePath = "apps/web/tsconfig.app.tsbuildinfo"
    git ls-files --error-unmatch -- $relativePath *> $null
    if ($LASTEXITCODE -ne 0) {
        $global:LASTEXITCODE = 0
        return
    }

    $status = git status --porcelain=v1 -- $relativePath
    if ($status) {
        git restore --worktree -- $relativePath
        Assert-LastExitCode "Restaurar tsbuildinfo"
        Write-Host "Restaurado $relativePath por ser salida incremental rastreada."
    }
}

function Get-ChangedPaths {
    $tracked = @(git diff --name-only)
    Assert-LastExitCode "Leer cambios tracked"
    $untracked = @(git ls-files --others --exclude-standard)
    Assert-LastExitCode "Leer cambios untracked"

    return @(
        $tracked + $untracked |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

function Assert-InventorySubset {
    $allowed = @{}
    foreach ($path in $PermanentPaths) {
        $allowed[$path] = $true
    }

    foreach ($path in Get-ChangedPaths) {
        if (-not $allowed.ContainsKey($path)) {
            throw "Ruta fuera del inventario BL-MVP-058: $path"
        }
    }
}

Write-Host "BL-MVP-058: adaptador aislado de YouTube IFrame..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"
if ($head -cne $ExpectedBase) {
    throw "BL-MVP-058 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"
if ($branch -cne "main") {
    throw "BL-MVP-058 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"
if ($staged.Count -gt 0) {
    throw "BL-MVP-058 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in @(
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-058.md",
    "README/BL-MVP-058_README.md",
    "apps/web/src/integrations/youtube/YouTubeIframeAdapter.tsx",
    "apps/web/src/integrations/youtube/youtube-iframe-adapter.css",
    "apps/web/src/routes/student/EducationalPlayerPage.tsx",
    "apps/web/src/routes/student/educational-player.css",
    "docs/engineering/integrations/youtube-iframe-adapter.md",
    "scripts/ci/content/verify-youtube-iframe-adapter.sh",
    "tests/E2ETests/youtube-iframe-adapter.spec.ts"
)) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}


$old1 = Decode-Utf8Base64 'aW1wb3J0IHsgUm91dGVQbGFjZWhvbGRlciB9IGZyb20gJy4uL3NoYXJlZC9Sb3V0ZVBsYWNlaG9sZGVyJzsKaW1wb3J0IHsgUGVyc29uYWxQcmVmZXJlbmNlc1BhZ2UgfSBmcm9tICcuL1BlcnNvbmFsUHJlZmVyZW5jZXNQYWdlJzsKaW1wb3J0ICcuL3N0dWRlbnQtYXJlYS5jc3MnOw=='
$new1 = Decode-Utf8Base64 'aW1wb3J0IHsgUm91dGVQbGFjZWhvbGRlciB9IGZyb20gJy4uL3NoYXJlZC9Sb3V0ZVBsYWNlaG9sZGVyJzsKaW1wb3J0IHsgRWR1Y2F0aW9uYWxQbGF5ZXJQYWdlIH0gZnJvbSAnLi9FZHVjYXRpb25hbFBsYXllclBhZ2UnOwppbXBvcnQgeyBQZXJzb25hbFByZWZlcmVuY2VzUGFnZSB9IGZyb20gJy4vUGVyc29uYWxQcmVmZXJlbmNlc1BhZ2UnOwppbXBvcnQgJy4vc3R1ZGVudC1hcmVhLmNzcyc7'
Replace-ExactOnce 'apps/web/src/routes/student/StudentArea.tsx' $old1 $new1 'EducationalPlayerPage' 'import UI-MVP-009'

$old2 = Decode-Utf8Base64 'ICBpZiAobWF0Y2gucm91dGUuaWQgPT09ICdVSS1NVlAtMDA4JykgewogICAgcmV0dXJuIDxQZXJzb25hbFByZWZlcmVuY2VzUGFnZSAvPjsKICB9CgogIHJldHVybiAo'
$new2 = Decode-Utf8Base64 'ICBpZiAobWF0Y2gucm91dGUuaWQgPT09ICdVSS1NVlAtMDA4JykgewogICAgcmV0dXJuIDxQZXJzb25hbFByZWZlcmVuY2VzUGFnZSAvPjsKICB9CgogIGlmIChtYXRjaC5yb3V0ZS5pZCA9PT0gJ1VJLU1WUC0wMDknKSB7CiAgICByZXR1cm4gPEVkdWNhdGlvbmFsUGxheWVyUGFnZSBzbHVnPXttYXRjaC5wYXJhbXMuc2x1ZyF9IC8+OwogIH0KCiAgcmV0dXJuICg='
Replace-ExactOnce 'apps/web/src/routes/student/StudentArea.tsx' $old2 $new2 'match.route.id === ''UI-MVP-009''' 'ruta UI-MVP-009 al reproductor mínimo'

$old3 = Decode-Utf8Base64 'ICAgIERhdGVUaW1lIEF2YWlsYWJpbGl0eVZhbGlkRnJvbSwKICAgIERhdGVUaW1lPyBBdmFpbGFiaWxpdHlWYWxpZFRvLAogICAgSVJlYWRPbmx5TGlzdDxzdHJpbmc+IEF2YWlsYWJsZUNvbXBvbmVudHMpOw=='
$new3 = Decode-Utf8Base64 'ICAgIERhdGVUaW1lIEF2YWlsYWJpbGl0eVZhbGlkRnJvbSwKICAgIERhdGVUaW1lPyBBdmFpbGFiaWxpdHlWYWxpZFRvLAogICAgSVJlYWRPbmx5TGlzdDxzdHJpbmc+IEF2YWlsYWJsZUNvbXBvbmVudHMsCiAgICBzdHJpbmcgU291cmNlRXh0ZXJuYWxSZWYpOw=='
Replace-ExactOnce 'src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs' $old3 $new3 'string SourceExternalRef' 'referencia exacta de fuente en DTO público'

$old4 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICkgQVMgY29tcG9uZW50X2tpbmRzCiAgICAgICAgICAgIEZST00gZWRpdG9yaWFsLnB1Ymxpc2hlZF9wYWNrYWdlX3Byb2plY3Rpb24gQVMgcHJvamVjdGlvbg=='
$new4 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICkgQVMgY29tcG9uZW50X2tpbmRzLAogICAgICAgICAgICAgICAgc291cmNlLmV4dGVybmFsX3JlZgogICAgICAgICAgICBGUk9NIGVkaXRvcmlhbC5wdWJsaXNoZWRfcGFja2FnZV9wcm9qZWN0aW9uIEFTIHByb2plY3Rpb24='
Replace-ExactOnce 'src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs' $old4 $new4 'source.external_ref
            FROM editorial.published_package_projection' 'selección de referencia YouTube pública'

$old5 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgIHJlYWRlci5HZXREYXRlVGltZSg3KSwKICAgICAgICAgICAgICAgIHJlYWRlci5Jc0RCTnVsbCg4KSA/IG51bGwgOiByZWFkZXIuR2V0RGF0ZVRpbWUoOCksCiAgICAgICAgICAgICAgICByZWFkZXIuR2V0RmllbGRWYWx1ZTxzdHJpbmdbXT4oMTApKSk7'
$new5 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgIHJlYWRlci5HZXREYXRlVGltZSg3KSwKICAgICAgICAgICAgICAgIHJlYWRlci5Jc0RCTnVsbCg4KSA/IG51bGwgOiByZWFkZXIuR2V0RGF0ZVRpbWUoOCksCiAgICAgICAgICAgICAgICByZWFkZXIuR2V0RmllbGRWYWx1ZTxzdHJpbmdbXT4oMTApLAogICAgICAgICAgICAgICAgcmVhZGVyLkdldFN0cmluZygxMSkpKTs='
Replace-ExactOnce 'src/Modules/Catalog/Infrastructure/Search/PublicSongDetailService.cs' $old5 $new5 'reader.GetString(11)' 'materialización de sourceExternalRef'

$old6 = Decode-Utf8Base64 'ICAgICAgLSBuYW1lOiBWZXJpZnkgZWRpdGFibGUgc3luY2hyb25pemF0aW9uIHRpbWVsaW5lCiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDU3X1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXN5bmNocm9uaXphdGlvbi10aW1lbGluZS1lZGl0b3Iuc2gKCiAgICAgIC0gbmFtZTogVmVyaWZ5IGVuY3J5cHRlZCBwcml2YXRlIG9iamVjdCBzdG9yYWdl'
$new6 = Decode-Utf8Base64 'ICAgICAgLSBuYW1lOiBWZXJpZnkgZWRpdGFibGUgc3luY2hyb25pemF0aW9uIHRpbWVsaW5lCiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDU3X1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXN5bmNocm9uaXphdGlvbi10aW1lbGluZS1lZGl0b3Iuc2gKCiAgICAgIC0gbmFtZTogVmVyaWZ5IGlzb2xhdGVkIFlvdVR1YmUgSUZyYW1lIGFkYXB0ZXIKICAgICAgICBzaGVsbDogYmFzaAogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXlvdXR1YmUtaWZyYW1lLWFkYXB0ZXIuc2gKCiAgICAgIC0gbmFtZTogVmVyaWZ5IGVuY3J5cHRlZCBwcml2YXRlIG9iamVjdCBzdG9yYWdl'
Replace-ExactOnce '.github/workflows/ci.yml' $old6 $new6 'Verify isolated YouTube IFrame adapter' 'puerta CI BL-MVP-058'


$old7 = Decode-Utf8Base64 'aW1wb3J0IHsgY3JlYXRlSHR0cENsaWVudCB9IGZyb20gJy4uLy4uL2RhdGEvaHR0cCc7CmltcG9ydCB7CiAgU3luY2hyb25pemF0aW9uVGltZWxpbmVFZGl0b3Is'
$new7 = Decode-Utf8Base64 'aW1wb3J0IHsgY3JlYXRlSHR0cENsaWVudCB9IGZyb20gJy4uLy4uL2RhdGEvaHR0cCc7CmltcG9ydCB7IFlvdVR1YmVJZnJhbWVBZGFwdGVyIH0gZnJvbSAnLi4vLi4vaW50ZWdyYXRpb25zL3lvdXR1YmUvWW91VHViZUlmcmFtZUFkYXB0ZXInOwppbXBvcnQgewogIFN5bmNocm9uaXphdGlvblRpbWVsaW5lRWRpdG9yLA=='
Replace-ExactOnce 'apps/web/src/routes/editorial/SynchronizationStructurePage.tsx' $old7 $new7 'YouTubeIframeAdapter' 'import de previsualización editorial sin publicación'

$old8 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgPC9kbD4KCiAgICAgICAgICAgICAgICAgIHtzb3VyY2UuZHVyYXRpb25NcyA9PT0gbnVsbCA/ICg='
$new8 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgPC9kbD4KCiAgICAgICAgICAgICAgICAgIHtzb3VyY2UucHJvdmlkZXJDb2RlID09PSAnWU9VVFVCRScgPyAoCiAgICAgICAgICAgICAgICAgICAgPGRpdiBjbGFzc05hbWU9InN5bmNocm9uaXphdGlvbi1zdHJ1Y3R1cmVfX2V4dGVybmFsLXByZXZpZXciPgogICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3NOYW1lPSJleWVicm93Ij5CTC1NVlAtMDU4IMK3IFZJU1RBIFBSRVZJQSBFRElUT1JJQUwgwrcgTk8gUFVCTElDQTwvcD4KICAgICAgICAgICAgICAgICAgICAgIDxZb3VUdWJlSWZyYW1lQWRhcHRlcgogICAgICAgICAgICAgICAgICAgICAgICBleHRlcm5hbFJlZj17c291cmNlLmV4dGVybmFsUmVmfQogICAgICAgICAgICAgICAgICAgICAgICB0aXRsZT17YEZ1ZW50ZSBlZGl0b3JpYWwgJHtzb3VyY2UuZXh0ZXJuYWxSZWZ9YH0KICAgICAgICAgICAgICAgICAgICAgIC8+CiAgICAgICAgICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICAgICAgICAgICkgOiBudWxsfQoKICAgICAgICAgICAgICAgICAge3NvdXJjZS5kdXJhdGlvbk1zID09PSBudWxsID8gKA=='
Replace-ExactOnce 'apps/web/src/routes/editorial/SynchronizationStructurePage.tsx' $old8 $new8 'VISTA PREVIA EDITORIAL · NO PUBLICA' 'previsualización editorial de la fuente YouTube'

$old9 = Decode-Utf8Base64 'ICAgICAgPFN0YXRlTWVzc2FnZQogICAgICAgIHN0YXRlPSJVSS1FU1QtMTEiCiAgICAgICAgdGl0bGU9IlNpbmNyb25pemFjacOzbiBlZGl0YWJsZSwgdG9kYXbDrWEgbm8gcHVibGljYWRhIgogICAgICAgIGRlc2NyaXB0aW9uPSJCTC1NVlAtMDU3IGd1YXJkYSByZXZpc2lvbmVzIERSQUZULiBCTC1NVlAtMDU4IGNvbmVjdGFyw6EgZWwgSUZyYW1lIGRlIFlvdVR1YmUgeSBCTC1NVlAtMDU5IHJlc29sdmVyw6EgZWwgc2VndWltaWVudG8gZGUgcmVwcm9kdWNjacOzbi4iCiAgICAgIC8+'
$new9 = Decode-Utf8Base64 'ICAgICAgPFN0YXRlTWVzc2FnZQogICAgICAgIHN0YXRlPSJVSS1FU1QtMTEiCiAgICAgICAgdGl0bGU9IlNpbmNyb25pemFjacOzbiBlZGl0YWJsZSwgdG9kYXbDrWEgbm8gcHVibGljYWRhIgogICAgICAgIGRlc2NyaXB0aW9uPSJCTC1NVlAtMDU3IGd1YXJkYSByZXZpc2lvbmVzIERSQUZULiBCTC1NVlAtMDU4IHBlcm1pdGUgcHJldmlzdWFsaXphciBsYSBmdWVudGUgWW91VHViZSBzaW4gcHVibGljYXI7IEJMLU1WUC0wNTkgcmVzb2x2ZXLDoSBlbCBzZWd1aW1pZW50byBkZSByZXByb2R1Y2Npw7NuLiIKICAgICAgLz4='
Replace-ExactOnce 'apps/web/src/routes/editorial/SynchronizationStructurePage.tsx' $old9 $new9 'BL-MVP-058 permite previsualizar la fuente YouTube sin publicar' 'alcance editorial BL058 sin publicación'



$old10 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgICAgIDxZb3VUdWJlSWZyYW1lQWRhcHRlcgogICAgICAgICAgICAgICAgICAgICAgICBleHRlcm5hbFJlZj17c291cmNlLmV4dGVybmFsUmVmfQogICAgICAgICAgICAgICAgICAgICAgICB0aXRsZT17YEZ1ZW50ZSBlZGl0b3JpYWwgJHtzb3VyY2UuZXh0ZXJuYWxSZWZ9YH0KICAgICAgICAgICAgICAgICAgICAgIC8+'
$new10 = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgICAgIDxZb3VUdWJlSWZyYW1lQWRhcHRlcgogICAgICAgICAgICAgICAgICAgICAgICBleHRlcm5hbFJlZj17c291cmNlLmV4dGVybmFsUmVmfQogICAgICAgICAgICAgICAgICAgICAgICB0aXRsZT17YEZ1ZW50ZSBlZGl0b3JpYWwgJHtzb3VyY2UuZXh0ZXJuYWxSZWZ9YH0KICAgICAgICAgICAgICAgICAgICAgICAgaGVhZGluZ0xldmVsPXs0fQogICAgICAgICAgICAgICAgICAgICAgLz4='
Replace-ExactOnce 'apps/web/src/routes/editorial/SynchronizationStructurePage.tsx' $old10 $new10 'headingLevel={4}' 'jerarquía semántica del adaptador editorial'



$formatTargets = @(
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/student/StudentArea.tsx",
    "apps/web/src/integrations/youtube/YouTubeIframeAdapter.tsx",
    "apps/web/src/integrations/youtube/youtube-iframe-adapter.css",
    "apps/web/src/routes/student/EducationalPlayerPage.tsx",
    "apps/web/src/routes/student/educational-player.css",
    "tests/E2ETests/youtube-iframe-adapter.spec.ts",
    "README/BL-MVP-058_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-058.md",
    "docs/engineering/integrations/youtube-iframe-adapter.md"
)
npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL058"

$bash = $null
foreach ($candidate in @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe"
)) {
    if (Test-Path $candidate -PathType Leaf) {
        $bash = $candidate
        break
    }
}
if ($null -eq $bash) {
    $bashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($null -ne $bashCommand) {
        $bash = $bashCommand.Source
    }
}
if ($null -eq $bash) {
    throw "No se encontro Git Bash real."
}

& $bash -n "scripts/ci/content/verify-youtube-iframe-adapter.sh"
Assert-LastExitCode "bash -n BL058"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL058"

Write-Host "Ejecutando Playwright focal BL043/058..."
npm.cmd run test:e2e -- tests/E2ETests/public-song-detail.spec.ts tests/E2ETests/youtube-iframe-adapter.spec.ts
Assert-LastExitCode "Playwright focal BL058"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-058..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL058"

& $bash "scripts/ci/content/verify-youtube-iframe-adapter.sh"
Assert-LastExitCode "Verificacion estatica BL-MVP-058"

Restore-GeneratedTypeScriptState
Assert-InventorySubset

git diff --check
Assert-LastExitCode "git diff --check BL058"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-058 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-058 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 14 rutas BL-MVP-058."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status
Write-Host ""
Write-Host "OK: BL-MVP-058 instalado y validado localmente."
Write-Host "Incluye carga diferida, privacy host, origin, eventos, controlador aislado y degradacion."
Write-Host "No implementa Data API, descarga audiovisual, motor de sincronizacion BL059 ni publicacion."
Write-Host "PENDIENTE: reinicio normal y revision visual real del borrador en /editorial/canciones/{recordingId}/sincronizacion antes de staging; no publicar."
Write-Host "No se ejecuto git add, commit ni push."

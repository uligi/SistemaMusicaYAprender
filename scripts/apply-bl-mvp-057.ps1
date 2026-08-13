[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipSmoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedBase = "9505acc212a8c8b0313c1d8ec70c36ab70bb5b93"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$PermanentPaths = @(
    ".github/workflows/ci.yml",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-057.md",
    "README/BL-MVP-057_README.md",
    "apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs",
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx",
    "apps/web/src/routes/editorial/synchronization-timeline-editor.css",
    "docs/engineering/content/synchronization-timeline-editor.md",
    "scripts/apply-bl-mvp-057.ps1",
    "scripts/ci/content/verify-synchronization-timeline-editor.sh",
    "src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs",
    "tests/E2ETests/synchronization-timeline-editor.spec.ts"
)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-GitBash {
    foreach ($candidate in @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "No se encontro Git Bash real."
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

function Decode-Utf8Base64([string]$Value) {
    return [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($Value))
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
            throw "Ruta fuera del inventario BL-MVP-057: $path"
        }
    }
}

Write-Host "BL-MVP-057: editor de linea de tiempo y sincronizacion..."

$head = (git rev-parse HEAD).Trim()
Assert-LastExitCode "Leer HEAD"

if ($head -cne $ExpectedBase) {
    throw "BL-MVP-057 requiere HEAD exacto $ExpectedBase y encontro $head."
}

$branch = (git branch --show-current).Trim()
Assert-LastExitCode "Leer rama"

if ($branch -cne "main") {
    throw "BL-MVP-057 debe instalarse desde main."
}

$staged = @(git diff --cached --name-only)
Assert-LastExitCode "Revisar staging"

if ($staged.Count -gt 0) {
    throw "BL-MVP-057 requiere staging vacio."
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

foreach ($required in $PermanentPaths | Where-Object {
    $_ -notin @(
        ".github/workflows/ci.yml",
        "apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs",
        "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
        "src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs"
    )
}) {
    if (-not (Test-Path $required -PathType Leaf)) {
        throw "Falta archivo del paquete: $required"
    }
}

$serviceInputOld = Decode-Utf8Base64 'cHVibGljIHNlYWxlZCByZWNvcmQgQ3JlYXRlVGltaW5nUmV2aXNpb25JbnB1dCgKICAgIEd1aWQgTHlyaWNzUmV2aXNpb25JZCwKICAgIEd1aWQgU291cmNlSWQsCiAgICBsb25nIE9mZnNldE1zLAogICAgTGlzdDxUaW1pbmdMaW5lRHJhZnQ+IExpbmVzKTs='

$serviceInputNew = Decode-Utf8Base64 'cHVibGljIHNlYWxlZCByZWNvcmQgQ3JlYXRlVGltaW5nUmV2aXNpb25JbnB1dCgKICAgIEd1aWQgTHlyaWNzUmV2aXNpb25JZCwKICAgIEd1aWQgU291cmNlSWQsCiAgICBsb25nIE9mZnNldE1zLAogICAgaW50PyBFeHBlY3RlZFJldmlzaW9uTm8sCiAgICBMaXN0PFRpbWluZ0xpbmVEcmFmdD4gTGluZXMpOw=='

Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs" `
    $serviceInputOld `
    $serviceInputNew `
    "int? ExpectedRevisionNo" `
    "version esperada del editor temporal"

$replayOld = Decode-Utf8Base64 'ICAgICAgICBpZiAobGF0ZXN0IGlzIG5vdCBudWxsCiAgICAgICAgICAgICYmIHN0cmluZy5FcXVhbHMoCiAgICAgICAgICAgICAgICBsYXRlc3QuQ2hlY2tzdW1TaGEyNTYsCiAgICAgICAgICAgICAgICBwcmVwYXJlZC5DaGVja3N1bVNoYTI1NiwKICAgICAgICAgICAgICAgIFN0cmluZ0NvbXBhcmlzb24uT3JkaW5hbElnbm9yZUNhc2UpKQogICAgICAgIHsKICAgICAgICAgICAgcmV0dXJuIGxhdGVzdDsKICAgICAgICB9CgogICAgICAgIHZhciByZXZpc2lvbklkID0gR3VpZC5DcmVhdGVWZXJzaW9uNygpOw=='

$replayNew = Decode-Utf8Base64 'ICAgICAgICBpZiAobGF0ZXN0IGlzIG5vdCBudWxsCiAgICAgICAgICAgICYmIHN0cmluZy5FcXVhbHMoCiAgICAgICAgICAgICAgICBsYXRlc3QuQ2hlY2tzdW1TaGEyNTYsCiAgICAgICAgICAgICAgICBwcmVwYXJlZC5DaGVja3N1bVNoYTI1NiwKICAgICAgICAgICAgICAgIFN0cmluZ0NvbXBhcmlzb24uT3JkaW5hbElnbm9yZUNhc2UpKQogICAgICAgIHsKICAgICAgICAgICAgcmV0dXJuIGxhdGVzdDsKICAgICAgICB9CgogICAgICAgIGlmICgobGF0ZXN0Py5SZXZpc2lvbk5vKSAhPSBpbnB1dC5FeHBlY3RlZFJldmlzaW9uTm8pCiAgICAgICAgewogICAgICAgICAgICB0aHJvdyBuZXcgVGltaW5nQWRtaW5pc3RyYXRpb25FeGNlcHRpb24oCiAgICAgICAgICAgICAgICAiY29udGVudC50aW1pbmcucmV2aXNpb24uY29uZmxpY3QiLAogICAgICAgICAgICAgICAgIkxhIHNpbmNyb25pemFjacOzbiBjYW1iacOzIGVuIGVsIHNlcnZpZG9yIGRlc2RlIHF1ZSBhYnJpc3RlIGVzdGUgYm9ycmFkb3IuIENvbnNlcnZhIHR1cyBjYW1iaW9zIHkgY29tcGFyYSBhbnRlcyBkZSB2b2x2ZXIgYSBndWFyZGFyLiIpOwogICAgICAgIH0KCiAgICAgICAgdmFyIHJldmlzaW9uSWQgPSBHdWlkLkNyZWF0ZVZlcnNpb243KCk7'

Replace-ExactOnce `
    "src/Modules/Content/Infrastructure/Administration/TimingRevisionAdministrationService.cs" `
    $replayOld `
    $replayNew `
    "content.timing.revision.conflict" `
    "conflicto de revision temporal"

$endpointStatusOld = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICJjb250ZW50LnRpbWluZy5zb3VyY2UtZHVyYXRpb24ucmVxdWlyZWQiID0+CiAgICAgICAgICAgICAgICAgICAgU3RhdHVzQ29kZXMuU3RhdHVzNDA5Q29uZmxpY3QsCiAgICAgICAgICAgICAgICBfID0+'

$endpointStatusNew = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICJjb250ZW50LnRpbWluZy5zb3VyY2UtZHVyYXRpb24ucmVxdWlyZWQiID0+CiAgICAgICAgICAgICAgICAgICAgU3RhdHVzQ29kZXMuU3RhdHVzNDA5Q29uZmxpY3QsCiAgICAgICAgICAgICAgICAiY29udGVudC50aW1pbmcucmV2aXNpb24uY29uZmxpY3QiID0+CiAgICAgICAgICAgICAgICAgICAgU3RhdHVzQ29kZXMuU3RhdHVzNDA5Q29uZmxpY3QsCiAgICAgICAgICAgICAgICBfID0+'

Replace-ExactOnce `
    "apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs" `
    $endpointStatusOld `
    $endpointStatusNew `
    '"content.timing.revision.conflict" =>' `
    "mapeo HTTP conflicto temporal"

$endpointTitleOld = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgICBTdGF0dXNDb2Rlcy5TdGF0dXM0MDlDb25mbGljdCA9PgogICAgICAgICAgICAgICAgICAgICAgICAiRnVlbnRlIHRvZGF2w61hIG5vIHZhbGlkYWJsZSIsCiAgICAgICAgICAgICAgICAgICAgXyA9Pg=='

$endpointTitleNew = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgICBTdGF0dXNDb2Rlcy5TdGF0dXM0MDlDb25mbGljdAogICAgICAgICAgICAgICAgICAgICAgICB3aGVuIGV4Y2VwdGlvbi5Db2RlID09ICJjb250ZW50LnRpbWluZy5yZXZpc2lvbi5jb25mbGljdCIgPT4KICAgICAgICAgICAgICAgICAgICAgICAgIkNvbmZsaWN0byBkZSBzaW5jcm9uaXphY2nDs24iLAogICAgICAgICAgICAgICAgICAgIFN0YXR1c0NvZGVzLlN0YXR1czQwOUNvbmZsaWN0ID0+CiAgICAgICAgICAgICAgICAgICAgICAgICJGdWVudGUgdG9kYXbDrWEgbm8gdmFsaWRhYmxlIiwKICAgICAgICAgICAgICAgICAgICBfID0+'

Replace-ExactOnce `
    "apps/api/Endpoints/Editorial/TimingRevisionAdministrationEndpoints.cs" `
    $endpointTitleOld `
    $endpointTitleNew `
    '"Conflicto de sincronización"' `
    "titulo HTTP conflicto temporal"

$pageImportOld = Decode-Utf8Base64 'aW1wb3J0IHsgU3RhdGVNZXNzYWdlIH0gZnJvbSAnLi4vLi4vY29tcG9uZW50cy91aSc7CmltcG9ydCB7IGNyZWF0ZUh0dHBDbGllbnQgfSBmcm9tICcuLi8uLi9kYXRhL2h0dHAnOw=='

$pageImportNew = Decode-Utf8Base64 'aW1wb3J0IHsgU3RhdGVNZXNzYWdlIH0gZnJvbSAnLi4vLi4vY29tcG9uZW50cy91aSc7CmltcG9ydCB7IGNyZWF0ZUh0dHBDbGllbnQgfSBmcm9tICcuLi8uLi9kYXRhL2h0dHAnOwppbXBvcnQgewogIFN5bmNocm9uaXphdGlvblRpbWVsaW5lRWRpdG9yLAogIHR5cGUgVGltaW5nUmV2aXNpb25FZGl0b3JTbmFwc2hvdCwKfSBmcm9tICcuL1N5bmNocm9uaXphdGlvblRpbWVsaW5lRWRpdG9yJzs='

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx" `
    $pageImportOld `
    $pageImportNew `
    "SynchronizationTimelineEditor" `
    "import editor BL057"

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx" `
    '<p className="eyebrow">BL-MVP-056 · UI-MVP-022</p>' `
    '<p className="eyebrow">BL-MVP-056–057 · UI-MVP-022</p>' `
    "BL-MVP-056–057 · UI-MVP-022" `
    "identificacion UI-MVP-022 BL057"

$introOld = Decode-Utf8Base64 'ICAgICAgICAgIENhZGEgZnVlbnRlIG11bHRpbWVkaWEgY29uc2VydmEgdW5hIHJldmlzacOzbiB0ZW1wb3JhbCBpbmRlcGVuZGllbnRlIHNvYnJlIHVuYSByZXZpc2nDs24KICAgICAgICAgIGV4YWN0YSBkZSBsYSBsZXRyYS4gTG9zIGludGVydmFsb3Mgc2UgZXhwcmVzYW4gZW4gbWlsaXNlZ3VuZG9zIHkgZXN0YSBwYW50YWxsYSB0b2RhdsOtYSBubwogICAgICAgICAgYWRlbGFudGEgZWwgZWRpdG9yIGRlIGzDrW5lYSBkZSB0aWVtcG8gZGUgQkwtTVZQLTA1Ny4='

$introNew = Decode-Utf8Base64 'ICAgICAgICAgIENhZGEgZnVlbnRlIG11bHRpbWVkaWEgY29uc2VydmEgdW5hIHJldmlzacOzbiB0ZW1wb3JhbCBpbmRlcGVuZGllbnRlIHNvYnJlIHVuYSByZXZpc2nDs24KICAgICAgICAgIGV4YWN0YSBkZSBsYSBsZXRyYS4gTG9zIGludGVydmFsb3Mgc2UgZXhwcmVzYW4gZW4gbWlsaXNlZ3VuZG9zIHkgZWwgZWRpdG9yIHBlcm1pdGUgbWFyY2FyLAogICAgICAgICAgZGVzcGxhemFyLCBwcmV2aXN1YWxpemFyIHkgZ3VhcmRhciBib3JyYWRvcmVzIHNpbiBwdWJsaWNhci4='

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx" `
    $introOld `
    $introNew `
    "guardar borradores sin publicar" `
    "descripcion funcional BL057"

$pageInsertOld = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgKSA6ICgKICAgICAgICAgICAgICAgICAgICA8U3RhdGVNZXNzYWdlCiAgICAgICAgICAgICAgICAgICAgICBzdGF0ZT0iVUktRVNULTEyIgogICAgICAgICAgICAgICAgICAgICAgdGl0bGU9IlNpbiByZXZpc2nDs24gZGUgc2luY3Jvbml6YWNpw7NuIgogICAgICAgICAgICAgICAgICAgICAgZGVzY3JpcHRpb249IkVzdGEgZnVlbnRlIHRvZGF2w61hIG5vIHRpZW5lIG1hcmNhcyB0ZW1wb3JhbGVzIHBhcmEgbGEgcmV2aXNpw7NuIGRlIGxldHJhIHNlbGVjY2lvbmFkYS4iCiAgICAgICAgICAgICAgICAgICAgLz4KICAgICAgICAgICAgICAgICAgKX0KICAgICAgICAgICAgICAgIDwvYXJ0aWNsZT4='

$pageInsertNew = Decode-Utf8Base64 'ICAgICAgICAgICAgICAgICAgKSA6ICgKICAgICAgICAgICAgICAgICAgICA8U3RhdGVNZXNzYWdlCiAgICAgICAgICAgICAgICAgICAgICBzdGF0ZT0iVUktRVNULTEyIgogICAgICAgICAgICAgICAgICAgICAgdGl0bGU9IlNpbiByZXZpc2nDs24gZGUgc2luY3Jvbml6YWNpw7NuIgogICAgICAgICAgICAgICAgICAgICAgZGVzY3JpcHRpb249IkVzdGEgZnVlbnRlIHRvZGF2w61hIG5vIHRpZW5lIG1hcmNhcyB0ZW1wb3JhbGVzIHBhcmEgbGEgcmV2aXNpw7NuIGRlIGxldHJhIHNlbGVjY2lvbmFkYS4iCiAgICAgICAgICAgICAgICAgICAgLz4KICAgICAgICAgICAgICAgICAgKX0KCiAgICAgICAgICAgICAgICAgIHtzb3VyY2UuZHVyYXRpb25NcyAhPT0gbnVsbCA/ICgKICAgICAgICAgICAgICAgICAgICA8U3luY2hyb25pemF0aW9uVGltZWxpbmVFZGl0b3IKICAgICAgICAgICAgICAgICAgICAgIHJlY29yZGluZ0lkPXtyZWNvcmRpbmdJZH0KICAgICAgICAgICAgICAgICAgICAgIGx5cmljc1JldmlzaW9uSWQ9e3N0YXRlLmRhdGEubHlyaWNzUmV2aXNpb25JZCF9CiAgICAgICAgICAgICAgICAgICAgICBzb3VyY2U9e3NvdXJjZX0KICAgICAgICAgICAgICAgICAgICAgIG9uU2F2ZWQ9eyhyZXZpc2lvbjogVGltaW5nUmV2aXNpb25FZGl0b3JTbmFwc2hvdCkgPT4KICAgICAgICAgICAgICAgICAgICAgICAgc2V0U3RhdGUoKGN1cnJlbnQpID0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgY3VycmVudC5waGFzZSAhPT0gJ3JlYWR5JwogICAgICAgICAgICAgICAgICAgICAgICAgICAgPyBjdXJyZW50CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBwaGFzZTogJ3JlYWR5JywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBkYXRhOiB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAuLi5jdXJyZW50LmRhdGEsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzb3VyY2VzOiBjdXJyZW50LmRhdGEuc291cmNlcy5tYXAoKGNhbmRpZGF0ZSkgPT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY2FuZGlkYXRlLnNvdXJjZUlkID09PSBzb3VyY2Uuc291cmNlSWQKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA/IHsgLi4uY2FuZGlkYXRlLCB0aW1pbmdSZXZpc2lvbjogcmV2aXNpb24gfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDogY2FuZGlkYXRlLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9LAogICAgICAgICAgICAgICAgICAgICAgICApCiAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgLz4KICAgICAgICAgICAgICAgICAgKSA6IG51bGx9CiAgICAgICAgICAgICAgICA8L2FydGljbGU+'

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx" `
    $pageInsertOld `
    $pageInsertNew `
    "<SynchronizationTimelineEditor" `
    "editor temporal por fuente"

$pageTailOld = Decode-Utf8Base64 'ICAgICAgPFN0YXRlTWVzc2FnZQogICAgICAgIHN0YXRlPSJVSS1FU1QtMTEiCiAgICAgICAgdGl0bGU9Ik1vZGVsbyB0ZW1wb3JhbCBsaXN0byBwYXJhIGVkaWNpw7NuIgogICAgICAgIGRlc2NyaXB0aW9uPSJCTC1NVlAtMDU3IGHDsWFkaXLDoSBtYXJjYWRvLCBkZXNwbGF6YW1pZW50byB5IHByZXZpc3VhbGl6YWNpw7NuLiBCTC1NVlAtMDU2IHNvbG8gY29uZmlybWEgaWRlbnRpZGFkLCBmdWVudGUsIHJldmlzaW9uZXMsIGludGVydmFsb3MgeSB2YWxpZGFjaW9uZXMuIgogICAgICAvPg=='

$pageTailNew = Decode-Utf8Base64 'ICAgICAgPFN0YXRlTWVzc2FnZQogICAgICAgIHN0YXRlPSJVSS1FU1QtMTEiCiAgICAgICAgdGl0bGU9IlNpbmNyb25pemFjacOzbiBlZGl0YWJsZSwgdG9kYXbDrWEgbm8gcHVibGljYWRhIgogICAgICAgIGRlc2NyaXB0aW9uPSJCTC1NVlAtMDU3IGd1YXJkYSByZXZpc2lvbmVzIERSQUZULiBCTC1NVlAtMDU4IGNvbmVjdGFyw6EgZWwgSUZyYW1lIGRlIFlvdVR1YmUgeSBCTC1NVlAtMDU5IHJlc29sdmVyw6EgZWwgc2VndWltaWVudG8gZGUgcmVwcm9kdWNjacOzbi4iCiAgICAgIC8+'

Replace-ExactOnce `
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx" `
    $pageTailOld `
    $pageTailNew `
    "Sincronización editable, todavía no publicada" `
    "estado final BL057"

$ciOld = Decode-Utf8Base64 'ICAgICAgLSBuYW1lOiBWZXJpZnkgdGltaW5nIHJldmlzaW9ucyBhbmQgc3luY2hyb25pemF0aW9uIHNlZ21lbnRzCiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDU2X1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXRpbWluZy1yZXZpc2lvbi1tb2RlbC5zaA=='

$ciNew = Decode-Utf8Base64 'ICAgICAgLSBuYW1lOiBWZXJpZnkgdGltaW5nIHJldmlzaW9ucyBhbmQgc3luY2hyb25pemF0aW9uIHNlZ21lbnRzCiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDU2X1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXRpbWluZy1yZXZpc2lvbi1tb2RlbC5zaAoKICAgICAgLSBuYW1lOiBWZXJpZnkgZWRpdGFibGUgc3luY2hyb25pemF0aW9uIHRpbWVsaW5lCiAgICAgICAgc2hlbGw6IGJhc2gKICAgICAgICBlbnY6CiAgICAgICAgICBQR0hPU1Q6IDEyNy4wLjAuMQogICAgICAgICAgUEdQT1JUOiAnNTQzMicKICAgICAgICAgIFBHVVNFUjogcG9zdGdyZXMKICAgICAgICAgIFBHUEFTU1dPUkQ6IHBvc3RncmVzCiAgICAgICAgICBQR0RBVEFCQVNFOiBtdXNpY2FfYXByZW5kZXJfY2kKICAgICAgICAgIEJMMDU3X1VTRV9ET0NLRVJfUFNRTDogJ2ZhbHNlJwogICAgICAgIHJ1bjogYmFzaCBzY3JpcHRzL2NpL2NvbnRlbnQvdmVyaWZ5LXN5bmNocm9uaXphdGlvbi10aW1lbGluZS1lZGl0b3Iuc2g='

Replace-ExactOnce `
    ".github/workflows/ci.yml" `
    $ciOld `
    $ciNew `
    "Verify editable synchronization timeline" `
    "puerta CI BL-MVP-057"

$formatTargets = @(
    "apps/web/src/routes/editorial/SynchronizationStructurePage.tsx",
    "apps/web/src/routes/editorial/SynchronizationTimelineEditor.tsx",
    "apps/web/src/routes/editorial/synchronization-timeline-editor.css",
    "tests/E2ETests/synchronization-timeline-editor.spec.ts",
    "README/BL-MVP-057_README.md",
    "Instrucciones/INSTRUCCIONES_INSTALACION_MVP_F3_BL-MVP-057.md",
    "docs/engineering/content/synchronization-timeline-editor.md"
)

npx.cmd prettier --write @formatTargets
Assert-LastExitCode "Prettier BL057"

$bash = Resolve-GitBash
& $bash -n "scripts/ci/content/verify-synchronization-timeline-editor.sh"
Assert-LastExitCode "bash -n BL057"

if (-not $SkipBrowserInstall) {
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalar Chromium Playwright"
}

Write-Host "Compilando frontend antes del Playwright focal..."
npm.cmd run build --workspace @musica-aprender/web
Assert-LastExitCode "Build frontend focal BL057"

Write-Host "Ejecutando Playwright focal BL056/057..."
npm.cmd run test:e2e -- tests/E2ETests/timing-revision-model.spec.ts tests/E2ETests/synchronization-timeline-editor.spec.ts
Assert-LastExitCode "Playwright focal BL057"

Restore-GeneratedTypeScriptState

if (-not $SkipQualityGate) {
    & "$RepoRoot/scripts/check-quality.ps1"
}

Write-Host "Compilando Release para BL-MVP-057..."
dotnet build MusicaAprender.sln --configuration Release --no-restore
Assert-LastExitCode "Build Release BL057"

if (-not $SkipSmoke) {
    Write-Host "Preparando PostgreSQL local para smoke BL-MVP-057..."
    & "$RepoRoot/scripts/local/ensure-local-secrets.ps1"
    & "$RepoRoot/scripts/local/sync-postgres-secret.ps1"
    & "$RepoRoot/scripts/database/apply-bootstrap.ps1"
    & "$RepoRoot/scripts/database/apply-login-identities.ps1"
    & "$RepoRoot/scripts/database/apply-initial-migration.ps1"

    $database = "musica_aprender"
    $databaseUser = "musica_local"

    if (Test-Path ".env") {
        foreach ($line in Get-Content ".env") {
            if ($line -match '^POSTGRES_DB=(.+)$') {
                $database = $Matches[1].Trim()
            }
            if ($line -match '^POSTGRES_USER=(.+)$') {
                $databaseUser = $Matches[1].Trim()
            }
        }
    }

    $previousEnv = @{
        PGHOST = $env:PGHOST
        PGPORT = $env:PGPORT
        PGUSER = $env:PGUSER
        PGPASSWORD = $env:PGPASSWORD
        PGDATABASE = $env:PGDATABASE
        BL057_USE_DOCKER_PSQL = $env:BL057_USE_DOCKER_PSQL
    }

    try {
        $env:PGHOST = "127.0.0.1"
        $env:PGPORT = "5432"
        $env:PGUSER = $databaseUser
        $env:PGPASSWORD = "unused-docker-exec"
        $env:PGDATABASE = $database
        $env:BL057_USE_DOCKER_PSQL = "true"

        & $bash "scripts/ci/content/verify-synchronization-timeline-editor.sh"
        Assert-LastExitCode "Smoke BL-MVP-057"
    }
    finally {
        foreach ($name in $previousEnv.Keys) {
            $value = $previousEnv[$name]
            if ($null -eq $value) {
                Remove-Item "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$name" $value
            }
        }
    }
}

Restore-GeneratedTypeScriptState
Assert-InventorySubset

git diff --check
Assert-LastExitCode "git diff --check BL057"

$changed = @(Get-ChangedPaths)
$expected = @($PermanentPaths | Sort-Object -Unique)

if ($changed.Count -ne $expected.Count) {
    throw "BL-MVP-057 esperaba $($expected.Count) rutas y encontro $($changed.Count)."
}

for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($changed[$index] -cne $expected[$index]) {
        throw "Inventario BL-MVP-057 no coincide. Esperado '$($expected[$index])', encontrado '$($changed[$index])'."
    }
}

Write-Host "OK: inventario final exacto de 12 rutas BL-MVP-057."
Write-Host ""
git status --short --untracked-files=all
Write-Host ""
git diff --stat
Write-Host ""
git diff --name-status

Write-Host ""
Write-Host "OK: BL-MVP-057 instalado y validado localmente."
Write-Host "Incluye marcado, limites, desplazamiento multiple, preview local, borrador parcial y conflicto de revision."
Write-Host "No implementa YouTube IFrame BL058, motor de reproduccion BL059 ni publicacion."
Write-Host "PENDIENTE: reinicio normal y revision visual real de UI-MVP-022 antes de staging."
Write-Host "No se ejecuto git add, commit ni push."

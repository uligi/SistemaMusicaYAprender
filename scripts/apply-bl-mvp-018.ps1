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

function Write-Base64Utf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Base64
    )

    $fullPath = Join-Path $RepoRoot $Path
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $bytes = [Convert]::FromBase64String($Base64)
    [System.IO.File]::WriteAllBytes($fullPath, $bytes)
}

Write-Host "BL-MVP-018: preparando tokens versionados del sistema visual..."

# BL-MVP-018A: payloads base64 para conservar UTF-8 incluso bajo Windows PowerShell 5.1.
$appBase64 = "ZXhwb3J0IGZ1bmN0aW9uIEFwcCgpIHsKICByZXR1cm4gKAogICAgPG1haW4gY2xhc3NOYW1lPSJhcHAtc2hlbGwiIGRhdGEtZGVzaWduLXRva2Vucz0idjEiPgogICAgICA8c2VjdGlvbiBjbGFzc05hbWU9IndlbGNvbWUtY2FyZCIgYXJpYS1sYWJlbGxlZGJ5PSJ3ZWxjb21lLXRpdGxlIj4KICAgICAgICA8cCBjbGFzc05hbWU9ImV5ZWJyb3ciPlNpc3RlbWEgdmlzdWFsIHYxIMK3IEJMLU1WUC0wMTg8L3A+CiAgICAgICAgPGgxIGlkPSJ3ZWxjb21lLXRpdGxlIj5Nw7pzaWNhIHkgQXByZW5kZXI8L2gxPgogICAgICAgIDxwIGNsYXNzTmFtZT0id2VsY29tZS1jYXJkX19qYXBhbmVzZSIgbGFuZz0iamEiPgogICAgICAgICAg6Z+z5qW944Gn5pel5pys6Kqe44KS5a2m44G2CiAgICAgICAgPC9wPgogICAgICAgIDxwPgogICAgICAgICAgTGEgYmFzZSB2aXN1YWwgeWEgY29uc3VtZSB0b2tlbnMgdmVyc2lvbmFkb3MgcGFyYSBjb2xvciwgdGlwb2dyYWbDrWEsIGVzcGFjaWFkbywgcmFkaW9zLAogICAgICAgICAgZWxldmFjacOzbiB5IG1vdmltaWVudG8gYW50ZXMgZGUgY29uc3RydWlyIGxvcyBjb21wb25lbnRlcyBhY2Nlc2libGVzLgogICAgICAgIDwvcD4KICAgICAgPC9zZWN0aW9uPgogICAgPC9tYWluPgogICk7Cn0K"
$stylesBase64 = "QGltcG9ydCAnLi90b2tlbnMvdjEuY3NzJzsKCjpyb290IHsKICBjb2xvci1zY2hlbWU6IG9ubHkgbGlnaHQ7CiAgZm9udC1mYW1pbHk6IHZhcigtLW1hLWZvbnQtaW50ZXJmYWNlKTsKICBmb250LXNpemU6IHZhcigtLW1hLWZvbnQtc2l6ZS1ib2R5KTsKICBjb2xvcjogdmFyKC0tbWEtY29sb3ItaW5rKTsKICBiYWNrZ3JvdW5kOiB2YXIoLS1tYS1jb2xvci1zdXJmYWNlKTsKICBmb250LXN5bnRoZXNpczogbm9uZTsKICB0ZXh0LXJlbmRlcmluZzogb3B0aW1pemVMZWdpYmlsaXR5Owp9CgoqIHsKICBib3gtc2l6aW5nOiBib3JkZXItYm94Owp9Cgo6OnNlbGVjdGlvbiB7CiAgY29sb3I6IHZhcigtLW1hLWNvbG9yLWNhbnZhcyk7CiAgYmFja2dyb3VuZDogdmFyKC0tbWEtY29sb3ItcHJpbWFyeSk7Cn0KCmJvZHkgewogIG1hcmdpbjogMDsKICBtaW4td2lkdGg6IHZhcigtLW1hLWxheW91dC1taW4tdmlld3BvcnQpOwogIG1pbi1oZWlnaHQ6IDEwMHZoOwp9CgouYXBwLXNoZWxsIHsKICBtaW4taGVpZ2h0OiAxMDB2aDsKICBkaXNwbGF5OiBncmlkOwogIHBsYWNlLWl0ZW1zOiBjZW50ZXI7CiAgcGFkZGluZzogdmFyKC0tbWEtc3BhY2UtNSk7Cn0KCi53ZWxjb21lLWNhcmQgewogIHdpZHRoOiBtaW4odmFyKC0tbWEtY29udGVudC1yZWFkaW5nLW1heCksIDEwMCUpOwogIHBhZGRpbmc6IGNsYW1wKHZhcigtLW1hLXNwYWNlLTUpLCA1dncsIHZhcigtLW1hLXNwYWNlLTcpKTsKICBib3JkZXI6IHZhcigtLW1hLWJvcmRlci13aWR0aC10aGluKSBzb2xpZCB2YXIoLS1tYS1jb2xvci1ib3JkZXIpOwogIGJvcmRlci1yYWRpdXM6IHZhcigtLW1hLXJhZGl1cy1zdXJmYWNlKTsKICBiYWNrZ3JvdW5kOiB2YXIoLS1tYS1jb2xvci1jYW52YXMpOwogIGJveC1zaGFkb3c6IHZhcigtLW1hLWVsZXZhdGlvbi1ub25lKTsKICB0cmFuc2l0aW9uLWR1cmF0aW9uOiB2YXIoLS1tYS1tb3Rpb24tZHVyYXRpb24tc3RhbmRhcmQpOwogIHRyYW5zaXRpb24tcHJvcGVydHk6IGJvcmRlci1jb2xvcjsKICB0cmFuc2l0aW9uLXRpbWluZy1mdW5jdGlvbjogdmFyKC0tbWEtbW90aW9uLWVhc2luZy1zdGFuZGFyZCk7Cn0KCi53ZWxjb21lLWNhcmQ6aG92ZXIgewogIGJvcmRlci1jb2xvcjogdmFyKC0tbWEtY29sb3ItcHJpbWFyeSk7Cn0KCi5leWVicm93IHsKICBtYXJnaW46IDAgMCB2YXIoLS1tYS1zcGFjZS0yKTsKICBjb2xvcjogdmFyKC0tbWEtY29sb3ItbXV0ZWQpOwogIGZvbnQtc2l6ZTogdmFyKC0tbWEtZm9udC1zaXplLXNlY29uZGFyeSk7CiAgZm9udC13ZWlnaHQ6IHZhcigtLW1hLWZvbnQtd2VpZ2h0LWJvbGQpOwogIGxldHRlci1zcGFjaW5nOiAwLjA1ZW07CiAgdGV4dC10cmFuc2Zvcm06IHVwcGVyY2FzZTsKfQoKaDEgewogIG1hcmdpbjogMCAwIHZhcigtLW1hLXNwYWNlLTQpOwogIGZvbnQtc2l6ZTogY2xhbXAoCiAgICB2YXIoLS1tYS1mb250LXNpemUtcGFnZS10aXRsZS1taW4pLAogICAgNXZ3LAogICAgdmFyKC0tbWEtZm9udC1zaXplLXBhZ2UtdGl0bGUtbWF4KQogICk7CiAgZm9udC13ZWlnaHQ6IHZhcigtLW1hLWZvbnQtd2VpZ2h0LXNlbWlib2xkKTsKICBsaW5lLWhlaWdodDogdmFyKC0tbWEtbGluZS1oZWlnaHQtaGVhZGluZyk7Cn0KCnAgewogIGxpbmUtaGVpZ2h0OiB2YXIoLS1tYS1saW5lLWhlaWdodC1ib2R5KTsKfQoKLndlbGNvbWUtY2FyZF9famFwYW5lc2UgewogIG1hcmdpbjogMCAwIHZhcigtLW1hLXNwYWNlLTQpOwogIGZvbnQtZmFtaWx5OiB2YXIoLS1tYS1mb250LWphcGFuZXNlKTsKICBmb250LXNpemU6IHZhcigtLW1hLWZvbnQtc2l6ZS1qYXBhbmVzZSk7Cn0K"

Write-Base64Utf8 "apps/web/src/app/App.tsx" $appBase64
Write-Base64Utf8 "apps/web/src/styles/index.css" $stylesBase64

$workflowPath = Join-Path $RepoRoot ".github/workflows/ci.yml"
$workflow = [System.IO.File]::ReadAllText($workflowPath)

if (-not $workflow.Contains("Verify versioned visual tokens")) {
    $anchor = @'
      - name: TypeScript strict check
        run: npm run typecheck

      - name: Formatting check
'@

    $replacement = @'
      - name: TypeScript strict check
        run: npm run typecheck

      - name: Verify versioned visual tokens
        run: node scripts/frontend/verify-design-tokens.mjs

      - name: Formatting check
'@

    if (-not $workflow.Contains($anchor)) {
        throw "No se encontro el ancla esperada de CI para BL-MVP-018."
    }

    $workflow = $workflow.Replace($anchor, $replacement)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($workflowPath, ($workflow.TrimEnd("`r", "`n") + "`n"), $utf8)
}

Write-Host "Formateando archivos del repositorio..."
npm.cmd run format
Assert-LastExitCode "npm format"

Write-Host "Verificando tokens visuales v1 y codificacion UTF-8..."
node scripts/frontend/verify-design-tokens.mjs
Assert-LastExitCode "Verificador BL-MVP-018"

Write-Host "Validando TypeScript..."
npm.cmd run typecheck
Assert-LastExitCode "TypeScript"

Write-Host "Construyendo frontend..."
npm.cmd run build
Assert-LastExitCode "Build frontend"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

Write-Host "Ejecutando puerta local de calidad..."
& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-018 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    abrir http://localhost:5173 y validar visualmente la pagina base."

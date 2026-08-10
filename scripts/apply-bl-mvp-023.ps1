[CmdletBinding()]
param(
    [switch]$SkipBrowserInstall,
    [switch]$SkipQualityGate,
    [switch]$SkipStart,
    [switch]$SkipRegistrationSmoke
)

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

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Correction
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Falta '$Name'. $Correction"
    }
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    if (-not (Test-Path ".env" -PathType Leaf)) {
        return $DefaultValue
    }

    $match = Get-Content ".env" |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
        Select-Object -Last 1

    if ($null -eq $match) {
        return $DefaultValue
    }

    return (($match -split "=", 2)[1]).Trim()
}

function Invoke-PostgresScalar {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $dbUser = Get-DotEnvValue -Name "POSTGRES_USER" -DefaultValue "musica_local"
    $dbName = Get-DotEnvValue -Name "POSTGRES_DB" -DefaultValue "musica_aprender"

    if ($dbUser -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_USER local no cumple el formato seguro esperado."
    }

    if ($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "POSTGRES_DB local no cumple el formato seguro esperado."
    }

    $output = docker compose exec -T postgres `
        psql `
        --username $dbUser `
        --dbname $dbName `
        --no-password `
        --set ON_ERROR_STOP=1 `
        --tuples-only `
        --no-align `
        --command $Sql
    Assert-LastExitCode "Consulta de verificacion PostgreSQL"

    return (($output | Out-String).Trim())
}

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Email,
        [AllowEmptyString()][string]$IdempotencyKey
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($IdempotencyKey)) {
        $headers["Idempotency-Key"] = $IdempotencyKey
    }

    $body = @{ email = $Email } | ConvertTo-Json -Compress

    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Method Post `
            -Uri $Uri `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body `
            -TimeoutSec 20

        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body = [string]$response.Content
        }
    }
    catch {
        $errorResponse = $_.Exception.Response
        if ($null -eq $errorResponse) {
            throw
        }

        return [pscustomobject]@{
            StatusCode = [int]$errorResponse.StatusCode
            Body = ""
        }
    }
}

function Convert-HexToBytes {
    param([Parameter(Mandatory = $true)][string]$Hex)

    if (($Hex.Length % 2) -ne 0 -or $Hex -notmatch '^[0-9A-Fa-f]+$') {
        throw "El valor hexadecimal no tiene un formato valido."
    }

    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }

    return $bytes
}

function Get-LookupHashHex {
    param(
        [Parameter(Mandatory = $true)][string]$Email,
        [Parameter(Mandatory = $true)][string]$LookupKeyPath
    )

    $keyHex = [System.IO.File]::ReadAllText($LookupKeyPath).Trim()
    if ($keyHex -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "identity_email_lookup_key debe contener exactamente 32 bytes hexadecimales."
    }

    [byte[]]$keyBytes = Convert-HexToBytes -Hex $keyHex
    $emailBytes = [System.Text.Encoding]::UTF8.GetBytes($Email.ToUpperInvariant())
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keyBytes)

    try {
        $hash = $hmac.ComputeHash($emailBytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $hmac.Dispose()
        [Array]::Clear($keyBytes, 0, $keyBytes.Length)
        [Array]::Clear($emailBytes, 0, $emailBytes.Length)
    }
}

function Test-PersonalRegistration {
    $apiPort = Get-DotEnvValue -Name "API_PORT" -DefaultValue "5080"
    if ($apiPort -notmatch '^\d{1,5}$' -or [int]$apiPort -gt 65535) {
        throw "API_PORT local no es un puerto valido."
    }

    $endpoint = "http://127.0.0.1:$apiPort/api/v1/auth/register"
    $suffix = [Guid]::NewGuid().ToString("N")
    $email = "bl023-$suffix@example.test"
    $duplicateEmail = $email.ToUpperInvariant()
    $keyOne = "bl023-$([Guid]::NewGuid().ToString('N'))"
    $keyTwo = "bl023-$([Guid]::NewGuid().ToString('N'))"
    $lookupKeyPath = Join-Path $RepoRoot "secrets/local/identity_email_lookup_key"
    $lookupHashHex = Get-LookupHashHex -Email $email -LookupKeyPath $lookupKeyPath
    $cleanupSql = @"
DELETE FROM identity.user_profile
WHERE account_id IN (
    SELECT account_id
    FROM security.account
    WHERE encode(email_lookup_hash, 'hex') = '$lookupHashHex'
);
DELETE FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$lookupHashHex';
DELETE FROM ops.idempotency_record
WHERE account_id IS NULL
  AND idempotency_key IN ('$keyOne', '$keyTwo');
"@

    try {
        $before = Invoke-PostgresScalar -Sql "SELECT count(*) FROM security.account WHERE encode(email_lookup_hash, 'hex') = '$lookupHashHex';"
        if ($before -ne "0") {
            throw "La identidad sintetica de BL-MVP-023 ya existia antes de la prueba."
        }

        $first = Invoke-JsonPost -Uri $endpoint -Email $email -IdempotencyKey $keyOne
        if ($first.StatusCode -ne 202) {
            throw "El primer registro devolvio HTTP $($first.StatusCode), se esperaba 202."
        }

        if ($first.Body -notmatch '"status"\s*:\s*"RECEIVED"') {
            throw "La respuesta publica no contiene el estado generico RECEIVED."
        }

        if ($first.Body.Contains($email)) {
            throw "La respuesta publica expuso el correo sintetico."
        }

        $replay = Invoke-JsonPost -Uri $endpoint -Email $email -IdempotencyKey $keyOne
        if ($replay.StatusCode -ne 202 -or $replay.Body -ne $first.Body) {
            throw "El replay idempotente no reprodujo exactamente la respuesta almacenada."
        }

        $duplicate = Invoke-JsonPost -Uri $endpoint -Email $duplicateEmail -IdempotencyKey $keyTwo
        if ($duplicate.StatusCode -ne 202 -or $duplicate.Body -ne $first.Body) {
            throw "El correo duplicado no recibio la misma respuesta publica generica."
        }

        $conflict = Invoke-JsonPost `
            -Uri $endpoint `
            -Email "otra-$email" `
            -IdempotencyKey $keyOne
        if ($conflict.StatusCode -ne 409) {
            throw "La misma clave con otro digest devolvio HTTP $($conflict.StatusCode), se esperaba 409."
        }

        $invalid = Invoke-JsonPost `
            -Uri $endpoint `
            -Email "correo-invalido" `
            -IdempotencyKey "bl023-$([Guid]::NewGuid().ToString('N'))"
        if ($invalid.StatusCode -ne 400) {
            throw "El correo invalido devolvio HTTP $($invalid.StatusCode), se esperaba 400."
        }

        $missingKey = Invoke-JsonPost -Uri $endpoint -Email $email -IdempotencyKey ""
        if ($missingKey.StatusCode -ne 400) {
            throw "La solicitud sin Idempotency-Key devolvio HTTP $($missingKey.StatusCode), se esperaba 400."
        }

        $accountCheck = Invoke-PostgresScalar -Sql @"
SELECT count(*)
FROM security.account
WHERE encode(email_lookup_hash, 'hex') = '$lookupHashHex'
  AND status_code = 'PENDING'
  AND verified_at IS NULL
  AND octet_length(email_lookup_hash) = 32
  AND octet_length(email_cipher) > 29;
"@
        if ($accountCheck -ne "1") {
            throw "PostgreSQL no contiene exactamente una cuenta PENDING protegida."
        }

        $profileCheck = Invoke-PostgresScalar -Sql @"
SELECT count(*)
FROM identity.user_profile p
JOIN security.account a USING (account_id)
WHERE encode(a.email_lookup_hash, 'hex') = '$lookupHashHex'
  AND p.display_name IS NULL
  AND p.ui_language = 'es-CR'
  AND p.time_zone = 'America/Costa_Rica';
"@
        if ($profileCheck -ne "1") {
            throw "PostgreSQL no contiene exactamente el perfil minimo esperado."
        }

        Write-Host "OK: BL-MVP-023 verificado contra API y PostgreSQL reales."
    }
    finally {
        try {
            Invoke-PostgresScalar -Sql $cleanupSql | Out-Null
        }
        catch {
            Write-Warning "No se pudo limpiar por completo la identidad sintetica: $($_.Exception.Message)"
        }
    }
}

$requiredFiles = @(
    ".github/workflows/ci.yml",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationEndpoint.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationRequest.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationResponse.cs",
    "apps/api/Endpoints/Identity/PersonalAccountRegistrationService.cs",
    "apps/web/src/routes/public/PersonalAccountRegistrationPage.tsx",
    "apps/web/src/routes/public/public-area.css",
    "config/secrets/manifest.json",
    "docs/engineering/frontend/personal-account-registration.md",
    "scripts/ci/identity/verify-personal-registration.sh",
    "src/Modules/Identity/Infrastructure/Registration/IdentityProfileRegistrationWriter.cs",
    "src/Modules/Security/Infrastructure/Registration/PersonalEmailProtector.cs",
    "src/Modules/Security/Infrastructure/Registration/ProtectedEmail.cs",
    "src/Modules/Security/Infrastructure/Registration/SecurityAccountRegistrationWriter.cs",
    "tests/E2ETests/base-accessibility.spec.ts",
    "BL-MVP-023_README.md"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $relativePath) -PathType Leaf)) {
        throw "Falta un archivo requerido de BL-MVP-023: $relativePath"
    }
}

Assert-Command -Name "git" -Correction "Instale Git, abra una PowerShell nueva y vuelva a ejecutar este instalador. Si persiste, comparta la salida completa para recibir un ZIP correctivo."
Assert-Command -Name "docker" -Correction "Instale/inicie Docker Desktop con Linux containers."
Assert-Command -Name "dotnet" -Correction "Instale .NET SDK 9.0.x."
Assert-Command -Name "node" -Correction "Instale Node.js 24.18.0."
Assert-Command -Name "npm.cmd" -Correction "Instale npm 11.16.0."

git merge-base --is-ancestor 3c1d957 HEAD
Assert-LastExitCode "Comprobacion de la base publicada BL-MVP-022 (3c1d957)"

& "$PSScriptRoot/check-toolchain.ps1"

docker version *> $null
Assert-LastExitCode "Docker Engine"
docker compose version *> $null
Assert-LastExitCode "Docker Compose"

& "$PSScriptRoot/local/ensure-local-secrets.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

if (-not $SkipBrowserInstall) {
    Write-Host "Instalando Chromium fijado por Playwright..."
    npm.cmd ci
    Assert-LastExitCode "npm ci"
    npm.cmd run test:e2e:install
    Assert-LastExitCode "Instalacion Chromium Playwright"
}

if (-not $SkipQualityGate) {
    Write-Host "Ejecutando la puerta local completa de calidad..."
    & "$PSScriptRoot/check-quality.ps1"
}

if (-not $SkipStart) {
    Write-Host "Iniciando el entorno local reproducible..."
    & "$PSScriptRoot/local/start.ps1"
    & "$PSScriptRoot/local/verify-running.ps1"

    if (-not $SkipRegistrationSmoke) {
        Test-PersonalRegistration
    }
}

$generatedTypeScriptState = git status --porcelain -- "apps/web/tsconfig.app.tsbuildinfo"
Assert-LastExitCode "Consulta del archivo incremental TypeScript"
if (-not [string]::IsNullOrWhiteSpace(($generatedTypeScriptState | Out-String))) {
    git restore -- "apps/web/tsconfig.app.tsbuildinfo"
    Assert-LastExitCode "Restauracion de tsconfig.app.tsbuildinfo"
    Write-Host "Restaurado apps/web/tsconfig.app.tsbuildinfo por ser salida incremental."
}

git diff --check
Assert-LastExitCode "git diff --check"

Write-Host ""
git status --short "--untracked-files=all"
Assert-LastExitCode "git status"
Write-Host ""
git diff --stat
Assert-LastExitCode "git diff --stat"
Write-Host ""
git diff --name-only
Assert-LastExitCode "git diff --name-only"

Write-Host ""
if ($SkipQualityGate -or $SkipStart -or $SkipRegistrationSmoke) {
    Write-Warning "BL-MVP-023 fue preparado con validaciones omitidas; no esta listo para publicar."
}
else {
    Write-Host "OK: BL-MVP-023 instalado y validado localmente con API, PostgreSQL y navegador."
}
Write-Host "Web:      http://localhost:5173/registro"
Write-Host "API:      http://localhost:5080/health/ready"
Write-Host "Mailpit:  http://localhost:8025"
Write-Host "No se ejecuto git add, commit, push ni una migracion de produccion."

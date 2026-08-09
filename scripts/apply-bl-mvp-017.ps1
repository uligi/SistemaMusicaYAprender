$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step fallo con codigo de salida $LASTEXITCODE."
    }
}

function Resolve-RepoPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $RepoRoot $Path
}

function Write-NormalizedText(
    [string]$Path,
    [string]$Content) {

    $fullPath = Resolve-RepoPath $Path
    $normalized = $Content.Replace("`r`n", "`n")

    if ($fullPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Replace("`n", "`r`n")
    }

    [System.IO.File]::WriteAllText(
        $fullPath,
        $normalized,
        $Utf8NoBom)
}

function Replace-Required(
    [string]$Path,
    [string]$Old,
    [string]$New) {

    $fullPath = Resolve-RepoPath $Path
    $content = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
    $oldNormalized = $Old.Replace("`r`n", "`n")
    $newNormalized = $New.Replace("`r`n", "`n")

    if ($content.Contains($newNormalized)) {
        return
    }

    if (-not $content.Contains($oldNormalized)) {
        throw "No se encontro el bloque esperado para actualizar '$Path'."
    }

    Write-NormalizedText `
        $fullPath `
        $content.Replace($oldNormalized, $newNormalized)
}

function Ensure-LineAfter(
    [string]$Path,
    [string]$Anchor,
    [string]$Line) {

    $fullPath = Resolve-RepoPath $Path
    $content = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
    $lines = @($content -split "`n")

    if ($lines -contains $Line) {
        return
    }

    $anchorIndex = [Array]::IndexOf($lines, $Anchor)

    if ($anchorIndex -lt 0) {
        throw "No se encontro la linea ancla esperada para actualizar '$Path'."
    }

    $updated = @()

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $updated += $lines[$index]

        if ($index -eq $anchorIndex) {
            $updated += $Line
        }
    }

    Write-NormalizedText `
        $fullPath `
        ($updated -join "`n")
}

function Append-Required(
    [string]$Path,
    [string]$Marker,
    [string]$Text) {

    $fullPath = Resolve-RepoPath $Path
    $content = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")

    if ($content.Contains($Marker)) {
        return
    }

    Write-NormalizedText `
        $fullPath `
        ($content.TrimEnd() + "`n`n" + $Text.Trim() + "`n")
}

Write-Host "BL-MVP-017: preparando cola de correo y adaptador SMTP interno..."

Replace-Required `
    "Directory.Packages.props" `
    '    <PackageVersion Include="Minio" Version="7.0.0" />' `
    "    <PackageVersion Include=`"Minio`" Version=`"7.0.0`" />`n    <PackageVersion Include=`"MailKit`" Version=`"4.17.0`" />"

Replace-Required `
    "src/BuildingBlocks/Infrastructure/MusicaAprender.BuildingBlocks.Infrastructure.csproj" `
    '    <PackageReference Include="Minio" />' `
    "    <PackageReference Include=`"Minio`" />`n    <PackageReference Include=`"MailKit`" />"

Ensure-LineAfter `
    "apps/api/Program.cs" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Database;" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;"

Replace-Required `
    "apps/api/Program.cs" `
    'builder.Services.AddMusicaAprenderReliableOperations();' `
    "builder.Services.AddMusicaAprenderReliableOperations();`nbuilder.Services.AddMusicaAprenderEmailQueue();"

Ensure-LineAfter `
    "apps/worker/Program.cs" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Configuration;" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Email.DependencyInjection;"

Replace-Required `
    "apps/worker/Program.cs" `
    'builder.Services.AddMusicaAprenderOutboxDispatch();' `
    "builder.Services.AddMusicaAprenderOutboxDispatch();`nbuilder.Services.AddMusicaAprenderEmailDelivery(builder.Configuration);"

Replace-Required `
    "apps/worker/Program.cs" `
    'builder.Services.AddHostedService<OutboxDispatchWorker>();' `
    "builder.Services.AddHostedService<OutboxDispatchWorker>();`nbuilder.Services.AddHostedService<EmailDeliveryWorker>();"

$telemetryAnchor = @'
    public static readonly Counter<long> OutboxReview =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.outbox.review",
            unit: "{event}",
            description: "Eventos de outbox enviados a revision.");
'@

$telemetryInsert = @'
    public static readonly Counter<long> OutboxReview =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.outbox.review",
            unit: "{event}",
            description: "Eventos de outbox enviados a revision.");

    public static readonly Counter<long> EmailDelivered =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.delivered",
            unit: "{email}",
            description: "Trabajos de correo entregados por SMTP.");

    public static readonly Counter<long> EmailRetries =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.retries",
            unit: "{retry}",
            description: "Reintentos de trabajos de correo.");

    public static readonly Counter<long> EmailReview =
        Meter.CreateCounter<long>(
            "musica_aprender.worker.email.review",
            unit: "{email}",
            description: "Trabajos de correo enviados a revision.");
'@

Replace-Required `
    "apps/worker/Observability/WorkerTelemetry.cs" `
    $telemetryAnchor `
    $telemetryInsert

Replace-Required `
    "compose.yml" `
    "      Smtp__Host: smtp-sink`n      Smtp__Port: '1025'`n      OpenTelemetry__OtlpEndpoint:" `
    "      Smtp__Host: smtp-sink`n      Smtp__Port: '1025'`n      Smtp__FromAddress: no-reply@musica-aprender.local`n      Smtp__FromDisplayName: Musica y Aprender`n      Smtp__Security: None`n      OpenTelemetry__OtlpEndpoint:"

$workflowAnchor = @'
      - name: Verify tracked tree still contains no secrets
        shell: bash
        run: bash scripts/security/check-no-secrets.sh
'@

$workflowInsert = @'
      - name: Verify queued versioned SMTP email delivery
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGDATABASE: musica_aprender_ci
        run: bash scripts/ci/email/verify-email-delivery.sh

      - name: Verify tracked tree still contains no secrets
        shell: bash
        run: bash scripts/security/check-no-secrets.sh
'@

Replace-Required `
    ".github/workflows/ci.yml" `
    $workflowAnchor `
    $workflowInsert

Append-Required `
    "infrastructure/smtp/README.md" `
    "BL-MVP-017" `
    @'
## BL-MVP-017

El correo interno se procesa en dos etapas durables:

1. `email.delivery.requested` se confirma en la outbox junto con la decision de negocio.
2. El Worker proyecta un `background_job` `EMAIL_DELIVERY` y realiza SMTP fuera de la transaccion de cuenta.

El payload persistido conserva referencias opacas, plantilla/version e idioma; no guarda destinatario ni token.
Mailpit sigue siendo el sink local. El adaptador SMTP usa MailKit y es reemplazable sin cambiar los contratos de identidad.
'@

$projectPath = "tools\EmailDeliveryVerifier\MusicaAprender.EmailDeliveryVerifier.csproj"
$solutionProjects = @(dotnet sln MusicaAprender.sln list)
Assert-LastExitCode "Lectura de solucion"

if (-not ($solutionProjects -match [regex]::Escape($projectPath))) {
    dotnet sln MusicaAprender.sln add $projectPath
    Assert-LastExitCode "Agregar EmailDeliveryVerifier a la solucion"
}

Write-Host "Actualizando lockfiles .NET..."
dotnet restore MusicaAprender.sln --force-evaluate
Assert-LastExitCode "Restauracion .NET"

Write-Host "Formateando C#..."
dotnet format MusicaAprender.sln --no-restore
Assert-LastExitCode "dotnet format"

Write-Host "Formateando archivos de repositorio..."
npm.cmd run format
Assert-LastExitCode "npm format"

Write-Host "Compilando verificador de correo..."
dotnet build $projectPath --no-restore
Assert-LastExitCode "Compilacion EmailDeliveryVerifier"

Write-Host "Verificando BL-MVP-017..."
& "$PSScriptRoot/database/verify-email-delivery.ps1"

Write-Host "Confirmando BL-MVP-016..."
& "$PSScriptRoot/database/verify-object-store.ps1"

Write-Host "Confirmando BL-MVP-015..."
& "$PSScriptRoot/database/verify-reliability.ps1"

Write-Host "Confirmando BL-MVP-014..."
& "$PSScriptRoot/database/verify-ef-model.ps1"

Write-Host "Confirmando BL-MVP-013..."
& "$PSScriptRoot/database/verify-transaction-context.ps1"

Write-Host "Confirmando BL-MVP-012..."
& "$PSScriptRoot/database/verify-database-access.ps1"

Write-Host "Confirmando BL-MVP-011..."
& "$PSScriptRoot/database/verify-physical-schema.ps1"
& "$PSScriptRoot/database/verify-master-source.ps1"

docker compose config --quiet
Assert-LastExitCode "Validacion Docker Compose"

& "$PSScriptRoot/check-quality.ps1"

Write-Host ""
Write-Host "OK: BL-MVP-017 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    .\scripts\database\verify-email-delivery.ps1"

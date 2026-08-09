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

Write-Host "BL-MVP-016: preparando IObjectStore y almacenamiento privado de desarrollo..."

Replace-Required `
    "Directory.Packages.props" `
    '    <PackageVersion Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="9.0.4" />' `
    "    <PackageVersion Include=`"Npgsql.EntityFrameworkCore.PostgreSQL`" Version=`"9.0.4`" />`n    <PackageVersion Include=`"Minio`" Version=`"7.0.0`" />"

Replace-Required `
    "src/BuildingBlocks/Infrastructure/MusicaAprender.BuildingBlocks.Infrastructure.csproj" `
    '    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" />' `
    "    <PackageReference Include=`"Npgsql.EntityFrameworkCore.PostgreSQL`" />`n    <PackageReference Include=`"Minio`" />"

Replace-Required `
    "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs" `
    '    private const string ObjectStoreSecretKeySecret = "object_store_secret_key";' `
    "    private const string ObjectStoreSecretKeySecret = `"object_store_secret_key`";`n    private const string ObjectStoreEncryptionKeySecret = `"object_store_encryption_key`";"

$externalSecretOld = @'
        var objectStoreSecretKey = ReadSecret(
            secretDirectory,
            ObjectStoreSecretKeySecret,
            minimumLength: 32);
'@

$externalSecretNew = @'
        var objectStoreSecretKey = ReadSecret(
            secretDirectory,
            ObjectStoreSecretKeySecret,
            minimumLength: 32);

        var objectStoreEncryptionKey = ReadSecret(
            secretDirectory,
            ObjectStoreEncryptionKeySecret,
            minimumLength: 64);
'@

Replace-Required `
    "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs" `
    $externalSecretOld `
    $externalSecretNew

Replace-Required `
    "src/BuildingBlocks/Infrastructure/Configuration/ExternalConfigurationExtensions.cs" `
    '                ["ObjectStore:SecretKey"] = objectStoreSecretKey' `
    "                [`"ObjectStore:SecretKey`"] = objectStoreSecretKey,`n                [`"ObjectStore:EncryptionKey`"] = objectStoreEncryptionKey"

Replace-Required `
    ".env.example" `
    "OBJECT_STORE_CONSOLE_PORT=9001" `
    "OBJECT_STORE_CONSOLE_PORT=9001`nOBJECT_STORE_BUCKET=musica-aprender-private"

Replace-Required `
    "scripts/local/ensure-local-secrets.ps1" `
    'Ensure-Secret "object_store_secret_key" 32' `
    "Ensure-Secret `"object_store_secret_key`" 32`r`nEnsure-Secret `"object_store_encryption_key`" 32"

Replace-Required `
    "scripts/ci/security/create-compose-secrets.sh" `
    'openssl rand -hex 32 > secrets/local/object_store_secret_key' `
    "openssl rand -hex 32 > secrets/local/object_store_secret_key`nopenssl rand -hex 32 > secrets/local/object_store_encryption_key"

Ensure-LineAfter `
    "apps/api/Program.cs" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Observability;" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;"

Replace-Required `
    "apps/api/Program.cs" `
    'builder.Services.AddMusicaAprenderReliableOperations();' `
    "builder.Services.AddMusicaAprenderReliableOperations();`nbuilder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);"

Ensure-LineAfter `
    "apps/worker/Program.cs" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.Observability;" `
    "using MusicaAprender.BuildingBlocks.Infrastructure.ObjectStorage.DependencyInjection;"

Replace-Required `
    "apps/worker/Program.cs" `
    'builder.Services.AddMusicaAprenderOutboxDispatch();' `
    "builder.Services.AddMusicaAprenderOutboxDispatch();`nbuilder.Services.AddMusicaAprenderPrivateObjectStore(builder.Configuration);"

Replace-Required `
    "compose.yml" `
    "      ObjectStore__Endpoint: http://object-store:9000`n      Smtp__Host: smtp-sink" `
    "      ObjectStore__Endpoint: http://object-store:9000`n      ObjectStore__Bucket: `${OBJECT_STORE_BUCKET:-musica-aprender-private}`n      ObjectStore__EncryptionKeyReference: local-secret://object_store_encryption_key/v1`n      Smtp__Host: smtp-sink"

Replace-Required `
    "compose.yml" `
    "      - postgres_api_password`n      - object_store_access_key`n      - object_store_secret_key`n    ports:" `
    "      - postgres_api_password`n      - object_store_access_key`n      - object_store_secret_key`n      - object_store_encryption_key`n    ports:"

Replace-Required `
    "compose.yml" `
    "      - postgres_worker_password`n      - object_store_access_key`n      - object_store_secret_key`n    depends_on:" `
    "      - postgres_worker_password`n      - object_store_access_key`n      - object_store_secret_key`n      - object_store_encryption_key`n    depends_on:"

Replace-Required `
    "compose.yml" `
    "  object_store_secret_key:`n    file: ./secrets/local/object_store_secret_key" `
    "  object_store_secret_key:`n    file: ./secrets/local/object_store_secret_key`n  object_store_encryption_key:`n    file: ./secrets/local/object_store_encryption_key"

$workflowAnchor = @'
      - name: Verify tracked tree still contains no secrets
        shell: bash
        run: bash scripts/security/check-no-secrets.sh
'@

$workflowInsert = @'
      - name: Start private development object store
        shell: bash
        run: |
          docker compose up --detach object-store
          for attempt in $(seq 1 30); do
            if curl --fail --silent http://127.0.0.1:9000/minio/health/ready >/dev/null; then
              exit 0
            fi
            sleep 1
          done
          docker compose logs object-store
          exit 1

      - name: Verify encrypted private object storage
        shell: bash
        env:
          PGHOST: 127.0.0.1
          PGPORT: '5432'
          PGDATABASE: musica_aprender_ci
        run: bash scripts/ci/object-storage/verify-private-object-store.sh

      - name: Verify tracked tree still contains no secrets
        shell: bash
        run: bash scripts/security/check-no-secrets.sh
'@

Replace-Required `
    ".github/workflows/ci.yml" `
    $workflowAnchor `
    $workflowInsert

Append-Required `
    "docs/adr/README.md" `
    "0003-private-object-storage.md" `
    '- `0003-private-object-storage.md`: concreta ADR-012 para MinIO privado de desarrollo y cifrado previo al almacenamiento.'

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Creado .env con configuracion no secreta."
}

& "$PSScriptRoot/local/ensure-local-secrets.ps1"
& "$PSScriptRoot/local/sync-postgres-secret.ps1"
& "$PSScriptRoot/database/apply-bootstrap.ps1"
& "$PSScriptRoot/database/apply-login-identities.ps1"
& "$PSScriptRoot/database/apply-initial-migration.ps1"

$projectPath = "tools\ObjectStoreVerifier\MusicaAprender.ObjectStoreVerifier.csproj"
$solutionProjects = @(dotnet sln MusicaAprender.sln list)
Assert-LastExitCode "Lectura de solucion"

if (-not ($solutionProjects -match [regex]::Escape($projectPath))) {
    dotnet sln MusicaAprender.sln add $projectPath
    Assert-LastExitCode "Agregar ObjectStoreVerifier a la solucion"
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

Write-Host "Compilando verificador de object storage..."
dotnet build $projectPath --no-restore
Assert-LastExitCode "Compilacion ObjectStoreVerifier"

Write-Host "Verificando BL-MVP-016..."
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
Write-Host "OK: BL-MVP-016 preparado y puerta local aprobada."
Write-Host "Siguiente: .\scripts\local\start.ps1"
Write-Host "Luego:      .\scripts\local\verify-running.ps1"
Write-Host "Despues:    .\scripts\database\verify-object-store.ps1"

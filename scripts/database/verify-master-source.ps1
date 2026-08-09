$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $Root

$MasterPath = Join-Path $Root "database\postgresql\master\MVP_PostgreSQL_18_Master.sql"
$SchemaPath = Join-Path $Root "database\postgresql\migrations\sql\01_initial_schema.sql"
$SeedPath = Join-Path $Root "database\postgresql\migrations\sql\02_seed_mvp.sql"

foreach ($path in @($MasterPath, $SchemaPath, $SeedPath)) {
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Falta el archivo fisico requerido: $path"
    }
}

$masterHash = (Get-FileHash $MasterPath -Algorithm SHA256).Hash.ToLowerInvariant()
$schemaHash = (Get-FileHash $SchemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
$seedHash = (Get-FileHash $SeedPath -Algorithm SHA256).Hash.ToLowerInvariant()

if ($masterHash -ne "da46cc9637c5b564f600f05b1c3dc4f16b6fc9ce161bf1f2943c2f9eb4929efa") {
    throw "El SQL maestro no coincide con la fuente autoritativa adjunta."
}

if ($schemaHash -ne "bbd1e1500bdae63fee91028b37f9d23a2880cde1325d346e8f7a390d3c8f4ab8") {
    throw "01_initial_schema.sql fue modificado respecto al SQL maestro."
}

if ($seedHash -ne "d031be0126447ac52474e5f86694c4c21e909514f981f679fa44d13fbcc59193") {
    throw "02_seed_mvp.sql fue modificado respecto al SQL maestro."
}

$master = [System.IO.File]::ReadAllText($MasterPath, [System.Text.Encoding]::UTF8)
$schema = [System.IO.File]::ReadAllText($SchemaPath, [System.Text.Encoding]::UTF8)
$seed = [System.IO.File]::ReadAllText($SeedPath, [System.Text.Encoding]::UTF8)

$schemaMarker = "-- PostgreSQL 18 - esquema físico inicial del MVP"
$seedMarker = "-- PostgreSQL 18 - datos semilla mínimos y deterministas del MVP"

$schemaStart = $master.IndexOf($schemaMarker, [System.StringComparison]::Ordinal)
$seedStart = $master.IndexOf($seedMarker, [System.StringComparison]::Ordinal)

if ($schemaStart -lt 0 -or $seedStart -le $schemaStart) {
    throw "No se encontraron los limites esperados dentro del SQL maestro."
}

$expectedSchema = $master.Substring($schemaStart, $seedStart - $schemaStart)
$expectedSeed = $master.Substring($seedStart)

if (-not [string]::Equals($schema, $expectedSchema, [System.StringComparison]::Ordinal)) {
    throw "01_initial_schema.sql no es una seccion exacta del SQL maestro."
}

if (-not [string]::Equals($seed, $expectedSeed, [System.StringComparison]::Ordinal)) {
    throw "02_seed_mvp.sql no es una seccion exacta del SQL maestro."
}

$migrationSource = [System.IO.File]::ReadAllText(
    (Join-Path $Root "tools\DatabaseMigrator\Migrations\InitialPhysicalSchema.cs"))

if ($migrationSource -match 'File\.ReadAllText|File\.Open|Path\.Combine') {
    throw "InitialPhysicalSchema no debe resolver SQL mediante rutas del servidor."
}

Write-Host "OK: SQL maestro y recursos de migracion coinciden byte a byte con la fuente autoritativa."

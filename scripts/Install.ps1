param(
    [string]$Server = 'localhost',
    [int]$Port = 5433,
    [string]$Admin = 'postgres',
    [ValidatePattern('^[a-z][a-z0-9_]*$')]
    [string]$Database = 'postsystem',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin'
)

$ErrorActionPreference = 'Stop'
$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { $psql = 'psql' }
$connection = @('-X', '-v', 'ON_ERROR_STOP=1', '-h', $Server, '-p', "$Port", '-U', $Admin)
$existing = & $psql @connection -d postgres -At -c "SELECT count(*) FROM pg_database WHERE datname = '$Database';"
if ($LASTEXITCODE -ne 0) { throw 'Cannot connect to PostgreSQL.' }
if ($existing -eq '0') {
    & $psql @connection -d postgres -c "CREATE DATABASE $Database ENCODING 'UTF8' TEMPLATE template0;"
    if ($LASTEXITCODE -ne 0) { throw 'Database creation failed.' }
}
$schema = & $psql @connection -d $Database -At -c "SELECT count(*) FROM pg_namespace WHERE nspname='postal';"
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the database.' }
if ($schema -ne '0') { throw 'Schema postal already exists. Choose an empty database; existing data was preserved.' }
& $psql @connection -d $Database -1 -f (Join-Path $PSScriptRoot '../db/install.sql')
if ($LASTEXITCODE -ne 0) { throw 'Installation failed; transaction was rolled back.' }
Write-Host "Installed database $Database on ${Server}:$Port."

param(
    [string]$Server = 'localhost',
    [int]$Port = 5433,
    [string]$Admin = 'postgres',
    [string]$Database = 'postsystem',
    [string]$PgBin = 'C:\Program Files\PostgreSQL\18\bin'
)

$ErrorActionPreference = 'Stop'
if (-not $env:POSTSYSTEM_APP_PASSWORD) {
    throw 'Set POSTSYSTEM_APP_PASSWORD to the password for the new application login.'
}
$psql = Join-Path $PgBin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { $psql = 'psql' }
$connection = @('-X', '-v', 'ON_ERROR_STOP=1', '-h', $Server, '-p', "$Port", '-U', $Admin, '-d', $Database)
& $psql @connection -1 -f (Join-Path $PSScriptRoot '../db/005_access.sql')
if ($LASTEXITCODE -ne 0) { throw 'Access setup failed.' }
& $psql @connection -1 -f (Join-Path $PSScriptRoot '../db/create_login.sql')
if ($LASTEXITCODE -ne 0) { throw 'Application login creation failed.' }
Write-Host 'Created postsystem_local. Use this login for the console application.'

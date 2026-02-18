param(
  [Parameter(Mandatory = $false)]
  [string]$Query = "",

  [Parameter(Mandatory = $false)]
  [string]$File = "",

  [Parameter(Mandatory = $false)]
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Load-DotEnv([string]$path) {
  if (-not (Test-Path $path)) { return }
  Get-Content $path | ForEach-Object {
    $line = $_
    if ($line -match '^\s*#' -or $line -match '^\s*$') { return }
    if ($line -match '^\s*([^=]+)=(.*)\s*$') {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Trim('"') }
      [Environment]::SetEnvironmentVariable($k, $v, "Process")
    }
  }
}

function Normalize-DbUrl([string]$url) {
  if ([string]::IsNullOrWhiteSpace($url)) { return $url }
  if (-not $url.StartsWith("postgresql://")) { return $url }

  $scheme = "postgresql://"
  $rest = $url.Substring($scheme.Length)
  $at = $rest.LastIndexOf("@")
  if ($at -lt 0) { return $url }

  $userinfo = $rest.Substring(0, $at)
  $hostpart = $rest.Substring($at + 1)

  $colon = $userinfo.IndexOf(":")
  if ($colon -lt 0) { return $url }

  $user = $userinfo.Substring(0, $colon)
  $pass = $userinfo.Substring($colon + 1)

  try {
    $decoded = [System.Uri]::UnescapeDataString($pass)
    $encoded = [System.Uri]::EscapeDataString($decoded)
    return "$scheme$user`:$encoded@$hostpart"
  } catch {
    return $url
  }
}

if (-not $Quiet) { Write-Host "SQL Runner (psql) - Supabase Remote" }
Load-DotEnv (Join-Path $PSScriptRoot "..\\.env")

$dbUrl = [string][Environment]::GetEnvironmentVariable("SUPABASE_DB_URL")
if ([string]::IsNullOrWhiteSpace($dbUrl)) {
  throw "Missing env var: SUPABASE_DB_URL (set it in .env; see .env.example)"
}
$dbUrl = Normalize-DbUrl $dbUrl

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
  throw "psql not found. Install PostgreSQL Command Line Tools (psql) and reopen your terminal."
}

if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($File)) {
  throw "Usage: scripts\\sql.ps1 -Query 'select now();' OR scripts\\sql.ps1 -File path\\to\\file.sql"
}

if (-not [string]::IsNullOrWhiteSpace($Query) -and -not [string]::IsNullOrWhiteSpace($File)) {
  throw "Pass only one: -Query or -File"
}

$args = @($dbUrl, "-v", "ON_ERROR_STOP=1")
if (-not [string]::IsNullOrWhiteSpace($Query)) {
  $args += @("-c", $Query)
} else {
  if (-not (Test-Path $File)) { throw "SQL file not found: $File" }
  $args += @("-f", $File)
}

& psql @args

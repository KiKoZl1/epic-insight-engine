param(
  [string]$SurfaceFrontend = "CreativeDiscoverySurface_Frontend",
  [string]$SurfaceBrowse = "CreativeDiscoverySurface_Browse",
  [string]$LinksSample1 = "playlist_trios",
  [string]$LinksSample2 = "set_br_playlists"
)

$ErrorActionPreference = "Stop"

function Require-Env($name) {
  $v = [string][Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($v)) {
    throw "Missing env var: $name"
  }
  return $v
}

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

function CurlJsonToFile([string]$method, [string]$url, [hashtable]$headers, [string]$body, [string]$outFile) {
  $args = @("-sS", "-X", $method, $url, "--max-time", "25", "-o", $outFile, "-w", "%{http_code}")
  foreach ($k in $headers.Keys) { $args += @("-H", ("{0}: {1}" -f $k, $headers[$k])) }
  if ($null -ne $body -and $body.Length -gt 0) {
    $args += @("--data-raw", $body)
  }
  $status = & curl.exe @args
  return [int]$status
}

function CurlToFile([string]$method, [string]$url, [hashtable]$headers, [string]$outFile) {
  $args = @("-sS", "-X", $method, $url, "--max-time", "25", "-o", $outFile, "-w", "%{http_code}")
  foreach ($k in $headers.Keys) { $args += @("-H", ("{0}: {1}" -f $k, $headers[$k])) }
  $status = & curl.exe @args
  return [int]$status
}

Write-Host "Epic Discovery API Spike"
Write-Host "- Uses DeviceAuth to mint EG1 bearer"
Write-Host "- Saves responses in scripts/_out/spike_*/"

$clientId = Require-Env "EPIC_OAUTH_CLIENT_ID"
$clientSecret = Require-Env "EPIC_OAUTH_CLIENT_SECRET"
$accountId = Require-Env "EPIC_DEVICE_AUTH_ACCOUNT_ID"
$deviceId = Require-Env "EPIC_DEVICE_AUTH_DEVICE_ID"
$deviceSecret = Require-Env "EPIC_DEVICE_AUTH_SECRET"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $PSScriptRoot "_out\\spike_$ts"
Ensure-Dir $outDir

# 1) Mint access token (EG1)
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$clientId`:$clientSecret"))
$tokFile = Join-Path $outDir "oauth_token.json"
$tokStatus = CurlJsonToFile "POST" "https://account-public-service-prod.ol.epicgames.com/account/api/oauth/token" @{
  "Authorization" = "Basic $basic"
  "Content-Type"  = "application/x-www-form-urlencoded"
  "Accept"        = "application/json"
} ("grant_type=device_auth&account_id=$accountId&device_id=$deviceId&secret=$deviceSecret&token_type=eg1") $tokFile

if ($tokStatus -ne 200) {
  Write-Host "oauth/token failed HTTP $tokStatus"
  Write-Host "See: $tokFile"
  exit 2
}

$tok = Get-Content $tokFile -Raw | ConvertFrom-Json
if (-not $tok.access_token) {
  Write-Host "oauth/token response missing access_token"
  Write-Host "See: $tokFile"
  exit 3
}

$access = [string]$tok.access_token
Write-Host ("- account_id: {0}" -f $tok.account_id)
Write-Host ("- access_token_len: {0}" -f $access.Length)

$results = @()

# 2) Hotconfig (no auth)
$hotFile = Join-Path $outDir "fn_hotconfig_livefn.json"
$st = CurlToFile "GET" "https://fn-hotconfigs.ogs.live.on.epicgames.com/hotconfigs/v2/livefn.json" @{"Accept"="application/json"} $hotFile
$results += [pscustomobject]@{ name="hotconfig_livefn"; http=$st; file=$hotFile }

# 3) FN version (get branch + changelist)
$verFile = Join-Path $outDir "fn_version.json"
$st = CurlJsonToFile "GET" "https://fngw-mcp-gc-livefn.ol.epicgames.com/fortnite/api/version" @{
  "Authorization" = "Bearer $access"
  "Accept"        = "application/json"
  "User-Agent"    = "Fortnite/Windows"
} "" $verFile
$results += [pscustomobject]@{ name="fn_version"; http=$st; file=$verFile }

$ver = $null
try { $ver = Get-Content $verFile -Raw | ConvertFrom-Json } catch {}
if ($ver -and $ver.version -and $ver.cln) {
  $branchStr = "++Fortnite+Release-$($ver.version)"
  $branchEnc = [Uri]::EscapeDataString($branchStr)
  $cln = [string]$ver.cln

  Write-Host ("- branch: {0}" -f $branchStr)
  Write-Host ("- cln: {0}" -f $cln)

  # 4) Discovery accessToken (needed for surface/config in some cases)
  $discTokFile = Join-Path $outDir "discovery_access_token.json"
  $st = CurlJsonToFile "GET" "https://fngw-mcp-gc-livefn.ol.epicgames.com/fortnite/api/discovery/accessToken/$branchEnc" @{
    "Authorization" = "Bearer $access"
    "Accept"        = "application/json"
    "User-Agent"    = "Fortnite/$branchStr Windows/10"
  } "" $discTokFile
  $results += [pscustomobject]@{ name="discovery_access_token"; http=$st; file=$discTokFile }

  $discTok = $null
  try { $discTok = (Get-Content $discTokFile -Raw | ConvertFrom-Json).token } catch {}

  # 5) FN Discovery v2 surface config (high value: cohorts/panel config if permitted)
  foreach ($surface in @($SurfaceFrontend, $SurfaceBrowse)) {
    $cfgFile = Join-Path $outDir ("discovery_v2_surface_config_{0}.json" -f $surface)
    $hdrs = @{
      "Authorization" = "Bearer $access"
      "Accept"        = "application/json"
      "User-Agent"    = "Fortnite/$branchStr Windows/10"
    }
    if ($discTok) { $hdrs["X-Epic-Access-Token"] = $discTok }
    $st = CurlJsonToFile "GET" ("https://fn-service-discovery-live-public.ogs.live.on.epicgames.com/api/v2/discovery/surface/{0}/config" -f $surface) $hdrs "" $cfgFile
    $results += [pscustomobject]@{ name=("v2_surface_config:{0}" -f $surface); http=$st; file=$cfgFile }
  }

  # 6) DAD assets for FortCreativeDiscoverySurface (highest value; may be permission-gated)
  $dadFile = Join-Path $outDir "dad_FortCreativeDiscoverySurface.json"
  $dadBody = '{"FortCreativeDiscoverySurface":0}'
  $dadUrl = "https://data-asset-directory-public-service-prod.ol.epicgames.com/api/v1/assets/Fortnite/$branchEnc/$cln?appId=Fortnite"
  $st = CurlJsonToFile "POST" $dadUrl @{
    "Authorization" = "Bearer $access"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
    "User-Agent"    = "Fortnite/$branchStr Windows/10"
  } $dadBody $dadFile
  $results += [pscustomobject]@{ name="dad_assets:FortCreativeDiscoverySurface"; http=$st; file=$dadFile }

  # 7) Calendar timeline (context for "why things changed"; permission-gated)
  $calFile = Join-Path $outDir "fn_calendar_timeline.json"
  $st = CurlJsonToFile "GET" "https://fngw-mcp-gc-livefn.ol.epicgames.com/fortnite/api/calendar/v1/timeline" @{
    "Authorization" = "Bearer $access"
    "Accept"        = "application/json"
    "User-Agent"    = "Fortnite/$branchStr Windows/10"
  } "" $calFile
  $results += [pscustomobject]@{ name="calendar_timeline"; http=$st; file=$calFile }
} else {
  Write-Host "WARN: couldn't parse version/cln from fn_version; skipping branch-dependent calls."
}

# 8) Links related (expand collections graph + screenshots + square thumbs)
foreach ($mn in @($LinksSample1, $LinksSample2)) {
  $file = Join-Path $outDir ("links_related_{0}.json" -f $mn)
  $st = CurlJsonToFile "GET" ("https://links-public-service-live.ol.epicgames.com/links/api/fn/mnemonic/{0}/related" -f $mn) @{
    "Authorization" = "Bearer $access"
    "Accept"        = "application/json"
  } "" $file
  $results += [pscustomobject]@{ name=("links_related:{0}" -f $mn); http=$st; file=$file }
}

Write-Host ""
Write-Host "Results:"
$results | Format-Table -AutoSize
Write-Host ""
Write-Host ("Output dir: {0}" -f $outDir)

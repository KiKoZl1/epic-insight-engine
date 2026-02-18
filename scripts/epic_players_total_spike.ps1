param(
  [string[]]$Regions = @("NAE","EU","BR","ASIA"),
  [string[]]$Surfaces = @("CreativeDiscoverySurface_Frontend","CreativeDiscoverySurface_Browse"),
  [int]$MaxPanelsPerSurface = 12,
  [int]$MaxPagesPerPanel = 3,
  [string[]]$SearchTerms = @("1v1","box","ffa","tycoon","horror","roleplay","pve","zone wars","red vs blue","gun game"),
  [int]$SearchPagesPerTerm = 8,
  [int]$MaxSearchCodes = 12000,
  [string]$SearchLocale = "en-US",
  [int]$MaxCollectionsToExpand = 300,
  [int]$MaxPlayableCodes = 3000,
  [int]$RequestSleepMs = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Env($name) {
  $v = [string][Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($v)) {
    throw "Missing env var: $name"
  }
  return $v
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function To-Base64([string]$s) {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
}

function Invoke-JsonHttp {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("GET","POST")][string]$Method,
    [Parameter(Mandatory=$true)][string]$Url,
    [hashtable]$Headers = @{},
    [string]$ContentType,
    [string]$Body,
    [int]$TimeoutSec = 25
  )

  $status = -1
  $raw = $null
  $json = $null
  $ok = $false
  $err = $null

  try {
    $args = @{
      Uri = $Url
      Method = $Method
      Headers = $Headers
      TimeoutSec = $TimeoutSec
      UseBasicParsing = $true
    }
    if ($ContentType) { $args.ContentType = $ContentType }
    if ($Body) { $args.Body = $Body }

    $resp = Invoke-WebRequest @args
    $status = [int]$resp.StatusCode
    $raw = $resp.Content
    $ok = ($status -ge 200 -and $status -lt 300)
  } catch {
    $ex = $_.Exception
    $err = $ex.Message
    if ($ex.Response) {
      try { $status = [int]$ex.Response.StatusCode.value__ } catch { $status = -1 }
      try {
        $stream = $ex.Response.GetResponseStream()
        if ($stream) {
          $reader = New-Object System.IO.StreamReader($stream)
          $raw = $reader.ReadToEnd()
        }
      } catch {
        $raw = $null
      }
    } else {
      $raw = $err
    }
    $ok = $false
  }

  if ($raw) {
    try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
  }

  return [pscustomobject]@{
    ok = $ok
    status = $status
    raw = $raw
    json = $json
    error = $err
  }
}

function Get-PropValue($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

function Parse-RelatedCodes {
  param([object]$Payload)

  $codes = New-Object "System.Collections.Generic.HashSet[string]"

  $addCode = {
    param($v)
    if ($null -eq $v) { return }
    $s = [string]$v
    if ([string]::IsNullOrWhiteSpace($s)) { return }
    [void]$codes.Add($s.Trim())
  }

  $meta = Get-PropValue $Payload "metadata"
  if ($meta) {
    $ccuSource = Get-PropValue $meta "ccu_source_links"
    if ($ccuSource -is [System.Collections.IEnumerable]) {
      foreach ($c in @($ccuSource)) { & $addCode $c }
    }

    $subs = Get-PropValue $meta "sub_link_codes"
    if ($subs -is [System.Collections.IEnumerable]) {
      foreach ($c in @($subs)) { & $addCode $c }
    }

    $dsub = Get-PropValue $meta "default_sub_link_code"
    if ($dsub) { & $addCode $dsub }

    $fallback = Get-PropValue $meta "fallback_links"
    if ($fallback) {
      foreach ($p in $fallback.PSObject.Properties) { & $addCode $p.Value }
    }
  }

  $links = Get-PropValue $Payload "links"
  if ($links) {
    foreach ($p in $links.PSObject.Properties) { & $addCode $p.Name }
  }

  $parents = Get-PropValue $Payload "parentLinks"
  if ($parents -is [System.Collections.IEnumerable]) {
    foreach ($pl in @($parents)) {
      $mn = Get-PropValue $pl "mnemonic"
      if ($mn) { & $addCode $mn }
    }
  }

  return @($codes)
}

function Is-CcuPlayableCode([string]$code) {
  if ($code -match '^\d{4}-\d{4}-\d{4}$') { return $true }
  if ($code.StartsWith("playlist_")) { return $true }
  if ($code.StartsWith("experience_")) { return $true }
  return $false
}

function Process-SearchResults {
  param(
    [array]$Results,
    [System.Collections.Generic.HashSet[string]]$SearchCodeSet,
    [System.Collections.Generic.HashSet[string]]$CollectionCodeSet,
    [int]$MaxCodes,
    [scriptblock]$AddCcu
  )

  $newCodes = 0
  foreach ($r in $Results) {
    $code = [string](Get-PropValue $r "linkCode")
    if ([string]::IsNullOrWhiteSpace($code)) { continue }

    if (-not $SearchCodeSet.Contains($code)) {
      if ($SearchCodeSet.Count -ge $MaxCodes) { break }
      [void]$SearchCodeSet.Add($code)
      $newCodes++
    }

    & $AddCcu $code (Get-PropValue $r "globalCCU")
    if (-not (Is-CcuPlayableCode $code)) {
      [void]$CollectionCodeSet.Add($code)
    }
  }
  return $newCodes
}

Write-Host "Epic Players Total Spike"
Write-Host "- Source: Discovery + Links (Epic APIs)"
Write-Host "- Output: scripts/_out/players_total_spike"
Write-Host ""

$clientId = Require-Env "EPIC_OAUTH_CLIENT_ID"
$clientSecret = Require-Env "EPIC_OAUTH_CLIENT_SECRET"
$accountId = Require-Env "EPIC_DEVICE_AUTH_ACCOUNT_ID"
$deviceId = Require-Env "EPIC_DEVICE_AUTH_DEVICE_ID"
$deviceSecret = Require-Env "EPIC_DEVICE_AUTH_SECRET"

$baseOut = Join-Path $PSScriptRoot "_out\\players_total_spike"
Ensure-Dir $baseOut
$runTs = Get-Date -Format "yyyyMMdd_HHmmss"
$runDir = Join-Path $baseOut ("run_" + $runTs)
Ensure-Dir $runDir

# 1) Device auth -> access token (EG1)
$basic = To-Base64 ("{0}:{1}" -f $clientId, $clientSecret)
$tokenBody = "grant_type=device_auth&account_id=$accountId&device_id=$deviceId&secret=$deviceSecret&token_type=eg1"
$tokenResp = Invoke-JsonHttp -Method "POST" -Url "https://account-public-service-prod.ol.epicgames.com/account/api/oauth/token" -Headers @{
  Authorization = "Basic $basic"
  Accept = "application/json"
} -ContentType "application/x-www-form-urlencoded" -Body $tokenBody

if (-not $tokenResp.ok) {
  throw ("oauth/token failed: HTTP {0} {1}" -f $tokenResp.status, $tokenResp.error)
}

$access = [string]$tokenResp.json.access_token
if (-not $access) { throw "oauth/token returned empty access_token" }

# 2) branch/version
$verResp = Invoke-JsonHttp -Method "GET" -Url "https://fngw-mcp-gc-livefn.ol.epicgames.com/fortnite/api/version" -Headers @{
  Authorization = "Bearer $access"
  Accept = "application/json"
  "User-Agent" = "Fortnite/Windows"
}
if (-not $verResp.ok) { throw "fortnite/api/version failed: HTTP $($verResp.status)" }

$version = [string]$verResp.json.version
$branch = "++Fortnite+Release-$version"
$branchEnc = [Uri]::EscapeDataString($branch)

# 3) discovery access token (X-Epic-Access-Token)
$discResp = Invoke-JsonHttp -Method "GET" -Url ("https://fngw-mcp-gc-livefn.ol.epicgames.com/fortnite/api/discovery/accessToken/{0}" -f $branchEnc) -Headers @{
  Authorization = "Bearer $access"
  Accept = "application/json"
  "User-Agent" = "Fortnite/$branch Windows/10"
}
if (-not $discResp.ok) { throw "discovery/accessToken failed: HTTP $($discResp.status)" }

$discAccessToken = [string]$discResp.json.token
if (-not $discAccessToken) { throw "discovery access token empty" }

$ccuByCode = @{}
$surfaceCodes = New-Object "System.Collections.Generic.HashSet[string]"
$collectionCodes = New-Object "System.Collections.Generic.HashSet[string]"

$addCcu = {
  param([string]$code, $ccuRaw)
  if ([string]::IsNullOrWhiteSpace($code)) { return }
  $ccu = 0
  try { $ccu = [int]$ccuRaw } catch { $ccu = 0 }
  if ($ccu -lt 0) { return }
  if (-not $ccuByCode.ContainsKey($code)) {
    $ccuByCode[$code] = $ccu
  } else {
    $ccuByCode[$code] = [Math]::Max([int]$ccuByCode[$code], $ccu)
  }
}

function Process-DiscoveryResults {
  param([array]$Results)
  foreach ($r in $Results) {
    $code = [string](Get-PropValue $r "linkCode")
    if ([string]::IsNullOrWhiteSpace($code)) { continue }
    [void]$surfaceCodes.Add($code)
    & $addCcu $code (Get-PropValue $r "globalCCU")
    if (-not (Is-CcuPlayableCode $code)) {
      [void]$collectionCodes.Add($code)
    }
  }
}

# 4) Pull discovery pages for selected regions/surfaces
foreach ($region in $Regions) {
  foreach ($surface in $Surfaces) {
    $surfaceBody = @{
      playerId = $accountId
      partyMemberIds = @($accountId)
      locale = "en"
      matchmakingRegion = $region
      platform = "Windows"
      isCabined = $false
      ratingAuthority = "ESRB"
      rating = "TEEN"
      numLocalPlayers = 1
    } | ConvertTo-Json -Depth 6 -Compress

    $surfaceUrl = "https://fn-service-discovery-live-public.ogs.live.on.epicgames.com/api/v2/discovery/surface/{0}?appId=Fortnite&stream={1}" -f $surface, ([Uri]::EscapeDataString($branch))
    $surfaceResp = Invoke-JsonHttp -Method "POST" -Url $surfaceUrl -Headers @{
      Authorization = "Bearer $access"
      "X-Epic-Access-Token" = $discAccessToken
      Accept = "application/json"
    } -ContentType "application/json" -Body $surfaceBody

    if (-not $surfaceResp.ok) {
      Write-Host ("WARN surface failed {0}/{1} HTTP {2}" -f $region, $surface, $surfaceResp.status)
      continue
    }

    $testVariantName = [string](Get-PropValue $surfaceResp.json "testVariantName")
    if (-not $testVariantName) { $testVariantName = "Baseline" }
    $panels = @((Get-PropValue $surfaceResp.json "panels"))
    if ($panels.Count -gt $MaxPanelsPerSurface) { $panels = $panels[0..($MaxPanelsPerSurface - 1)] }

    foreach ($p in $panels) {
      $panelName = [string](Get-PropValue $p "panelName")
      $fp = Get-PropValue $p "firstPage"
      $fpResults = @((Get-PropValue $fp "results"))
      if ($fpResults.Count -gt 0) { Process-DiscoveryResults -Results $fpResults }

      for ($page=0; $page -lt $MaxPagesPerPanel; $page++) {
        $pageBody = @{
          testVariantName = $testVariantName
          panelName = $panelName
          pageIndex = $page
          playerId = $accountId
          partyMemberIds = @($accountId)
          locale = "en"
          matchmakingRegion = $region
          platform = "Windows"
          isCabined = $false
          ratingAuthority = "ESRB"
          rating = "TEEN"
          numLocalPlayers = 1
        } | ConvertTo-Json -Depth 6 -Compress

        $pageUrl = "https://fn-service-discovery-live-public.ogs.live.on.epicgames.com/api/v2/discovery/surface/{0}/page?appId=Fortnite&stream={1}" -f $surface, ([Uri]::EscapeDataString($branch))
        $pageResp = Invoke-JsonHttp -Method "POST" -Url $pageUrl -Headers @{
          Authorization = "Bearer $access"
          "X-Epic-Access-Token" = $discAccessToken
          Accept = "application/json"
        } -ContentType "application/json" -Body $pageBody

        if (-not $pageResp.ok) { break }
        $results = @((Get-PropValue $pageResp.json "results"))
        if ($results.Count -eq 0) { break }
        Process-DiscoveryResults -Results $results
        Start-Sleep -Milliseconds $RequestSleepMs
      }
    }
  }
}

# 5) V2: Crawl island-search pages (globalCCU ordered) to increase coverage.
$searchUrl = "https://fngw-svc-gc-livefn.ol.epicgames.com/api/island-search/v1/search?accountId=$accountId"
$searchCodeSet = New-Object "System.Collections.Generic.HashSet[string]"
$searchStats = [ordered]@{
  terms = $SearchTerms.Count
  pages_attempted = 0
  calls_ok = 0
  calls_failed = 0
  rows_seen = 0
  unique_codes = 0
}

foreach ($term in $SearchTerms) {
  if ($searchCodeSet.Count -ge $MaxSearchCodes) { break }
  $stalePages = 0

  for ($page = 0; $page -lt $SearchPagesPerTerm; $page++) {
    if ($searchCodeSet.Count -ge $MaxSearchCodes) { break }

    $searchBody = @{
      namespace = "fortnite"
      context = @()
      locale = $SearchLocale
      search = [string]$term
      orderBy = "globalCCU"
      ratingAuthority = ""
      rating = ""
      page = $page
    } | ConvertTo-Json -Depth 6 -Compress

    $searchResp = Invoke-JsonHttp -Method "POST" -Url $searchUrl -Headers @{
      Authorization = "Bearer $access"
      Accept = "application/json"
    } -ContentType "application/json" -Body $searchBody

    $searchStats.pages_attempted++
    if (-not $searchResp.ok) {
      $searchStats.calls_failed++
      break
    }

    $searchStats.calls_ok++
    $rows = @((Get-PropValue $searchResp.json "results"))
    if ($rows.Count -eq 0) { break }
    $searchStats.rows_seen += $rows.Count

    $added = Process-SearchResults -Results $rows -SearchCodeSet $searchCodeSet -CollectionCodeSet $collectionCodes -MaxCodes $MaxSearchCodes -AddCcu $addCcu
    if ($added -le 0) {
      $stalePages++
    } else {
      $stalePages = 0
    }

    if ($rows.Count -lt 20) { break }
    if ($stalePages -ge 3) { break }
    Start-Sleep -Milliseconds $RequestSleepMs
  }
}
$searchStats.unique_codes = $searchCodeSet.Count

# 6) Expand collections via /related and extract ccu_source_links
$seedCollections = @(
  "set_br_playlists",
  "set_delmar_casual",
  "set_delmar_mrs_ranked",
  "reference_current_island",
  "reference_nestedtrendingindiscover_1"
)

$toVisit = New-Object "System.Collections.Generic.Queue[string]"
$seenCollections = New-Object "System.Collections.Generic.HashSet[string]"
$playableCodes = New-Object "System.Collections.Generic.HashSet[string]"

foreach ($c in $seedCollections) { if (-not [string]::IsNullOrWhiteSpace($c)) { $toVisit.Enqueue($c) } }
foreach ($c in $collectionCodes) { $toVisit.Enqueue($c) }

$expanded = 0
while ($toVisit.Count -gt 0 -and $expanded -lt $MaxCollectionsToExpand -and $playableCodes.Count -lt $MaxPlayableCodes) {
  $code = [string]$toVisit.Dequeue()
  if ([string]::IsNullOrWhiteSpace($code)) { continue }
  if ($seenCollections.Contains($code)) { continue }
  [void]$seenCollections.Add($code)

  $relUrl = "https://links-public-service-live.ol.epicgames.com/links/api/fn/mnemonic/$([Uri]::EscapeDataString($code))/related"
  $relResp = Invoke-JsonHttp -Method "GET" -Url $relUrl -Headers @{
    Authorization = "Bearer $access"
    Accept = "application/json"
  }
  $expanded++
  if (-not $relResp.ok -or $null -eq $relResp.json) { continue }

  $relatedCodes = Parse-RelatedCodes -Payload $relResp.json
  foreach ($rc in $relatedCodes) {
    if (Is-CcuPlayableCode $rc) {
      [void]$playableCodes.Add($rc)
    } else {
      if (-not $seenCollections.Contains($rc)) { $toVisit.Enqueue($rc) }
    }
  }

  Start-Sleep -Milliseconds $RequestSleepMs
}

# 7) Fetch CCU for playable codes using link-entries
$playableArr = @($playableCodes)
if ($playableArr.Count -gt $MaxPlayableCodes) { $playableArr = $playableArr[0..($MaxPlayableCodes - 1)] }

for ($i=0; $i -lt $playableArr.Count; $i += 200) {
  $chunk = $playableArr[$i..([Math]::Min($i + 199, $playableArr.Count - 1))]
  $body = (@{ linkCodes = @($chunk) } | ConvertTo-Json -Depth 4 -Compress)
  $leResp = Invoke-JsonHttp -Method "POST" -Url "https://fn-service-discovery-live-public.ogs.live.on.epicgames.com/api/v2/discovery/link-entries" -Headers @{
    Authorization = "Bearer $access"
    "X-Epic-Access-Token" = $discAccessToken
    Accept = "application/json"
  } -ContentType "application/json" -Body $body

  if ($leResp.ok -and $leResp.json) {
    foreach ($p in $leResp.json.PSObject.Properties) {
      $code = [string]$p.Name
      $v = $p.Value
      $ccu = Get-PropValue $v "globalCCU"
      & $addCcu $code $ccu
    }
  }
  Start-Sleep -Milliseconds $RequestSleepMs
}

# 8) Compute totals + peaks from local snapshots
$positive = @()
foreach ($k in $ccuByCode.Keys) {
  $v = [int]$ccuByCode[$k]
  if ($v -gt 0) {
    $positive += [pscustomobject]@{ code = $k; ccu = $v }
  }
}
$totalNow = ($positive | Measure-Object -Property ccu -Sum).Sum
if ($null -eq $totalNow) { $totalNow = 0 }

$topNow = $positive | Sort-Object ccu -Descending | Select-Object -First 25

$snapshot = [ordered]@{
  ts = (Get-Date).ToString("o")
  branch = $branch
  version = $version
  regions = $Regions
  surfaces = $Surfaces
  players_now_estimate = [int]$totalNow
  tracked_codes_total = $ccuByCode.Count
  tracked_codes_positive = $positive.Count
  surface_codes_seen = $surfaceCodes.Count
  search = $searchStats
  collections_seen = $collectionCodes.Count
  collections_expanded = $expanded
  playable_codes_from_related = $playableArr.Count
  top_now = $topNow
}

$summaryPath = Join-Path $runDir "players_total_spike_summary.json"
($snapshot | ConvertTo-Json -Depth 8) | Set-Content -Encoding UTF8 -Path $summaryPath

$jsonlPath = Join-Path $baseOut "players_total_snapshots.jsonl"
($snapshot | ConvertTo-Json -Depth 8 -Compress) | Add-Content -Encoding UTF8 -Path $jsonlPath

$series = @()
if (Test-Path $jsonlPath) {
  foreach ($line in Get-Content $jsonlPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $series += ($line | ConvertFrom-Json) } catch {}
  }
}

$now = Get-Date
$dayAgo = $now.AddHours(-24)
$peak24 = 0
$allPeak = 0
foreach ($s in $series) {
  $val = 0
  try { $val = [int]$s.players_now_estimate } catch { $val = 0 }
  if ($val -gt $allPeak) { $allPeak = $val }
  try {
    $ts = [datetime]::Parse([string]$s.ts)
    if ($ts -ge $dayAgo -and $val -gt $peak24) { $peak24 = $val }
  } catch {}
}

Write-Host ""
Write-Host "Estimated Fortnite Player Totals (API Spike)"
Write-Host ("- Players right now (estimate): {0}" -f ([int]$totalNow).ToString("N0"))
Write-Host ("- 24-hour peak (local snapshots): {0}" -f ([int]$peak24).ToString("N0"))
Write-Host ("- All-time peak (local snapshots): {0}" -f ([int]$allPeak).ToString("N0"))
Write-Host ("- Tracked positive codes: {0}" -f $positive.Count)
Write-Host ""
Write-Host ("Summary JSON: {0}" -f $summaryPath)
Write-Host ("Snapshots JSONL: {0}" -f $jsonlPath)
Write-Host ""
Write-Host "Note: this is an estimate from Discovery + Links signals, not an official single global endpoint."

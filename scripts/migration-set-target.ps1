Param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRef,
  [Parameter(Mandatory = $true)]
  [string]$SupabaseUrl,
  [Parameter(Mandatory = $true)]
  [string]$PublishableKey
)

$ErrorActionPreference = "Stop"

function Upsert-EnvLine {
  Param(
    [string[]]$Lines,
    [string]$Key,
    [string]$Value
  )
  $pattern = "^\s*$([regex]::Escape($Key))\s*="
  $newLine = "$Key=`"$Value`""
  $idx = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match $pattern) {
      $idx = $i
      break
    }
  }
  if ($idx -ge 0) {
    $Lines[$idx] = $newLine
  } else {
    $Lines += $newLine
  }
  return ,$Lines
}

$repoRoot = (Get-Location).Path
$envPath = Join-Path $repoRoot ".env"
$configPath = Join-Path $repoRoot "supabase\config.toml"
$artifactsDir = Join-Path $repoRoot "migration_artifacts\logs"
if (!(Test-Path $artifactsDir)) {
  New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (Test-Path $envPath) {
  Copy-Item $envPath (Join-Path $artifactsDir ".env.backup.$stamp") -Force
} else {
  New-Item -ItemType File -Path $envPath -Force | Out-Null
}

if (Test-Path $configPath) {
  Copy-Item $configPath (Join-Path $artifactsDir "supabase.config.toml.backup.$stamp") -Force
} else {
  throw "Missing file: $configPath"
}

# Update .env keys
$envLines = Get-Content $envPath -ErrorAction SilentlyContinue
if ($null -eq $envLines) { $envLines = @() }
$envLines = Upsert-EnvLine -Lines $envLines -Key "VITE_SUPABASE_URL" -Value $SupabaseUrl
$envLines = Upsert-EnvLine -Lines $envLines -Key "VITE_SUPABASE_PUBLISHABLE_KEY" -Value $PublishableKey
$envLines = Upsert-EnvLine -Lines $envLines -Key "SUPABASE_URL" -Value $SupabaseUrl

if (-not ($envLines -match "^\s*SUPABASE_SERVICE_ROLE_KEY\s*=")) {
  $envLines += 'SUPABASE_SERVICE_ROLE_KEY="<set-manually>"'
}
if (-not ($envLines -match "^\s*OPENAI_API_KEY\s*=")) {
  $envLines += 'OPENAI_API_KEY="<set-manually>"'
}
if (-not ($envLines -match "^\s*OPENAI_MODEL\s*=")) {
  $envLines += 'OPENAI_MODEL="gpt-4.1-mini"'
}
if (-not ($envLines -match "^\s*OPENAI_TRANSLATION_MODEL\s*=")) {
  $envLines += 'OPENAI_TRANSLATION_MODEL="gpt-4.1-mini"'
}

Set-Content -Path $envPath -Value $envLines -Encoding UTF8

# Update Supabase config project_id
$cfg = Get-Content -Raw $configPath
$cfg2 = [regex]::Replace($cfg, 'project_id\s*=\s*"[a-z0-9]+"', "project_id = `"$ProjectRef`"")
if ($cfg2 -eq $cfg) {
  throw "Could not update project_id in supabase/config.toml"
}
Set-Content -Path $configPath -Value $cfg2 -Encoding UTF8

Write-Host "Target migration config updated."
Write-Host "- project_ref: $ProjectRef"
Write-Host "- supabase_url: $SupabaseUrl"
Write-Host "- backups: $artifactsDir"

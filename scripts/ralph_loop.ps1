param(
  [string]$Mode = "dev",
  [int]$DurationMinutes = 60,
  [int]$IntervalSeconds = 300,
  [int]$MaxIterations = 2,
  [string]$EditMode = "apply",
  [int]$EditMaxFiles = 2,
  [string]$EditAllowlist = "src/,index.html,docs/",
  [bool]$GateLint = $false,
  [bool]$GateBuild = $true,
  [bool]$GateTest = $true,
  [string]$LlmProvider = "openai",
  [string]$LlmModel = "gpt-4.1-mini",
  [string]$Scope = "csv,lookup",
  [string]$PromptFile = "",
  [int]$StopAfterConsecutiveFailures = 2
)

$ErrorActionPreference = "Stop"

function New-RunStamp {
  $d = Get-Date
  return "{0}{1:00}{2:00}_{3:00}{4:00}{5:00}" -f $d.Year, $d.Month, $d.Day, $d.Hour, $d.Minute, $d.Second
}

$repo = Get-Location
$outRoot = Join-Path $repo "scripts\_out\ralph_loop"
$runDir = Join-Path $outRoot ("run_" + (New-RunStamp))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$until = (Get-Date).AddMinutes($DurationMinutes)
$run = 0
$consecutiveFails = 0
$results = @()

while ((Get-Date) -lt $until) {
  $run++
  $start = Get-Date
  Write-Host ("[{0}] Ralph loop run #{1}" -f $start.ToString("HH:mm:ss"), $run)

  $runnerArgs = @(
    "--mode=$Mode",
    "--dry-run=false",
    "--llm-provider=$LlmProvider",
    "--llm-model=$LlmModel",
    "--scope=$Scope",
    "--max-iterations=$MaxIterations",
    "--edit-mode=$EditMode",
    "--edit-max-files=$EditMaxFiles",
    "--edit-allowlist=$EditAllowlist",
    "--gate-lint=$GateLint",
    "--gate-build=$GateBuild",
    "--gate-test=$GateTest"
  )
  if ($PromptFile) {
    $runnerArgs += "--prompt-file=$PromptFile"
  }

  $output = & scripts\run-ralph-local-runner.bat @runnerArgs 2>&1
  $exitCode = $LASTEXITCODE
  $output | ForEach-Object { Write-Host $_ }

  $summaryPath = $null
  foreach ($line in $output) {
    if ($line -match "^- summary:\s*(.+)$") {
      $summaryPath = $matches[1].Trim()
    }
  }

  $status = "unknown"
  $applied = 0
  $changedCount = 0
  $runId = $null
  if ($summaryPath -and (Test-Path $summaryPath)) {
    try {
      $j = Get-Content $summaryPath -Raw | ConvertFrom-Json
      $status = [string]$j.final_status
      if ($null -ne $j.applied_patches) {
        $applied = [int]$j.applied_patches
      } else {
        $applied = 0
      }
      $changedCount = if ($j.changed_files_after_run) { @($j.changed_files_after_run).Count } else { 0 }
      $runId = [string]$j.run_id
    } catch {
      $status = "summary_parse_error"
    }
  }

  $ok = ($exitCode -eq 0 -and $status -ne "failed")
  if ($ok) { $consecutiveFails = 0 } else { $consecutiveFails++ }

  $results += [pscustomobject]@{
    run = $run
    started_at = $start.ToString("o")
    exit_code = $exitCode
    status = $status
    run_id = $runId
    applied_changes = $applied
    changed_files = $changedCount
    summary_path = $summaryPath
  }

  Write-Host ("Run #{0} => exit={1} status={2} applied={3} changed_files={4}" -f $run, $exitCode, $status, $applied, $changedCount)

  if ($consecutiveFails -ge $StopAfterConsecutiveFailures) {
    Write-Host ("Stopping loop: {0} consecutive failures." -f $consecutiveFails)
    break
  }

  if ((Get-Date) -lt $until) {
    Start-Sleep -Seconds $IntervalSeconds
  }
}

$summaryOut = [pscustomobject]@{
  started_at = (Get-Date).ToString("o")
  duration_minutes = $DurationMinutes
  interval_seconds = $IntervalSeconds
  mode = $Mode
  edit_mode = $EditMode
  llm_provider = $LlmProvider
  llm_model = $LlmModel
  scope = $Scope
  runs_total = $results.Count
  runs_failed = @($results | Where-Object { $_.exit_code -ne 0 -or $_.status -eq "failed" }).Count
  runs_with_changes = @($results | Where-Object { $_.applied_changes -gt 0 }).Count
  results = $results
}

$summaryPath = Join-Path $runDir "ralph_loop_summary.json"
$summaryOut | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Ralph loop finished."
Write-Host ("- runs: {0}" -f $summaryOut.runs_total)
Write-Host ("- failed: {0}" -f $summaryOut.runs_failed)
Write-Host ("- runs with changes: {0}" -f $summaryOut.runs_with_changes)
Write-Host ("- summary: {0}" -f $summaryPath)

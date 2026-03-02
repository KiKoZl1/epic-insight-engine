param(
  [string]$Config = "ml/tgis/configs/base.yaml",
  [int]$MaxRuns = 1,
  [int]$IdleSleepSeconds = 20,
  [switch]$SkipCostSync
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$envPath = Join-Path $root ".env"
if (-not (Test-Path $envPath)) {
  throw ".env not found at $envPath"
}

Get-Content $envPath | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  $parts = $_ -split '=', 2
  if ($parts.Length -ne 2) { return }
  $k = $parts[0].Trim()
  $v = $parts[1].Trim()
  if ($v.StartsWith('"') -and $v.EndsWith('"')) {
    $v = $v.Substring(1, $v.Length - 2)
  }
  [Environment]::SetEnvironmentVariable($k, $v, "Process")
}
[Environment]::SetEnvironmentVariable("PYTHONUNBUFFERED", "1", "Process")

$artifactsDir = Join-Path $root "ml/tgis/artifacts"
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

$pidFile = Join-Path $artifactsDir "process_training_queue.pid"
$outLog = Join-Path $artifactsDir "process_training_queue.out.log"
$errLog = Join-Path $artifactsDir "process_training_queue.err.log"

if (Test-Path $pidFile) {
  $oldPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($oldPid) {
    $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($oldProc) {
      Stop-Process -Id $oldPid -Force
      Start-Sleep -Seconds 1
    }
  }
}

$args = @(
  "-m", "ml.tgis.runtime.local_worker_supervisor",
  "--config", $Config,
  "--max-training-runs", "$MaxRuns",
  "--poll-seconds", "$IdleSleepSeconds"
)
if ($SkipCostSync) {
  $args += "--skip-cost-sync"
}

$proc = Start-Process -FilePath "python" -ArgumentList $args -WorkingDirectory $root -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
Set-Content -Path $pidFile -Value $proc.Id

Write-Output "worker_started pid=$($proc.Id)"
Write-Output "stdout_log=$outLog"
Write-Output "stderr_log=$errLog"

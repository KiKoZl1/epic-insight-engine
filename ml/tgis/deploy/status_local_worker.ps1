$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$pidFile = Join-Path $root "ml/tgis/artifacts/process_training_queue.pid"
$outLog = Join-Path $root "ml/tgis/artifacts/process_training_queue.out.log"
$errLog = Join-Path $root "ml/tgis/artifacts/process_training_queue.err.log"

if (-not (Test-Path $pidFile)) {
  Write-Output "worker_running=false pid_file_missing=true"
  exit 0
}

$workerPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $workerPid) {
  Write-Output "worker_running=false pid_file_empty=true"
  exit 0
}

$proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
if ($proc) {
  Write-Output "worker_running=true pid=$workerPid started_at=$($proc.StartTime.ToString('s'))"
} else {
  Write-Output "worker_running=false pid=$workerPid"
}

if (Test-Path $outLog) {
  Write-Output "--- stdout tail ---"
  Get-Content $outLog -Tail 5
}
if (Test-Path $errLog) {
  Write-Output "--- stderr tail ---"
  Get-Content $errLog -Tail 5
}

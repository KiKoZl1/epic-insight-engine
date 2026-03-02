$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$pidFile = Join-Path $root "ml/tgis/artifacts/process_training_queue.pid"

if (-not (Test-Path $pidFile)) {
  Write-Output "worker_not_running (pid file missing)"
  exit 0
}

$workerPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $workerPid) {
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  Write-Output "worker_not_running (empty pid file)"
  exit 0
}

$proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
if ($proc) {
  Stop-Process -Id $workerPid -Force
  Write-Output "worker_stopped pid=$workerPid"
} else {
  Write-Output "worker_not_running pid=$workerPid"
}

Remove-Item $pidFile -Force -ErrorAction SilentlyContinue

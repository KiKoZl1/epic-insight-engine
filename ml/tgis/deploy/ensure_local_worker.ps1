$ErrorActionPreference = "Stop"

$root = (Resolve-Path ".").Path
$pidFile = Join-Path $root "ml/tgis/artifacts/process_training_queue.pid"
$startScript = Join-Path $root "ml/tgis/deploy/start_local_worker.ps1"

if (-not (Test-Path $startScript)) {
  throw "start_local_worker.ps1 not found at $startScript"
}

$isRunning = $false
if (Test-Path $pidFile) {
  $workerPid = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($workerPid) {
    $proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
    if ($proc) {
      $isRunning = $true
      Write-Output "worker_running=true pid=$workerPid"
    }
  }
}

if (-not $isRunning) {
  Write-Output "worker_running=false action=start"
  & powershell -ExecutionPolicy Bypass -File $startScript
}

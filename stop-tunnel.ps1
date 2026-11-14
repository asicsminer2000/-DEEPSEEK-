$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'network-config.ps1')
$config = Get-ImpulseConfig

New-Item -ItemType Directory -Force -Path $config.LogDir | Out-Null
Remove-Item -LiteralPath $config.StoppedFile -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath $config.StopFile -Value ([string]$PID) -Encoding ASCII

Write-Host 'Останавливаю localtunnel...' -ForegroundColor Cyan

# Wake the watchdog immediately; it still owns the final shutdown and writes
# the acknowledgement file. Do not delete the stop flag before that.
foreach ($process in Get-ImpulseTunnelProcesses) {
  try { Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop } catch {}
}

$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $config.StoppedFile)) {
  Start-Sleep -Milliseconds 500
}

if (-not (Test-Path -LiteralPath $config.StoppedFile)) {
  # The watchdog may be stuck in a network call. Stop it explicitly so it
  # cannot resurrect the tunnel later.
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match 'tunnel-watchdog\.ps1'
  } | ForEach-Object {
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
  }
  foreach ($process in Get-ImpulseTunnelProcesses) {
    try { Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop } catch {}
  }
}

Remove-Item -LiteralPath $config.StopFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $config.StoppedFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $config.PidFile -Force -ErrorAction SilentlyContinue
Write-Host 'Туннель остановлен. Запуск снова: start-tunnel.cmd' -ForegroundColor Green

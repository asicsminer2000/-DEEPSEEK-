$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'network-config.ps1')
$config = Get-ImpulseConfig

if (-not (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 3)) {
  Write-Host "Локальный сервер не отвечает: $($config.LocalUrl)/health" -ForegroundColor Red
  Write-Host 'Сначала запустите start-server.cmd или start-impulse.cmd.'
  Write-Host 'P2P-режим в клиенте работает и без локального сервера.'
  exit 1
}

$lt = Get-ImpulseLocaltunnelPath
$node = Get-ImpulseNodePath
if (-not $lt) {
  Write-Host 'localtunnel не установлен. Выполните: npm install' -ForegroundColor Red
  exit 1
}
if (-not $node) {
  Write-Host 'Не найден Node.js или Electron для запуска localtunnel.' -ForegroundColor Red
  exit 1
}

if (Test-ImpulseHealth -Url $config.PublicUrl -Tunnel -TimeoutSec 10) {
  Write-Host "Туннель уже работает: $($config.PublicUrl)" -ForegroundColor Green
  Write-Host 'Второй экземпляр не нужен.'
  exit 0
}

New-Item -ItemType Directory -Force -Path $config.LogDir | Out-Null
$watchdog = Join-Path $config.Root 'tunnel-watchdog.ps1'
Start-Process -FilePath 'powershell.exe' `
  -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$watchdog`"" `
  -WorkingDirectory $config.Root -WindowStyle Hidden

Write-Host "Запускаю localtunnel для $($config.LocalUrl)..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
  if (Test-ImpulseHealth -Url $config.PublicUrl -Tunnel -TimeoutSec 8) {
    Write-Host ''
    Write-Host "Туннель работает: $($config.PublicUrl)" -ForegroundColor Green
    Write-Host 'Watchdog автоматически перезапустит его при обрыве.'
    Write-Host 'На Android укажите этот адрес на экране входа.'
    exit 0
  }
  Start-Sleep -Seconds 2
}

Write-Host ''
Write-Host "Туннель ещё запускается: $($config.PublicUrl)/health" -ForegroundColor Yellow
Write-Host "Лог: $($config.WatchdogLog)"
Write-Host "Остановить: stop-tunnel.cmd"
exit 2

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'network-config.ps1')
$config = Get-ImpulseConfig

if (-not (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 2)) {
  Write-Host 'Запуск локального сервера «Импульс»...' -ForegroundColor Cyan
  $serverScript = Join-Path $config.Root 'start-server.ps1'
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serverScript`"" `
    -WorkingDirectory $config.Root `
    -WindowStyle Minimized

  $deadline = (Get-Date).AddSeconds(40)
  while ((Get-Date) -lt $deadline -and -not (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 2)) {
    Start-Sleep -Milliseconds 500
  }

  if (-not (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 2)) {
    Write-Host 'Сервер не запустился. Запустите start-server.cmd и посмотрите ошибку в окне.' -ForegroundColor Red
    Read-Host 'Нажмите Enter, чтобы закрыть'
    exit 1
  }
  Write-Host 'Сервер запущен.' -ForegroundColor Green
} else {
  Write-Host "Сервер уже запущен: $($config.LocalUrl)" -ForegroundColor Green
}

$releaseDir = Join-Path $config.Root 'desktop\release'
$app = $null

$unpacked = Join-Path $releaseDir 'win-unpacked\Импульс.exe'
if (Test-Path $unpacked) {
  $app = $unpacked
}

if (-not $app -and (Test-Path $releaseDir)) {
  $portable = Get-ChildItem $releaseDir -Filter '*portable.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($portable) { $app = $portable.FullName }
}

if (-not $app -and (Test-Path $releaseDir)) {
  $any = Get-ChildItem $releaseDir -Filter '*.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch 'Setup|uninstall' } |
    Select-Object -First 1
  if ($any) { $app = $any.FullName }
}

if (-not $app) {
  Write-Host 'Клиент не найден. Соберите его командой npm run dist.' -ForegroundColor Red
  Read-Host 'Нажмите Enter, чтобы закрыть'
  exit 1
}

Write-Host "Открываю клиент: $app" -ForegroundColor Cyan
Start-Process -FilePath $app

if (Test-ImpulseHealth -Url $config.PublicUrl -Tunnel -TimeoutSec 4) {
  Write-Host "Публичный туннель доступен: $($config.PublicUrl)" -ForegroundColor Green
} else {
  Write-Host "Публичный туннель не запущен. Для телефона на мобильном интернете: start-tunnel.cmd" -ForegroundColor Yellow
  Write-Host "Прямая P2P-связь доступна в клиенте кнопкой «P2P» без туннеля."
}

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'network-config.ps1')
$config = Get-ImpulseConfig

if (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 2) {
  Write-Host "Сервер уже запущен: $($config.LocalUrl)" -ForegroundColor Green
  Write-Host 'Второй экземпляр не нужен.'
  exit 0
}

$serverDir = Join-Path $config.Root 'server'
$entry = Join-Path $serverDir 'dist\index.js'
if (-not (Test-Path -LiteralPath $entry)) {
  Write-Host 'Сборка сервера не найдена: server\dist\index.js' -ForegroundColor Red
  Write-Host 'Соберите сервер: npm run build:server'
  exit 1
}

$electron = Join-Path $config.Root 'desktop\node_modules\electron\dist\electron.exe'
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $electron) {
  $runtime = $electron
  $env:ELECTRON_RUN_AS_NODE = '1'
} elseif ($node) {
  $runtime = $node.Source
  Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
} else {
  Write-Host 'Не найден Node.js или Electron. Установите зависимости проекта.' -ForegroundColor Red
  exit 1
}

# localtunnel connects to loopback, so 0.0.0.0 is not required. Set HOST
# explicitly only when LAN access is also needed.
if (-not $env:HOST) { $env:HOST = '127.0.0.1' }
$env:PORT = [string]$config.Port

Write-Host "Запуск «Импульса» на $($config.LocalUrl) (HOST=$($env:HOST))..." -ForegroundColor Cyan
Set-Location -LiteralPath $serverDir
& $runtime $entry
exit $LASTEXITCODE

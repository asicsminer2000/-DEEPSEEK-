# Single source of truth for the local server and localtunnel scripts.
# Override without editing files:
#   $env:IMPULSE_PORT=3000; $env:IMPULSE_SUBDOMAIN='my-name'

$script:ImpulseRoot = $PSScriptRoot
$script:ImpulsePort = if ($env:IMPULSE_PORT) {
  $parsedPort = 0
  if (-not [int]::TryParse($env:IMPULSE_PORT, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
    throw "IMPULSE_PORT must be a TCP port between 1 and 65535"
  }
  $parsedPort
} else {
  3000
}
$script:ImpulseSubdomain = if ($env:IMPULSE_SUBDOMAIN) {
  $env:IMPULSE_SUBDOMAIN.Trim()
} else {
  'moy-server-2026'
}
$script:ImpulseLocalUrl = "http://127.0.0.1:$script:ImpulsePort"
$script:ImpulsePublicUrl = "https://$script:ImpulseSubdomain.loca.lt"
$script:ImpulseLogDir = Join-Path $env:LOCALAPPDATA 'Temp\opencode'
$script:ImpulseStopFile = Join-Path $script:ImpulseLogDir 'impulse-tunnel.stop'
$script:ImpulseStoppedFile = Join-Path $script:ImpulseLogDir 'impulse-tunnel.stopped'
$script:ImpulsePidFile = Join-Path $script:ImpulseLogDir 'impulse-tunnel.pid'
$script:ImpulseWatchdogLog = Join-Path $script:ImpulseLogDir 'impulse-tunnel-watchdog.log'
$script:ImpulseTunnelOut = Join-Path $script:ImpulseLogDir 'lt-watchdog.out.log'
$script:ImpulseTunnelErr = Join-Path $script:ImpulseLogDir 'lt-watchdog.err.log'

function Get-ImpulseConfig {
  [pscustomobject]@{
    Root = $script:ImpulseRoot
    Port = $script:ImpulsePort
    Subdomain = $script:ImpulseSubdomain
    LocalUrl = $script:ImpulseLocalUrl
    PublicUrl = $script:ImpulsePublicUrl
    LogDir = $script:ImpulseLogDir
    StopFile = $script:ImpulseStopFile
    StoppedFile = $script:ImpulseStoppedFile
    PidFile = $script:ImpulsePidFile
    WatchdogLog = $script:ImpulseWatchdogLog
    TunnelOut = $script:ImpulseTunnelOut
    TunnelErr = $script:ImpulseTunnelErr
  }
}

function Test-ImpulseHealth {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [switch]$Tunnel,
    [int]$TimeoutSec = 10
  )
  try {
    $headers = @{}
    if ($Tunnel) { $headers['bypass-tunnel-reminder'] = 'true' }
    $response = Invoke-RestMethod -Uri "$($Url.TrimEnd('/'))/health" -Headers $headers `
      -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
    return ($response.ok -eq $true -and $response.service -eq 'impulse')
  } catch {
    return $false
  }
}

function Get-ImpulseTunnelProcesses {
  $portPattern = '--port\s+' + [regex]::Escape([string]$script:ImpulsePort) + '(\s|$)'
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    ($_.Name -eq 'node.exe' -or $_.Name -eq 'electron.exe') -and
    $_.CommandLine -match 'lt\.js' -and
    $_.CommandLine -match $portPattern -and
    $_.CommandLine -match [regex]::Escape($script:ImpulseSubdomain)
  })
}

function Get-ImpulseLocaltunnelPath {
  $local = Join-Path $script:ImpulseRoot 'node_modules\localtunnel\bin\lt.js'
  if (Test-Path -LiteralPath $local) { return $local }
  $global = Join-Path $env:APPDATA 'npm\node_modules\localtunnel\bin\lt.js'
  if (Test-Path -LiteralPath $global) { return $global }
  return $null
}

function Get-ImpulseNodePath {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($node) { return $node.Source }
  $bundled = Join-Path $script:ImpulseRoot 'desktop\node_modules\electron\dist\electron.exe'
  if (Test-Path -LiteralPath $bundled) { return $bundled }
  return $null
}

function Write-ImpulseLog {
  param([string]$Message)
  try {
    New-Item -ItemType Directory -Force -Path $script:ImpulseLogDir | Out-Null
    Add-Content -LiteralPath $script:ImpulseWatchdogLog `
      -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
  } catch {
  }
}

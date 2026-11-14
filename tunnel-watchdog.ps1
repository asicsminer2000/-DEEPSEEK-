# Keeps the localtunnel for Impulse alive on a stable subdomain.
# Started hidden by start-tunnel.ps1; stopped by stop-tunnel.ps1.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'network-config.ps1')
$config = Get-ImpulseConfig

New-Item -ItemType Directory -Force -Path $config.LogDir | Out-Null
Remove-Item -LiteralPath $config.StopFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $config.StoppedFile -Force -ErrorAction SilentlyContinue

$mutex = New-Object System.Threading.Mutex($false, 'Local\ImpulseTunnelWatchdog')
if (-not $mutex.WaitOne(0)) { exit 0 }

Set-Content -LiteralPath $config.PidFile -Value ([string]$PID) -Encoding ASCII
Write-ImpulseLog 'watchdog started'

function Stop-Lt {
  foreach ($item in Get-ImpulseTunnelProcesses) {
    try { Stop-Process -Id $item.ProcessId -Force -ErrorAction Stop } catch {}
  }
  Start-Sleep -Seconds 2
}

function Start-Lt {
  $node = Get-ImpulseNodePath
  $lt = Get-ImpulseLocaltunnelPath
  if (-not $node -or -not $lt) {
    Write-ImpulseLog 'node or localtunnel is missing'
    return $false
  }

  foreach ($log in @($config.TunnelOut, $config.TunnelErr)) {
    if (Test-Path -LiteralPath $log) {
      Copy-Item -LiteralPath $log -Destination "$log.previous" -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
  }

  $env:ELECTRON_RUN_AS_NODE = '1'
  # Start-Process does not quote array arguments. The project path contains a
  # space ("Мессенджер Импульс"), so quote the script path explicitly.
  $quotedLt = '"' + $lt + '"'
  $process = Start-Process -FilePath $node `
    -ArgumentList @($quotedLt, '--port', [string]$config.Port, '--subdomain', $config.Subdomain) `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput $config.TunnelOut -RedirectStandardError $config.TunnelErr

  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    $text = ''
    if (Test-Path -LiteralPath $config.TunnelOut) {
      $text += Get-Content -LiteralPath $config.TunnelOut -Raw -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $config.TunnelErr) {
      $text += Get-Content -LiteralPath $config.TunnelErr -Raw -ErrorAction SilentlyContinue
    }
    if ($text -match [regex]::Escape($config.PublicUrl)) {
      Write-ImpulseLog "tunnel started (pid $($process.Id))"
      return $true
    }
    if ($process.HasExited) {
      Write-ImpulseLog "localtunnel exited during startup (code $($process.ExitCode))"
      return $false
    }
  }

  Write-ImpulseLog 'localtunnel did not report the requested subdomain'
  Stop-Lt
  return $false
}

function Wait-ForStop([int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $config.StopFile) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return (Test-Path -LiteralPath $config.StopFile)
}

$serverWasDown = $false
$failures = 0
$lastRestart = Get-Date
$lastStartAttempt = [datetime]::MinValue

while ($true) {
  if (Test-Path -LiteralPath $config.StopFile) {
    Write-ImpulseLog 'stop requested'
    Stop-Lt
    Set-Content -LiteralPath $config.StoppedFile -Value ([string]$PID) -Encoding ASCII
    Remove-Item -LiteralPath $config.StopFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $config.PidFile -Force -ErrorAction SilentlyContinue
    Write-ImpulseLog 'watchdog stopped'
    break
  }

  if (-not (Test-ImpulseHealth -Url $config.LocalUrl -TimeoutSec 5)) {
    if (-not $serverWasDown) {
      Write-ImpulseLog 'local server is down, waiting'
      $serverWasDown = $true
    }
    $failures = 0
    if (Wait-ForStop 15) { continue }
    continue
  }
  if ($serverWasDown) {
    Write-ImpulseLog 'local server is up again'
    $serverWasDown = $false
  }

  if (@(Get-ImpulseTunnelProcesses).Count -eq 0) {
    if (((Get-Date) - $lastStartAttempt).TotalSeconds -ge 15) {
      Write-ImpulseLog 'tunnel process is missing, starting'
      $lastStartAttempt = Get-Date
      $null = Start-Lt
      if (Wait-ForStop 5) { continue }
    }
  }

  if (Test-ImpulseHealth -Url $config.PublicUrl -Tunnel -TimeoutSec 15) {
    if ($failures -gt 0) { Write-ImpulseLog 'tunnel is healthy again' }
    $failures = 0
    if (Wait-ForStop 30) { continue }
    continue
  }

  $failures++
  Write-ImpulseLog "public health check failed ($failures/3)"
  if ($failures -ge 3) {
    if (((Get-Date) - $lastRestart).TotalSeconds -lt 30) {
      if (Wait-ForStop 10) { continue }
      continue
    }
    Write-ImpulseLog 'restarting tunnel'
    Stop-Lt
    $lastRestart = Get-Date
    $lastStartAttempt = Get-Date
    $null = Start-Lt
    $failures = 0
    if (Wait-ForStop 5) { continue }
  } elseif (Wait-ForStop 15) {
    continue
  }
}

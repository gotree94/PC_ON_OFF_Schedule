# Boot-HibernateCheck.ps1
# Called by the PCPower-BootCheck scheduled task at system startup (SYSTEM).
# Hibernates the PC only when BOTH conditions hold:
#   1. The hibernate flag exists (set by Sleep-Scheduled.ps1 before reboot)
#   2. Current time falls inside an OFF window (from config.json)
# A stale flag from an aborted reboot is discarded instead of hibernating.
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$log = Join-Path $root 'schedule.log'
$flag = Join-Path $root 'pending-hibernate.flag'
$configPath = Join-Path $root 'config.json'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $log -Value $line -Encoding UTF8
}

# Returns $true when $NowMinutes falls inside any OFF interval
# (each sleep time up to the next wake time, wrapping midnight).
function Test-OffWindow {
    param(
        [int]$NowMinutes,
        [int[]]$SleepMinutes,
        [int[]]$WakeMinutes
    )
    foreach ($s in $SleepMinutes) {
        $after = @($WakeMinutes | Where-Object { $_ -gt $s } | Sort-Object)
        if ($after.Count -gt 0) {
            $w = [int]$after[0]
        }
        else {
            $w = [int](($WakeMinutes | Sort-Object | Select-Object -First 1)) + 1440
        }
        $n = $NowMinutes
        if ($n -lt $s) { $n = $n + 1440 }
        if ($n -ge $s -and $n -lt $w) { return $true }
    }
    return $false
}

try {
    if (-not (Test-Path -Path $flag)) {
        Write-Log 'Boot check: no pending hibernate flag. Nothing to do.'
        exit 0
    }

    if (-not (Test-Path -Path $configPath)) { throw "config.json not found: $configPath" }
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $sleepMin = @($config.sleepTimes | ForEach-Object { [int]([TimeSpan]::Parse($_).TotalMinutes) })
    $wakeMin = @($config.wakeTimes | ForEach-Object { [int]([TimeSpan]::Parse($_).TotalMinutes) })

    $now = Get-Date
    $nowMin = [int]$now.TimeOfDay.TotalMinutes
    $inOff = Test-OffWindow -NowMinutes $nowMin -SleepMinutes $sleepMin -WakeMinutes $wakeMin

    # The flag is consumed either way so it can never go stale.
    Remove-Item -Path $flag -Force

    if (-not $inOff) {
        Write-Log ("Boot check: flag found but {0} is an ON window - stale flag discarded, staying awake." -f $now.ToString('HH:mm'))
        exit 0
    }

    if ($DryRun) {
        Write-Log 'Flag + OFF-window conditions met. Would hibernate now.' 'DRYRUN'
        exit 0
    }

    Write-Log 'Boot check: conditions met. Hibernating now.'
    & shutdown.exe /h
    # Only reached if hibernation failed.
    Write-Log "shutdown /h failed with exit code $LASTEXITCODE" 'ERROR'
    exit $LASTEXITCODE
}
catch {
    Write-Log "Boot check FAILED: $($_.Exception.Message)" 'ERROR'
    exit 1
}

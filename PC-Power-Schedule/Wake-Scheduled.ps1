# Wake-Scheduled.ps1
# Called by the PCPower-Wake scheduled task.
# The task itself is configured with "Wake the computer to run this task",
# so the PC wakes from hibernate before this script runs.
# The script only logs the event so wakeups are verifiable in schedule.log.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$log = Join-Path $root 'schedule.log'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $log -Value $line -Encoding UTF8
}

try {
    Write-Log "Wake task fired. PC is awake at $(Get-Date -Format 'HH:mm:ss')."
    exit 0
}
catch {
    Write-Log "Wake task FAILED: $($_.Exception.Message)" 'ERROR'
    exit 1
}

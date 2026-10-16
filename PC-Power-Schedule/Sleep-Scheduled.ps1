# Sleep-Scheduled.ps1
# Called by the PCPower-Sleep scheduled task.
# Creates the hibernate flag, then reboots the PC.
# After reboot, Boot-HibernateCheck.ps1 sees the flag and hibernates.
param(
    [switch]$WhatIf
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

try {
    if (-not (Test-Path -Path $configPath)) { throw "config.json not found: $configPath" }
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $delay = [int]$config.rebootDelaySeconds
    if ($delay -lt 5) { $delay = 5 }

    if ($WhatIf) {
        Write-Log "Would create hibernate flag and run: shutdown /r /t $delay /f" 'WHATIF'
        exit 0
    }

    # Flag must exist BEFORE the reboot so the startup task can pick it up.
    Set-Content -Path $flag -Value (Get-Date -Format 'o') -Encoding UTF8
    Write-Log "Scheduled sleep: hibernate flag created. Rebooting in $delay seconds."

    & shutdown.exe /r /t $delay /f /d p:4:1 /c 'PCPower: scheduled reboot before hibernate'
    if ($LASTEXITCODE -ne 0) { throw "shutdown /r failed with exit code $LASTEXITCODE" }

    Write-Log 'shutdown /r issued. System will hibernate after reboot.'
    exit 0
}
catch {
    Write-Log "Sleep task FAILED: $($_.Exception.Message)" 'ERROR'
    exit 1
}

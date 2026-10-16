#Requires -RunAsAdministrator
# Register-Schedule.ps1
# (Re)creates the three PCPower-* scheduled tasks from config.json and
# enables hibernate + wake timers in the active power scheme.
# Run this again as Administrator whenever you edit config.json.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$log = Join-Path $root 'schedule.log'
$configPath = Join-Path $root 'config.json'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $log -Value $line -Encoding UTF8
}

try {
    # ---- Validate config ----
    if (-not (Test-Path -Path $configPath)) { throw "config.json not found: $configPath" }
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    $wakeTimes = @($config.wakeTimes)
    $sleepTimes = @($config.sleepTimes)
    if ($wakeTimes.Count -lt 1) { throw 'config.json: wakeTimes must contain at least one time' }
    if ($sleepTimes.Count -lt 1) { throw 'config.json: sleepTimes must contain at least one time' }
    foreach ($t in ($wakeTimes + $sleepTimes)) { $null = [TimeSpan]::Parse($t) }  # throws on bad format

    # ---- Power settings: hibernate + wake timers ----
    & powercfg.exe /h on
    if ($LASTEXITCODE -ne 0) { throw "powercfg /h on failed (exit $LASTEXITCODE)" }
    & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1
    if ($LASTEXITCODE -ne 0) { throw "powercfg AC wake timer enable failed (exit $LASTEXITCODE)" }
    & powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1
    if ($LASTEXITCODE -ne 0) { throw "powercfg DC wake timer enable failed (exit $LASTEXITCODE)" }
    & powercfg.exe /setactive SCHEME_CURRENT
    Write-Log 'Power settings: hibernate enabled, wake timers enabled (AC + DC).'

    # ---- Shared task components ----
    $psArgsFmt = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    # ---- Task 1: PCPower-Wake (daily at each wake time, wakes hibernating PC) ----
    $wakeTriggers = @($wakeTimes | ForEach-Object {
        New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.Add([TimeSpan]::Parse($_)))
    })
    Register-ScheduledTask -TaskName 'PCPower-Wake' -Force `
        -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ($psArgsFmt -f (Join-Path $root 'Wake-Scheduled.ps1'))) `
        -Trigger $wakeTriggers `
        -Settings (New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)) `
        -Principal $principal `
        -Description "Power schedule: wake PC at $($wakeTimes -join ', ')" | Out-Null

    # ---- Task 2: PCPower-Sleep (daily at each sleep time, reboot then hibernate) ----
    $sleepTriggers = @($sleepTimes | ForEach-Object {
        New-ScheduledTaskTrigger -Daily -At ([DateTime]::Today.Add([TimeSpan]::Parse($_)))
    })
    Register-ScheduledTask -TaskName 'PCPower-Sleep' -Force `
        -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ($psArgsFmt -f (Join-Path $root 'Sleep-Scheduled.ps1'))) `
        -Trigger $sleepTriggers `
        -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)) `
        -Principal $principal `
        -Description "Power schedule: reboot + hibernate at $($sleepTimes -join ', ')" | Out-Null

    # ---- Task 3: PCPower-BootCheck (at startup, hibernate if flag + OFF window) ----
    Register-ScheduledTask -TaskName 'PCPower-BootCheck' -Force `
        -Action (New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ($psArgsFmt -f (Join-Path $root 'Boot-HibernateCheck.ps1'))) `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)) `
        -Principal $principal `
        -Description 'Power schedule: hibernate after scheduled reboot when inside OFF window' | Out-Null

    Write-Log "Registered tasks: PCPower-Wake [$($wakeTimes -join ', ')], PCPower-Sleep [$($sleepTimes -join ', ')], PCPower-BootCheck [startup]."

    # ---- Report ----
    Write-Host ''
    Write-Host '=== Registered tasks ==='
    $rows = Get-ScheduledTask -TaskName 'PCPower-*' | ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo
        [pscustomobject]@{
            TaskName   = $_.TaskName
            State      = $_.State.ToString()
            NextRun    = if ($info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'n/a (runs at next boot)' }
            LastResult = '0x{0:x}' -f $info.LastTaskResult
        }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
    Write-Host 'Wake timer query (SUB_SLEEP RTCWAKE - look for Power Setting Index 0x1):'
    & powercfg.exe /q SCHEME_CURRENT SUB_SLEEP RTCWAKE
    Write-Log 'Registration complete.'
    exit 0
}
catch {
    Write-Log "Registration FAILED: $($_.Exception.Message)" 'ERROR'
    Write-Error $_
    exit 1
}

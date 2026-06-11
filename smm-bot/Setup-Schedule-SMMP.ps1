# Setup-Schedule-SMMP.ps1 — ежедневная публикация через SMMplanner API.
# По умолчанию: 18:00 (вечер — между дневным VK-постом и ночью).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1  = Join-Path $root 'Post-Next-SMMP.ps1'
$pwsh = (Get-Command pwsh).Source
$time = '18:00'

if (-not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }

$taskName = 'NL-SMMP-AutoPost'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action = New-ScheduledTaskAction `
    -Execute $pwsh `
    -Argument "-NoProfile -File `"$ps1`"" `
    -WorkingDirectory $root

$trigger = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: ежедневно в $time через SMMplanner API публикует в MAX, ОК и др."

Write-Host "✅ Задача '$taskName' создана. Расписание: ежедневно в $time."
Write-Host "Проверить: schtasks /Query /TN $taskName /V /FO LIST"

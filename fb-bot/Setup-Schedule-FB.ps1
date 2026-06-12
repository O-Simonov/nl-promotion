# Создание задания в Планировщике Windows — Facebook пост каждый день в 11:00
$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1      = Join-Path $root 'Post-Next-FB.ps1'
$pwsh     = (Get-Command pwsh).Source
$time     = '11:00'
$taskName = 'NL-FB-AutoPost'

if (-not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -File `"$ps1`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: ежедневно в $time публикует следующий пост в Facebook страницу."

Write-Host "Задача '$taskName' создана. Расписание: ежедневно в $time." -ForegroundColor Green

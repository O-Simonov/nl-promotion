# Setup-Token-Reminder.ps1 — планирует Telegram-напоминание об обновлении токенов Meta
# Запускать каждый раз после обновления токенов (переносит задачу на +60 дней)
$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1      = Join-Path $root 'Send-Token-Reminder.ps1'
$pwsh     = (Get-Command pwsh).Source
$taskName = 'NL-Token-Reminder'

# Напоминание за 2 дня до истечения 60 дней (58-й день от сегодня)
$remindDate = (Get-Date).AddDays(58).Date.AddHours(9)

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -File `"$ps1`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Once -At $remindDate
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: напоминание об обновлении токенов Meta за 2 дня до истечения."

Write-Host "Задача '$taskName' создана." -ForegroundColor Green
Write-Host "Напоминание придёт: $($remindDate.ToString('dd.MM.yyyy HH:mm'))" -ForegroundColor Cyan
Write-Host "Запусти этот скрипт снова после обновления токенов." -ForegroundColor Yellow

# Setup-Schedule-VK.ps1 — создаёт в Windows ежедневное расписание для Post-Next-VK.ps1.
# По умолчанию: каждый день в 14:00 (через 4 часа после TG-бота).
# Запускать ОДИН РАЗ от имени администратора.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1  = Join-Path $root 'Post-Next-VK.ps1'
$pwsh = (Get-Command pwsh).Source
$time = '14:00'  # время публикации

if (-not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "pwsh (PowerShell 7) не найден в PATH."; exit 1
}

$taskName = 'NL-VK-AutoPost'
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
    -Description "NL promotion: ежедневно в $time публикует следующий пост из tg-bot/queue в сообщество ВК."

Write-Host "✅ Задача '$taskName' создана. Расписание: ежедневно в $time."
Write-Host "Проверить: schtasks /Query /TN $taskName /V /FO LIST"
Write-Host "Тестовый запуск: pwsh -File `"$ps1`""

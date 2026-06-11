# Setup-Schedule.ps1 — создаёт ежедневную задачу автопостинга в Windows.
# Использование:  pwsh -File Setup-Schedule.ps1            (по умолчанию в 10:00)
#                 pwsh -File Setup-Schedule.ps1 -Time 18:30 (своё время)

param([string]$Time = "10:00")

$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $root 'Post-Next.ps1'

# находим pwsh (нужен PowerShell 7+ для отправки фото)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    Write-Host "❌ Не найден PowerShell 7 (pwsh). Установи его: https://aka.ms/powershell"
    exit 1
}

$action  = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName "NL-Telegram-AutoPost" `
    -Action $action -Trigger $trigger -Settings $settings `
    -Description "Ежедневный автопостинг NL в Telegram" -Force | Out-Null

Write-Host "✅ Готово! Задача 'NL-Telegram-AutoPost' создана."
Write-Host "   Бот будет публиковать по одному посту каждый день в $Time."
Write-Host "   (Компьютер должен быть включён в это время. Если был выключен — пост уйдёт при ближайшем включении.)"
Write-Host ""
Write-Host "Удалить расписание потом:  Unregister-ScheduledTask -TaskName 'NL-Telegram-AutoPost' -Confirm:`$false"

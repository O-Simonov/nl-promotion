# Setup-Schedule-News.ps1 — ежедневная задача сбора свежих постов NL в дайджест.
# По умолчанию каждый день в 08:30 (до утренних публикаций).
# Запускать один раз.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1  = Join-Path $root 'Fetch-NL-News.ps1'
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$time = '08:30'
$taskName = 'NL-News-Watch'

if (-not $ps1 -or -not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }
if (-not $pwsh) { Write-Host "pwsh (PowerShell 7) не найден в PATH."; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -File `"$ps1`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
# -RestartCount/-RestartInterval: при сбое (выход с кодом 1 после внутренних повторов)
# планировщик перезапустит задачу до 3 раз с паузой 5 минут.
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: ежедневно в $time собирает свежие посты канала NL в news-watch/digest.md."

Write-Host "✅ Задача '$taskName' создана. Расписание: ежедневно в $time." -ForegroundColor Green
Write-Host "Тестовый запуск: pwsh -File `"$ps1`""

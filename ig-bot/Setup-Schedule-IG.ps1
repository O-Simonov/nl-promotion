# Создание задания в Планировщике Windows — Instagram пост каждый день в 12:00
$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1      = Join-Path $root 'Post-Next-IG.ps1'
$pwsh     = (Get-Command pwsh).Source
$time     = '12:00'
$taskName = 'NL-IG-AutoPost'

if (-not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Write-Host "pwsh (PowerShell 7) не найден в PATH."; exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -File `"$ps1`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
# -RestartCount/-RestartInterval: при сбое запуска (скрипт вышел с кодом 1 после внутренних повторов)
# планировщик перезапустит задачу до 3 раз с паузой 5 минут.
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: ежедневно в $time публикует следующий пост с картинкой в Instagram."

Write-Host "Задача '$taskName' создана. Расписание: ежедневно в $time." -ForegroundColor Green
Write-Host "Проверить: schtasks /Query /TN $taskName /V /FO LIST"
Write-Host "Тестовый запуск: pwsh -File `"$ps1`""

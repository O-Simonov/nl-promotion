# Создание задания в Планировщике Windows — X (Twitter) пост каждый день в 13:07
# Время смещено с «круглого» (по методичке) и сидит между IG (12:00) и VK (14:00).
$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1      = Join-Path $root 'Post-Next-X.ps1'
$pwsh     = (Get-Command pwsh).Source
$time     = '13:07'
$taskName = 'NL-X-AutoPost'

if (-not (Test-Path $ps1)) { Write-Host "Не найден $ps1"; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Старая задача '$taskName' удалена."
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -File `"$ps1`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "NL promotion: ежедневно в $time публикует следующий пост в X (Twitter) через Playwright."

Write-Host "Задача '$taskName' создана. Расписание: ежедневно в $time." -ForegroundColor Green
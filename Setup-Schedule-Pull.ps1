# Setup-Schedule-Pull.ps1 — ежедневный git pull с GitHub (до refill и постинга).
# По умолчанию 08:50 — раньше NL-Queue-Refill (09:00) и Telegram (10:00).
#
#   pwsh -File Setup-Schedule-Pull.ps1
#   pwsh -File Setup-Schedule-Pull.ps1 -Time 08:30

param([string]$Time = '08:50')

$root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $root 'Pull-From-GitHub.ps1'

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    Write-Host "❌ Не найден PowerShell 7 (pwsh)."
    exit 1
}

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory $root
$trigger   = New-ScheduledTaskTrigger -Daily -At $Time
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -WakeToRun -RunOnlyIfNetworkAvailable -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName 'NL-GitHub-Pull' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Ежедневный git pull origin/main перед refill и автопостингом NL' -Force | Out-Null

Write-Host "✅ Задача 'NL-GitHub-Pull' создана — каждый день в $Time."
Write-Host "   Подтягивает правки с GitHub (в т.ч. с телефона) в C:\NL_produkt."
Write-Host "   Лог: C:\NL_produkt\logs\git-pull.log"
Write-Host ""
Write-Host "Удалить: Unregister-ScheduledTask -TaskName 'NL-GitHub-Pull' -Confirm:`$false"

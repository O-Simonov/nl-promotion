# Test-Bot.ps1 — проверяет токен и отправляет тестовое сообщение в канал.
# Запусти этот скрипт ПЕРВЫМ после вставки токена, чтобы убедиться, что всё работает.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Get-Content (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$token = $cfg.botToken
$channel = $cfg.channelId

if ([string]::IsNullOrWhiteSpace($token) -or $token -match 'ВСТАВЬ') {
    Write-Host "❌ Сначала вставь токен бота в config.json"; exit 1
}

# 1) проверяем токен
$me = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getMe"
if (-not $me.ok) { Write-Host "❌ Токен неверный."; exit 1 }
Write-Host "✅ Бот подключён: @$($me.result.username)"

# 2) пробуем отправить сообщение в канал
try {
    $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body @{
        chat_id = $channel
        text    = "✅ Проверка связи: бот может публиковать в этот канал. Тестовое сообщение можно удалить."
    }
    if ($resp.ok) {
        Write-Host "✅ Тестовое сообщение отправлено в канал $channel"
        Write-Host "Всё готово! Можно настраивать расписание (Setup-Schedule.ps1)."
    }
}
catch {
    Write-Host "❌ Не удалось отправить в канал $channel"
    Write-Host "Причина: $($_.Exception.Message)"
    Write-Host "Проверь: 1) канал существует;  2) бот добавлен в него АДМИНИСТРАТОРОМ;  3) channelId в config.json указан верно (например @Simka1969)."
}

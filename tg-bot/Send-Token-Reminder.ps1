# Send-Token-Reminder.ps1 — отправляет напоминание об обновлении токенов Meta
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Get-Content (Join-Path $root 'config.json') | ConvertFrom-Json

$text = "🔑 <b>ПОРА ОБНОВИТЬ ТОКЕНЫ META!</b>

Токены Facebook и Instagram живут ~60 дней и скоро истекут.

<b>Как обновить:</b>
1. Открыть developers.facebook.com → Graph API Explorer
2. Выбрать приложение и страницу
3. Добавить разрешения: pages_manage_posts, instagram_content_publish
4. Нажать «Создать токен страницы»
5. Скопировать токен в ig-bot/config.json и fb-bot/config.json (поле pageToken)
6. Проверить: pwsh -File ig-bot\Test-Bot-IG.ps1

После обновления токенов запустить Setup-Token-Reminder.ps1 заново чтобы перенести напоминание ещё на 60 дней."

$uri  = "https://api.telegram.org/bot$($cfg.botToken)/sendMessage"
$body = @{ chat_id = $cfg.channelId; text = $text; parse_mode = 'HTML' }

try {
    Invoke-RestMethod -Uri $uri -Method Post -Body $body | Out-Null
    Write-Host "Напоминание отправлено в Telegram." -ForegroundColor Green
} catch {
    Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
}

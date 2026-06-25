# Notify-Owner.ps1 — отправляет уведомление о проблемах в TG-канал @Simka1969_nl
# (запасной вариант: если указан -DirectChatId, шлёт лично Олегу)
#
# Использование:
#   pwsh -File Notify-Owner.ps1 -Message "Текст"
#   pwsh -File Notify-Owner.ps1 -Message "Текст" -DirectChatId 123456789
#
# Уведомления приходят в виде сообщения с префиксом 🚨 ALERT — их видно сразу.

param(
    [Parameter(Mandatory=$true)][string]$Message,
    [string]$BotToken = "",            # если пусто — возьмём из tg-bot/config.json
    [int]$DirectChatId = 0,            # 0 = шлём в канал, иначе — лично Олегу
    [string]$ChannelId = "@Simka1969_nl"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Если токен не передан — берём из tg-bot/config.json
if (-not $BotToken) {
    $cfgPath = Join-Path $PSScriptRoot "tg-bot\config.json"
    if (Test-Path $cfgPath) {
        $cfg = Get-Content $cfgPath | ConvertFrom-Json
        $BotToken = $cfg.botToken
    } else {
        Write-Host "❌ Не найден tg-bot/config.json и не передан -BotToken"
        exit 1
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
$fullText = "🚨 <b>ALERT [$timestamp]</b>%0A%0A$Message"

if ($DirectChatId -gt 0) {
    $chatId = $DirectChatId
    $mode = "direct"
} else {
    $chatId = $ChannelId
    $mode = "channel"
}

$url = "https://api.telegram.org/bot$BotToken/sendMessage"
$body = @{
    chat_id    = $chatId
    text       = $fullText
    parse_mode = "HTML"
} | ConvertTo-Json -Compress

try {
    $resp = Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $body -TimeoutSec 15
    if ($resp.ok) {
        Write-Host "✅ ALERT отправлен ($mode, message_id=$($resp.result.message_id))"
        exit 0
    } else {
        Write-Host "❌ Telegram API: $($resp | ConvertTo-Json -Compress)"
        exit 1
    }
} catch {
    Write-Host "❌ Ошибка отправки: $($_.Exception.Message)"
    exit 1
}

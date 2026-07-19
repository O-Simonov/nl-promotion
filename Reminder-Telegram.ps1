# Reminder-Telegram.ps1 — собирает сводку по автопостингу NL и шлёт её
# в личный Telegram-чат владельца. Запускается по расписанию (Task Scheduler)
# как напоминание/health-check. Не зависит от открытой сессии Claude Code.
#
# Читает notify.config.json (gitignored): { "botToken", "chatId" }.

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$root = $PSScriptRoot
$cfg  = Get-Content (Join-Path $root 'notify.config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$token = $cfg.botToken
$chat  = $cfg.chatId

$today = Get-Date -Format 'yyyy-MM-dd'
$root2 = Join-Path $root 'tg-bot'

# --- сводка по ботам: логи за сегодня ---
$bots = @(
  @{ name='TG'; log='tg-bot\logs\post.log';   okPat='OK: опубликован|УСПЕХ!|OK' ; badPat='СБОЙ|не удалось|❌' }
  @{ name='FB'; log='fb-bot\logs\fb-bot.log'; okPat='УСПЕХ!|OK: опубликован'      ; badPat='СБОЙ|❌|ошибка' }
  @{ name='IG'; log='ig-bot\logs\ig-bot.log'; okPat='УСПЕХ!|Пост опубликован'     ; badPat='СБОЙ|❌|ошибка' }
  @{ name='VK'; log='vk-bot\logs\post.log';   okPat='OK: опубликован|Успех'        ; badPat='СБОЙ|❌|ошибка' }
  @{ name='X';  log='x-bot\logs\x-bot.log';   okPat='УСПЕХ!|Твит опубликован'      ; badPat='СБОЙ|❌|нужен ручной вход' }
)

$lines = @()
foreach ($b in $bots) {
  $logPath = Join-Path $root $b.log
  if (-not (Test-Path $logPath)) { $lines += "• $($b.name): нет лога"; continue }
  $todays = Get-Content $logPath | Where-Object { $_ -match "^$today|^\[$today" }
  if (-not $todays) { $lines += "• $($b.name): сегодня не запускался ⏳"; continue }
  $ok  = ($todays | Where-Object { $_ -match $b.okPat  }).Count
  $bad = ($todays | Where-Object { $_ -match $b.badPat }).Count
  if ($bad -gt 0)      { $lines += "• $($b.name): ❌ ошибка/сбой (попыток OK: $ok)" }
  elseif ($ok -gt 0)   { $lines += "• $($b.name): ✅ опубликовал" }
  else                 { $lines += "• $($b.name): ⚠️ запускался, статус неясен" }
}

# --- очередь / бэклог ---
$q = (Get-ChildItem (Join-Path $root2 'queue')   -Filter *.txt -File -ErrorAction SilentlyContinue | Measure-Object).Count
$b = (Get-ChildItem (Join-Path $root2 'backlog') -Filter *.txt -File -ErrorAction SilentlyContinue | Measure-Object).Count
$lines += ""
$lines += "📦 Очередь: $q | Бэклог: $b (запас ~$([math]::Round(($q+$b)/4)) дн.)"

$msg = "📊 <b>Ежедневная сводка: автопостинг NL</b>%0A$today%0A%0A" + ($lines -join "%0A")
$msg += "%0A%0AЕсли что-то ❌ — открой Claude Code в C:\NL_produkt и скажи «проверь ботов»."

$url  = "https://api.telegram.org/bot$token/sendMessage"
$body = @{ chat_id = $chat; text = $msg; parse_mode = 'HTML' } | ConvertTo-Json -Compress

try {
  $resp = Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json' -Body $body -TimeoutSec 15
  if ($resp.ok) { Write-Host "✅ Напоминание отправлено (message_id=$($resp.result.message_id))"; exit 0 }
  else { Write-Host "❌ Telegram: $($resp | ConvertTo-Json -Compress)"; exit 1 }
} catch {
  Write-Host "❌ Ошибка отправки: $($_.Exception.Message)"; exit 1
}
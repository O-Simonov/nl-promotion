# Проверка всех ботов — запускай после 12:00
$tasks = @(
    @{ Name="NL-Queue-Refill";      Time="09:00" },
    @{ Name="NL-Telegram-AutoPost"; Time="10:00" },
    @{ Name="NL-FB-AutoPost";       Time="11:00" },
    @{ Name="NL-IG-AutoPost";       Time="12:00" },
    @{ Name="NL-VK-AutoPost";       Time="14:00" }
)

Write-Host "=== Проверка ботов NL ===" -ForegroundColor Cyan
Write-Host ""

foreach ($t in $tasks) {
    $info = Get-ScheduledTaskInfo -TaskName $t.Name
    $ok   = $info.LastTaskResult -eq 0
    $ran  = $info.LastRunTime.Date -eq (Get-Date).Date

    $status = if ($ran -and $ok)   { "УСПЕХ ✓" }
              elseif ($ran -and !$ok) { "ОШИБКА ✗ (код $($info.LastTaskResult))" }
              else                    { "НЕ ЗАПУСКАЛСЯ сегодня" }

    $color = if ($ran -and $ok) { "Green" } elseif ($ran) { "Red" } else { "Yellow" }
    Write-Host "$($t.Time) $($t.Name): " -NoNewline
    Write-Host $status -ForegroundColor $color
}

Write-Host ""
Write-Host "=== Очередь ===" -ForegroundColor Cyan
$q = (Get-ChildItem C:\NL_produkt\tg-bot\queue\*.txt -ErrorAction SilentlyContinue).Count
$b = (Get-ChildItem C:\NL_produkt\tg-bot\backlog\*.txt -ErrorAction SilentlyContinue).Count
Write-Host "В очереди: $q постов | В бэклоге: $b постов"

Write-Host ""
Write-Host "=== Последние строки логов ===" -ForegroundColor Cyan
@(
    "C:\NL_produkt\tg-bot\logs\post.log",
    "C:\NL_produkt\fb-bot\logs\fb-bot.log",
    "C:\NL_produkt\ig-bot\logs\ig-bot.log",
    "C:\NL_produkt\tg-bot\logs\refill.log"
) | ForEach-Object {
    if (Test-Path $_) {
        $last = Get-Content $_ -Tail 1
        Write-Host "$(Split-Path -Leaf $_): $last"
    }
}

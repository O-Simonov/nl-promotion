# Fetch-NL-News.ps1 — собирает свежие посты из публичного канала NL (t.me/s/<channel>)
# в локальный дайджест news-watch/digest.md. Источник материалов для постов.
# Без логина и без api_id — читает публичное веб-превью канала.
# Требуется PowerShell 7+ (pwsh). Запуск вручную или по расписанию (Setup-Schedule-News.ps1).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- какие каналы мониторим (только публичные каналы; группы-обсуждения превью не дают) ---
$channels = @('nl25_news')

$digestFile = Join-Path $root 'digest.md'
$stateFile  = Join-Path $root 'state.json'
$logDir     = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'news.log'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Tee-Object -FilePath $logFile -Append }

# --- состояние: последний обработанный id поста по каждому каналу ---
$state = @{}
if (Test-Path $stateFile) {
    try { (Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = [int]$_.Value } } catch {}
}

# --- HTML -> чистый текст ---
function Clean-Text([string]$html) {
    if (-not $html) { return '' }
    $t = $html -replace '(?i)<br\s*/?>', "`n"
    $t = $t -replace '(?s)<[^>]+>', ''          # вырезаем теги
    $t = [System.Net.WebUtility]::HtmlDecode($t) # &amp; &gt; и т.п.
    $t = $t -replace "[ \t]+", ' '
    $t = ($t -split "`n" | ForEach-Object { $_.Trim() }) -join "`n"
    $t = $t -replace "`n{3,}", "`n`n"
    return $t.Trim()
}

# --- загрузка превью канала с повтором при сбое (1 + 3 повтора, пауза 30с) ---
function Get-ChannelHtml([string]$channel) {
    $url = "https://t.me/s/$channel"
    $maxAttempts = 4; $retryDelaySec = 30
    for ($a = 1; $a -le $maxAttempts; $a++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 25).Content
        } catch {
            if ($a -lt $maxAttempts) {
                Log "[$channel] попытка $a/$maxAttempts не удалась: $($_.Exception.Message). Повтор через $retryDelaySec c..."
                Start-Sleep -Seconds $retryDelaySec
            } else { throw }
        }
    }
}

$allNew = @()  # новые посты со всех каналов

foreach ($channel in $channels) {
    try {
        $html = Get-ChannelHtml $channel
    } catch {
        Log "[$channel] СБОЙ загрузки после всех попыток: $($_.Exception.Message)"
        continue
    }

    $lastId = if ($state.ContainsKey($channel)) { $state[$channel] } else { 0 }
    $maxId  = $lastId

    # каждое сообщение — отдельный блок (.tgme_widget_message_wrap)
    $parts = $html -split '<div class="tgme_widget_message_wrap'
    foreach ($p in $parts) {
        if ($p -notmatch ('data-post="' + [regex]::Escape($channel) + '/(\d+)"')) { continue }
        $id = [int]$Matches[1]
        if ($id -le $lastId) { continue }   # уже видели

        $text = ''
        if ($p -match '(?s)<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>') { $text = Clean-Text $Matches[1] }
        $time = ''
        if ($p -match '<time datetime="([^"]+)"') {
            try { $time = ([datetimeoffset]$Matches[1]).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } catch { $time = $Matches[1] }
        }
        if ($id -gt $maxId) { $maxId = $id }
        $allNew += [pscustomobject]@{ Channel = $channel; Id = $id; Time = $time; Text = $text }
    }
    $state[$channel] = $maxId
}

if ($allNew.Count -eq 0) {
    Log "Новых постов нет."
    ($state | ConvertTo-Json) | Set-Content -Path $stateFile -Encoding UTF8
    exit 0
}

# --- формируем новые записи (новые сверху) и дописываем в начало дайджеста ---
$sb = New-Object System.Text.StringBuilder
foreach ($post in ($allNew | Sort-Object Id -Descending)) {
    $link = "https://t.me/$($post.Channel)/$($post.Id)"
    [void]$sb.AppendLine("## [$($post.Time)] @$($post.Channel)  ·  #$($post.Id)")
    [void]$sb.AppendLine($(if ($post.Text) { $post.Text } else { '(без текста — медиа/файл)' }))
    [void]$sb.AppendLine("🔗 $link")
    [void]$sb.AppendLine('')
}
$newBlock = $sb.ToString()

$old = if (Test-Path $digestFile) { Get-Content $digestFile -Raw -Encoding UTF8 } else { "# Дайджест свежих постов NL (источник для моих постов)`n`n" }
if ($old -notmatch '^# Дайджест') { $old = "# Дайджест свежих постов NL (источник для моих постов)`n`n" + $old }

# вставляем новый блок сразу после заголовка
$header = "# Дайджест свежих постов NL (источник для моих постов)`n`n"
$body   = $old -replace '(?s)^# Дайджест свежих постов NL[^\n]*\n\n', ''
($header + $newBlock + $body) | Set-Content -Path $digestFile -Encoding UTF8

($state | ConvertTo-Json) | Set-Content -Path $stateFile -Encoding UTF8
Log "Добавлено новых постов: $($allNew.Count). Дайджест: $digestFile"

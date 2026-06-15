# Post-Next.ps1 — публикует СЛЕДУЮЩИЙ пост из очереди в Telegram-канал.
# Запускается вручную или по расписанию (см. Setup-Schedule.ps1).
# Требуется PowerShell 7+ (pwsh).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- читаем конфиг ---
$cfgPath = Join-Path $root 'config.json'
if (-not (Test-Path $cfgPath)) { Write-Host "Нет config.json рядом со скриптом."; exit 1 }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$token   = $cfg.botToken
$channel = $cfg.channelId
if ([string]::IsNullOrWhiteSpace($token) -or $token -match 'ВСТАВЬ') {
    Write-Host "В config.json не вставлен токен бота."; exit 1
}

# --- папки ---
$queueDir = Join-Path $root 'queue'
$sentDir  = Join-Path $root 'sent'
$logDir   = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $sentDir, $logDir | Out-Null
$logFile = Join-Path $logDir 'post.log'
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Tee-Object -FilePath $logFile -Append }

# --- берём самый первый пост по имени (01, 02, ...) ---
$post = Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Sort-Object Name | Select-Object -First 1
if (-not $post) { Log "Очередь пуста — постить нечего. Добавь файлы .txt в папку queue."; exit 0 }

$text = Get-Content $post.FullName -Raw -Encoding UTF8

# --- если рядом есть картинка с тем же именем (01-den1.jpg) — шлём с фото ---
$base = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
$img = Get-ChildItem -Path $queueDir -File |
       Where-Object { $_.BaseName -eq $base -and $_.Extension -match '\.(jpg|jpeg|png)$' } |
       Select-Object -First 1
# --- видео с тем же именем (01-reel.mp4) — шлём как видео-пост (вертикальный анонс) ---
$video = Get-ChildItem -Path $queueDir -File |
         Where-Object { $_.BaseName -eq $base -and $_.Extension -match '\.(mp4|mov)$' } |
         Select-Object -First 1

# --- параметры самопроверки/повтора при сбое ---
$maxAttempts   = 4   # 1 основная попытка + 3 повтора
$retryDelaySec = 30  # пауза между попытками

# Отправка с повтором. Возвращает ответ API при успехе; кидает исключение после всех попыток.
# ВАЖНО: внутри только сам вызов публикации — перенос файлов делается ПОСЛЕ успеха,
# поэтому повтор не может привести к двойной публикации.
function Invoke-Publish {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            if ($video) {
                $form = @{ chat_id = $channel; caption = $text; video = Get-Item $video.FullName; supports_streaming = 'true' }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendVideo" -Method Post -Form $form
            } elseif ($img) {
                $form = @{ chat_id = $channel; caption = $text; photo = Get-Item $img.FullName }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendPhoto" -Method Post -Form $form
            } else {
                $body = @{ chat_id = $channel; text = $text; disable_web_page_preview = $true }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body $body
            }
            if (-not $resp.ok) { throw "API вернул ok=false: $($resp | ConvertTo-Json -Compress)" }
            if ($attempt -gt 1) { Log "Успех со $attempt-й попытки." }
            return $resp
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                Log "Попытка $attempt/$maxAttempts не удалась: $($_.Exception.Message). Повтор через $retryDelaySec c..."
                Start-Sleep -Seconds $retryDelaySec
            } else { throw }
        }
    }
}

try {
    $resp = Invoke-Publish

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Move-Item $post.FullName (Join-Path $sentDir "$ts-$($post.Name)")
    if ($img)   { Move-Item $img.FullName   (Join-Path $sentDir "$ts-$($img.Name)") }
    if ($video) { Move-Item $video.FullName (Join-Path $sentDir "$ts-$($video.Name)") }
    $left = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Measure-Object).Count
    Log "OK: опубликован '$($post.Name)'$(if($video){' (видео)'}elseif($img){' (с фото)'}). В очереди осталось: $left."
}
catch {
    Log "СБОЙ после $maxAttempts попыток: '$($post.Name)': $($_.Exception.Message)"
    Log "Подсказка: проверь сеть/доступ к api.telegram.org и что бот — администратор канала."
    exit 1
}

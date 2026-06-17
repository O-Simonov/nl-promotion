# Post-Next.ps1 — публикует СЛЕДУЮЩИЙ пост из очереди в Telegram-канал.
# Запускается вручную или по расписанию (см. Setup-Schedule.ps1).
# Требуется PowerShell 7+ (pwsh).

$ErrorActionPreference = 'Stop'

# Принудительно включаем TLS 1.2/1.3 для .NET HttpClient. На некоторых провайдерах
# [Net.ServicePointManager]::SecurityProtocol = SystemDefault приводит к разрыву
# TLS-хэндшейка (SSL connection could not be established) — например, при DPI или
# при отсутствии записей SCHANNEL\Protocols в реестре. Явное перечисление
# протоколов это решает.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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

# Сразу пишем в лог: если процесс умрёт «молча» (STATUS_CONTROL_C_EXIT),
# будет видно, что скрипт вообще стартовал и какая у него среда.
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
Log "=== СТАРТ Post-Next.ps1 (pid=$PID, user=$env:USERNAME) ==="
Log "SecurityProtocol = $([Net.ServicePointManager]::SecurityProtocol)"
Log "PowerShell = $($PSVersionTable.PSVersion), OS = $([System.Environment]::OSVersion.VersionString)"

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
        # Глобальный wall-clock: 4 попытки × (20с таймаут + 30с пауза) = ≤170с.
        # Если что-то пошло совсем не так — сами себя обрежем, чтобы Планировщик
        # не висел и не убивал процесс на STATUS_CONTROL_C_EXIT.
        if ($swTotal.Elapsed.TotalSeconds -gt 150) { throw "Глобальный таймаут 150с — прерываю, чтобы Планировщик не убил" }
        try {
            if ($video) {
                Log "→ POST https://api.telegram.org/bot…/sendVideo (попытка $attempt/$maxAttempts)"
                $form = @{ chat_id = $channel; caption = $text; video = Get-Item $video.FullName; supports_streaming = 'true' }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendVideo" -Method Post -Form $form -TimeoutSec 20
            } elseif ($img) {
                Log "→ POST https://api.telegram.org/bot…/sendPhoto (попытка $attempt/$maxAttempts)"
                $form = @{ chat_id = $channel; caption = $text; photo = Get-Item $img.FullName }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendPhoto" -Method Post -Form $form -TimeoutSec 20
            } else {
                Log "→ POST https://api.telegram.org/bot…/sendMessage (попытка $attempt/$maxAttempts)"
                $body = @{ chat_id = $channel; text = $text; disable_web_page_preview = $true }
                $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/sendMessage" -Method Post -Body $body -TimeoutSec 20
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
    # --- smoke-test: быстрый GET к API (5с). Если сеть лежит — не мучаем 4×20с. ---
    Log "→ smoke-test https://api.telegram.org/"
    try {
        $null = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getMe" -Method Get -TimeoutSec 5
    } catch {
        $errText = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Log "❌ СЕТЬ НЕДОСТУПНА: $errText — пропускаю пост (он остаётся в очереди)"
        Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
        exit 0
    }

    $resp = Invoke-Publish

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Move-Item $post.FullName (Join-Path $sentDir "$ts-$($post.Name)")
    if ($img)   { Move-Item $img.FullName   (Join-Path $sentDir "$ts-$($img.Name)") }
    if ($video) { Move-Item $video.FullName (Join-Path $sentDir "$ts-$($video.Name)") }
    $left = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Measure-Object).Count
    Log "OK: опубликован '$($post.Name)'$(if($video){' (видео)'}elseif($img){' (с фото)'}). В очереди осталось: $left."
    Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (ОК) ==="
}
catch {
    Log "СБОЙ после $maxAttempts попыток: '$($post.Name)': $($_.Exception.Message)"
    Log "Подсказка: проверь сеть/доступ к api.telegram.org и что бот — администратор канала."
    Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
    exit 1
}

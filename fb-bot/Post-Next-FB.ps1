# Facebook автопостинг — следующий пост из очереди
$ErrorActionPreference = "Stop"

# Принудительно включаем TLS 1.2/1.3 для .NET HttpClient. На некоторых провайдерах
# [Net.ServicePointManager]::SecurityProtocol = SystemDefault приводит к разрыву
# TLS-хэндшейка (SSL connection could not be established) — например, при DPI или
# при отсутствии записей SCHANNEL\Protocols в реестре. Явное перечисление
# протоколов это решает.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$queueDir   = Join-Path $scriptDir "..\tg-bot\queue"
$sentDir    = Join-Path $scriptDir "sent"
$logFile    = Join-Path $scriptDir "logs\fb-bot.log"

New-Item -ItemType Directory -Force -Path $sentDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir "logs") | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# Сразу пишем в лог: если процесс умрёт «молча» (STATUS_CONTROL_C_EXIT),
# будет видно, что скрипт вообще стартовал и какая у него среда.
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log "=== СТАРТ Post-Next-FB.ps1 (pid=$PID, user=$env:USERNAME) ==="
Write-Log "SecurityProtocol = $([Net.ServicePointManager]::SecurityProtocol)"
Write-Log "PowerShell = $($PSVersionTable.PSVersion), OS = $([System.Environment]::OSVersion.VersionString)"

$cfg      = Get-Content $configPath | ConvertFrom-Json
$token    = $cfg.pageToken
$pageId   = $cfg.pageId
$imgbbKey = $cfg.imgbbApiKey
$apiVer   = $cfg.apiVersion

# Берём первый пост из очереди
$post = Get-ChildItem -Path $queueDir -Filter "*.txt" -File | Sort-Object Name | Select-Object -First 1
if (-not $post) {
    Write-Log "Очередь пуста — нечего публиковать."
    exit 0
}

$caption = Get-Content $post.FullName -Raw -Encoding UTF8
$base    = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
$pngPath = Join-Path $queueDir "$base.png"
$jpgPath = Join-Path $queueDir "$base.jpg"
$imgFile = if (Test-Path $pngPath) { $pngPath } elseif (Test-Path $jpgPath) { $jpgPath } else { $null }

Write-Log "Публикую: $($post.Name)$(if ($imgFile) {' + ' + (Split-Path -Leaf $imgFile)} else {' (без картинки)'})"

# --- параметры самопроверки/повтора при сбое ---
$maxAttempts   = 4   # 1 основная попытка + 3 повтора
$retryDelaySec = 30  # пауза между попытками

# Публикация (imgbb при наличии фото -> photos/feed) с повтором. Возвращает Post ID.
# ВАЖНО: финальный вызов публикации — последний шаг; перенос файлов делается ПОСЛЕ успеха,
# поэтому повтор не приводит к двойной публикации.
function Invoke-Publish {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        # Глобальный wall-clock: 4 попытки × (20с таймаут + 30с пауза) = ≤170с.
        # Если что-то пошло совсем не так — сами себя обрежем, чтобы Планировщик
        # не висел и не убивал процесс на STATUS_CONTROL_C_EXIT.
        if ($swTotal.Elapsed.TotalSeconds -gt 150) { throw "Глобальный таймаут 150с — прерываю, чтобы Планировщик не убил" }
        try {
            if ($imgFile) {
                Write-Log "→ POST api.imgbb.com/1/upload (попытка $attempt/$maxAttempts)"
                $imgBytes  = [System.IO.File]::ReadAllBytes($imgFile)
                $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
                $imgbbResp = Invoke-RestMethod -Method Post -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" -Body @{ image = $imgBase64 } -TimeoutSec 20
                if (-not $imgbbResp.data.url) { throw "imgbb не вернул URL" }
                Write-Log "→ POST graph.facebook.com/$apiVer/$pageId/photos (попытка $attempt/$maxAttempts)"
                $r = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$pageId/photos" -Body @{
                    url = $imgbbResp.data.url; caption = $caption; access_token = $token
                } -TimeoutSec 20
            } else {
                Write-Log "→ POST graph.facebook.com/$apiVer/$pageId/feed (попытка $attempt/$maxAttempts)"
                $r = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$pageId/feed" -Body @{
                    message = $caption; access_token = $token
                } -TimeoutSec 20
            }
            $postId = $r.id ?? $r.post_id
            if (-not $postId) { throw "нет Post ID в ответе: $($r | ConvertTo-Json -Compress)" }
            if ($attempt -gt 1) { Write-Log "Успех со $attempt-й попытки." }
            return $postId
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                Write-Log "Попытка $attempt/$maxAttempts не удалась: $($_.Exception.Message). Повтор через $retryDelaySec c..."
                Start-Sleep -Seconds $retryDelaySec
            } else { throw }
        }
    }
}

try {
    # --- smoke-test: быстрый GET к Graph API (5с). Если сеть лежит — не мучаем 4×20с. ---
    Write-Log "→ smoke-test graph.facebook.com"
    try {
        # ВАЖНО: `? экранирует '?' — иначе PowerShell «съедает» $pageId и fields,
        # URI ломается (…/v25.0/=id&access_token=…) и Graph API всегда отвечает 400.
        $null = Invoke-RestMethod -Uri "https://graph.facebook.com/$apiVer/$pageId`?fields=id&access_token=$token" -TimeoutSec 5
    } catch {
        $errText = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-Log "❌ СЕТЬ НЕДОСТУПНА: $errText — пропускаю пост (он остаётся в очереди)"
        Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
        exit 0
    }

    $postId = Invoke-Publish
    Write-Log "УСПЕХ! Post ID: $postId"

    # Перемещаем файлы в sent/
    Move-Item -Path $post.FullName -Destination (Join-Path $sentDir $post.Name)
    if ($imgFile) { Move-Item -Path $imgFile -Destination (Join-Path $sentDir (Split-Path -Leaf $imgFile)) }
    Write-Log "Файлы перемещены в sent/"
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (ОК) ==="

    # Сброс счётчика ошибок Meta при успехе
    $errCounter = Join-Path $scriptDir "logs\meta-error-count.txt"
    if (Test-Path $errCounter) { Remove-Item $errCounter -Force }

} catch {
    $errMsg = $_.Exception.Message
    Write-Log "СБОЙ после $maxAttempts попыток: $errMsg"
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (FAIL) ==="

    # Считаем подряд идущие ошибки Meta (400, checkpoint и т.п.)
    $errCounter = Join-Path $scriptDir "logs\meta-error-count.txt"
    $count = 0
    if (Test-Path $errCounter) { [int]$count = (Get-Content $errCounter -Raw).Trim() }
    $count++
    Set-Content -Path $errCounter -Value $count

    # Если 3-й сбой подряд — уведомляем Олега в TG-канал (НЕ падаем, если Notify не сработал)
    if ($count -ge 3) {
        try {
            $notifyScript = Join-Path $PSScriptRoot "..\Notify-Owner.ps1"
            if (Test-Path $notifyScript) {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $notifyScript `
                    -Message "⚠️ <b>FB-бот</b> упал <b>$count раз подряд</b>.%0A%0AПоследняя ошибка:%0A<code>$([System.Web.HttpUtility]::HtmlEncode($errMsg))</code>%0A%0AСкорее всего, Meta-токен в checkpoint (subcode 459). Зайди в <b>facebook.com</b>, пройди проверку, потом скажи мне — я разгребу очередь."
                Write-Log "🚨 Уведомление отправлено (ошибка #$count)"
            }
        } catch { Write-Log "⚠️ Не удалось отправить уведомление: $($_.Exception.Message)" }
    }

    exit 1
}

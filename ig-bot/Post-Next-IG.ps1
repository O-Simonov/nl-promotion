# Instagram автопостинг — следующий пост из очереди с картинкой
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
$logFile    = Join-Path $scriptDir "logs\ig-bot.log"

New-Item -ItemType Directory -Force -Path $sentDir  | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir "logs") | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# Сразу пишем в лог: если процесс умрёт «молча» (STATUS_CONTROL_C_EXIT),
# будет видно, что скрипт вообще стартовал и какая у него среда.
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log "=== СТАРТ Post-Next-IG.ps1 (pid=$PID, user=$env:USERNAME) ==="
Write-Log "SecurityProtocol = $([Net.ServicePointManager]::SecurityProtocol)"
Write-Log "PowerShell = $($PSVersionTable.PSVersion), OS = $([System.Environment]::OSVersion.VersionString)"

$cfg       = Get-Content $configPath | ConvertFrom-Json
$token     = $cfg.pageToken
$igId      = $cfg.igUserId
$imgbbKey  = $cfg.imgbbApiKey
$apiVer    = $cfg.apiVersion

# Найти следующий пост с картинкой
$queueFiles = Get-ChildItem -Path $queueDir -Filter "*.txt" | Sort-Object Name

$postFile  = $null
$imageFile = $null

foreach ($f in $queueFiles) {
    $base    = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $pngPath = Join-Path $queueDir "$base.png"
    $jpgPath = Join-Path $queueDir "$base.jpg"
    if (Test-Path $pngPath) { $postFile = $f; $imageFile = $pngPath; break }
    if (Test-Path $jpgPath) { $postFile = $f; $imageFile = $jpgPath; break }
}

if (-not $postFile) {
    Write-Log "ПРОПУСК: не найдено постов с картинкой в очереди."
    exit 0
}

Write-Log "Публикую пост: $($postFile.Name) + $(Split-Path -Leaf $imageFile)"

# Читаем текст поста
$caption = Get-Content $postFile.FullName -Raw -Encoding UTF8

# --- параметры самопроверки/повтора при сбое ---
$maxAttempts   = 4   # 1 основная попытка + 3 повтора
$retryDelaySec = 30  # пауза между попытками

# Полная публикация (imgbb -> контейнер -> media_publish) с повтором. Возвращает ответ публикации.
# ВАЖНО: media_publish — последний шаг; перенос файлов делается ПОСЛЕ успеха,
# поэтому повтор не приводит к двойной публикации.
function Invoke-Publish {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        # Глобальный wall-clock: 4 попытки × (20с таймаут + 30с пауза) = ≤170с.
        # Если что-то пошло совсем не так — сами себя обрежем, чтобы Планировщик
        # не висел и не убивал процесс на STATUS_CONTROL_C_EXIT.
        if ($swTotal.Elapsed.TotalSeconds -gt 150) { throw "Глобальный таймаут 150с — прерываю, чтобы Планировщик не убил" }
        try {
            # 1. Загружаем картинку на imgbb
            Write-Log "→ POST api.imgbb.com/1/upload (попытка $attempt/$maxAttempts)"
            $imgBytes  = [System.IO.File]::ReadAllBytes($imageFile)
            $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
            $imgbbResponse = Invoke-RestMethod -Method Post -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" -Body @{ image = $imgBase64 } -TimeoutSec 20
            if (-not $imgbbResponse.data.url) { throw "imgbb не вернул URL" }
            $imageUrl = $imgbbResponse.data.url

            # 2. Создаём контейнер в Instagram
            Write-Log "→ POST graph.facebook.com/$apiVer/$igId/media (попытка $attempt/$maxAttempts)"
            $containerResponse = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media" -Body @{
                image_url = $imageUrl; caption = $caption; access_token = $token
            } -TimeoutSec 20
            if (-not $containerResponse.id) { throw "не получен id контейнера: $($containerResponse | ConvertTo-Json -Compress)" }

            # 3. Пауза — Instagram требует время перед публикацией
            Start-Sleep -Seconds 10

            # 4. Публикуем контейнер
            Write-Log "→ POST graph.facebook.com/$apiVer/$igId/media_publish (попытка $attempt/$maxAttempts)"
            $publishResponse = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media_publish" -Body @{
                creation_id = $containerResponse.id; access_token = $token
            } -TimeoutSec 20
            if (-not $publishResponse.id) { throw "публикация не удалась: $($publishResponse | ConvertTo-Json -Compress)" }
            if ($attempt -gt 1) { Write-Log "Успех со $attempt-й попытки." }
            return $publishResponse
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
        # ВАЖНО: `? экранирует '?' — иначе PowerShell «съедает» $igId и fields,
        # URI ломается (…/v25.0/=id&access_token=…) и Graph API всегда отвечает 400.
        $null = Invoke-RestMethod -Uri "https://graph.facebook.com/$apiVer/$igId`?fields=id&access_token=$token" -TimeoutSec 5
    } catch {
        $errText = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-Log "❌ СЕТЬ НЕДОСТУПНА: $errText — пропускаю пост (он остаётся в очереди)"
        Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
        exit 0
    }

    $publishResponse = Invoke-Publish
    Write-Log "УСПЕХ! Пост опубликован. ID: $($publishResponse.id)"

    # Перемещаем файлы в sent/
    Move-Item -Path $postFile.FullName -Destination (Join-Path $sentDir $postFile.Name)
    Move-Item -Path $imageFile         -Destination (Join-Path $sentDir (Split-Path -Leaf $imageFile))
    Write-Log "Файлы перемещены в sent/: $($postFile.Name), $(Split-Path -Leaf $imageFile)"
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (ОК) ==="

    # Сброс счётчика ошибок Meta при успехе
    $errCounter = Join-Path $scriptDir "logs\meta-error-count.txt"
    if (Test-Path $errCounter) { Remove-Item $errCounter -Force }

}
catch {
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
                    -Message "⚠️ <b>IG-бот</b> упал <b>$count раз подряд</b>.%0A%0AПоследняя ошибка:%0A<code>$([System.Web.HttpUtility]::HtmlEncode($errMsg))</code>%0A%0AСкорее всего, Meta-токен в checkpoint (subcode 459). Зайди в <b>facebook.com</b>, пройди проверку, потом скажи мне — я разгребу очередь."
                Write-Log "🚨 Уведомление отправлено (ошибка #$count)"
            }
        } catch { Write-Log "⚠️ Не удалось отправить уведомление: $($_.Exception.Message)" }
    }

    exit 1
}

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
        try {
            # 1. Загружаем картинку на imgbb
            $imgBytes  = [System.IO.File]::ReadAllBytes($imageFile)
            $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
            $imgbbResponse = Invoke-RestMethod -Method Post -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" -Body @{ image = $imgBase64 }
            if (-not $imgbbResponse.data.url) { throw "imgbb не вернул URL" }
            $imageUrl = $imgbbResponse.data.url

            # 2. Создаём контейнер в Instagram
            $containerResponse = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media" -Body @{
                image_url = $imageUrl; caption = $caption; access_token = $token
            }
            if (-not $containerResponse.id) { throw "не получен id контейнера: $($containerResponse | ConvertTo-Json -Compress)" }

            # 3. Пауза — Instagram требует время перед публикацией
            Start-Sleep -Seconds 10

            # 4. Публикуем контейнер
            $publishResponse = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media_publish" -Body @{
                creation_id = $containerResponse.id; access_token = $token
            }
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
    $publishResponse = Invoke-Publish
    Write-Log "УСПЕХ! Пост опубликован. ID: $($publishResponse.id)"

    # Перемещаем файлы в sent/
    Move-Item -Path $postFile.FullName -Destination (Join-Path $sentDir $postFile.Name)
    Move-Item -Path $imageFile         -Destination (Join-Path $sentDir (Split-Path -Leaf $imageFile))
    Write-Log "Файлы перемещены в sent/: $($postFile.Name), $(Split-Path -Leaf $imageFile)"
}
catch {
    Write-Log "СБОЙ после $maxAttempts попыток: $($postFile.Name): $($_.Exception.Message)"
    exit 1
}

# Instagram автопостинг — следующий пост из очереди с картинкой
$ErrorActionPreference = "Stop"

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

# 1. Загружаем картинку на imgbb
Write-Log "Загружаю картинку на imgbb..."
$imgBytes  = [System.IO.File]::ReadAllBytes($imageFile)
$imgBase64 = [System.Convert]::ToBase64String($imgBytes)

$imgbbResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" `
    -Body @{ image = $imgBase64 }

if (-not $imgbbResponse.data.url) {
    Write-Log "ОШИБКА: imgbb не вернул URL."
    exit 1
}

$imageUrl = $imgbbResponse.data.url
Write-Log "Картинка загружена: $imageUrl"

# 2. Создаём контейнер в Instagram
Write-Log "Создаю контейнер в Instagram..."
$containerResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://graph.facebook.com/$apiVer/$igId/media" `
    -Body @{
        image_url  = $imageUrl
        caption    = $caption
        access_token = $token
    }

if (-not $containerResponse.id) {
    Write-Log "ОШИБКА: не получен id контейнера. Ответ: $($containerResponse | ConvertTo-Json)"
    exit 1
}

$containerId = $containerResponse.id
Write-Log "Контейнер создан: $containerId"

# 3. Ждём — Instagram требует паузу перед публикацией
Write-Log "Ожидание 10 секунд перед публикацией..."
Start-Sleep -Seconds 10

# 4. Публикуем контейнер
Write-Log "Публикую пост..."
$publishResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://graph.facebook.com/$apiVer/$igId/media_publish" `
    -Body @{
        creation_id  = $containerId
        access_token = $token
    }

if (-not $publishResponse.id) {
    Write-Log "ОШИБКА: публикация не удалась. Ответ: $($publishResponse | ConvertTo-Json)"
    exit 1
}

Write-Log "УСПЕХ! Пост опубликован. ID: $($publishResponse.id)"

# 5. Перемещаем файлы в sent/
$sentTxt = Join-Path $sentDir $postFile.Name
$sentImg = Join-Path $sentDir (Split-Path -Leaf $imageFile)
Move-Item -Path $postFile.FullName -Destination $sentTxt
Move-Item -Path $imageFile         -Destination $sentImg

Write-Log "Файлы перемещены в sent/: $($postFile.Name), $(Split-Path -Leaf $imageFile)"

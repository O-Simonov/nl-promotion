# Facebook автопостинг — следующий пост из очереди
$ErrorActionPreference = "Stop"

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

try {
    if ($imgFile) {
        # Загружаем картинку на imgbb
        Write-Log "Загружаю картинку на imgbb..."
        $imgBytes  = [System.IO.File]::ReadAllBytes($imgFile)
        $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
        $imgbbResp = Invoke-RestMethod -Method Post `
            -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" `
            -Body @{ image = $imgBase64 }
        $imageUrl = $imgbbResp.data.url
        Write-Log "Картинка: $imageUrl"

        # Публикуем с фото
        $r = Invoke-RestMethod -Method Post `
            -Uri "https://graph.facebook.com/$apiVer/$pageId/photos" `
            -Body @{ url = $imageUrl; caption = $caption; access_token = $token }
    } else {
        # Публикуем текст
        $r = Invoke-RestMethod -Method Post `
            -Uri "https://graph.facebook.com/$apiVer/$pageId/feed" `
            -Body @{ message = $caption; access_token = $token }
    }

    Write-Log "УСПЕХ! Post ID: $($r.id ?? $r.post_id)"

    # Перемещаем файлы в sent/
    Move-Item -Path $post.FullName -Destination (Join-Path $sentDir $post.Name)
    if ($imgFile) { Move-Item -Path $imgFile -Destination (Join-Path $sentDir (Split-Path -Leaf $imgFile)) }
    Write-Log "Файлы перемещены в sent/"

} catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)"
    exit 1
}

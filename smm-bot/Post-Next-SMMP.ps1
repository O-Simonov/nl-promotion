# Post-Next-SMMP.ps1 — публикует следующий пост из общей очереди через SMMplanner API v2.
# Один пост → сразу во все подключённые соцсети (MAX, ОК, YouTube — кому доступно).
# Берёт из общей очереди tg-bot/queue/, переносит в smm-bot/sent/.

# --- ДОКУМЕНТАЦИЯ SMMplanner API v2 ---
# Документация:    https://smmplanner.com/api-documentation-v1.php (есть раздел v2)
# Получить токен:  SMMplanner → Настройки → API-ключи
# Endpoint:        POST https://api.smmplanner.com/pub/v2/
# Параметры:
#   access_token  — в теле POST
#   account[]     — ID аккаунтов SMMplanner (массив)
#   content       — текст поста
#   image[0..n]   — URL картинок
#   publish_at    — 'YYYY-MM-DD HH:MM:SS' (если пусто — публикация сразу)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- читаем конфиг ---
$cfgPath = Join-Path $root 'config.json'
if (-not (Test-Path $cfgPath)) { Write-Host "Нет config.json рядом со скриптом."; exit 1 }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$accessToken = $cfg.accessToken
$accountIds  = $cfg.accountIds   # массив ID аккаунтов SMMplanner (для MAX, ОК и т.д.)
$publishDelayHours = if ($cfg.publishDelayHours) { [int]$cfg.publishDelayHours } else { 4 }
if ([string]::IsNullOrWhiteSpace($accessToken) -or $accessToken -match 'ВСТАВЬ') {
    Write-Host "В config.json не вставлен access_token."; exit 1
}
if (-not $accountIds -or $accountIds.Count -eq 0) {
    Write-Host "В config.json не указаны accountIds (ID аккаунтов SMMplanner)."; exit 1
}

# --- папки ---
$rootTg = Split-Path -Parent $root
$queueDir = Join-Path $rootTg 'tg-bot/queue'
$sentDir  = Join-Path $root 'sent'
$logDir   = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $sentDir, $logDir | Out-Null
$logFile = Join-Path $logDir 'post.log'
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Tee-Object -FilePath $logFile -Append }

# --- берём следующий пост ---
$post = Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Sort-Object Name | Select-Object -First 1
if (-not $post) { Log "Очередь пуста — постить нечего."; exit 0 }

$text = Get-Content $post.FullName -Raw -Encoding UTF8

# --- ищем картинку (если есть) ---
$base = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
$img  = Get-ChildItem -Path $queueDir -File |
        Where-Object { $_.BaseName -eq $base -and $_.Extension -match '\.(jpg|jpeg|png)$' } |
        Select-Object -First 1

# --- готовим тело запроса ---
$publishAt = (Get-Date).AddHours($publishDelayHours).ToString('yyyy-MM-dd HH:mm:ss')

$body = @{
    access_token = $accessToken
    content      = $text
    publish_at   = $publishAt
}
foreach ($acc in $accountIds) {
    $body['account[]'] = $acc
}

# Если есть картинка — SMMplanner v2 требует публичный URL
# Локальный файл нужно сначала загрузить на свой хостинг (Netlify, S3, и т.д.)
# У нас простой путь: загружаем в "api.smmplanner.com/uploader/" если поддерживается
if ($img) {
    Log "Загружаю фото $($img.Name) в SMMplanner..."
    try {
        $uploadForm = @{ file = Get-Item $img.FullName }
        $uploadResp = Invoke-RestMethod -Uri "https://api.smmplanner.com/uploader/" -Method Post -Form $uploadForm
        if ($uploadResp.url) {
            $body['image[0]'] = $uploadResp.url
        } else {
            Log "Не удалось загрузить фото: $($uploadResp | ConvertTo-Json -Compress). Постим без картинки."
        }
    } catch {
        Log "Ошибка загрузки фото: $($_.Exception.Message). Постим без картинки."
    }
}

# --- публикуем ---
$uri = 'https://api.smmplanner.com/pub/v2/'
try {
    Log "Публикую '$($post.Name)' в SMMplanner (аккаунты: $($accountIds -join ', ')), publish_at=$publishAt..."
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'

    # SMMplanner v2 возвращает либо {id, account, status, code}, либо {data: [...]}
    if ($resp.code -eq 200 -or $resp.status -eq 'OK') {
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        Move-Item $post.FullName (Join-Path $sentDir "$ts-$($post.Name)")
        if ($img) { Move-Item $img.FullName (Join-Path $sentDir "$ts-$($img.Name)") }
        $left = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Measure-Object).Count
        Log "OK: опубликован '$($post.Name)' через SMMplanner. ID поста: $($resp.id). В очереди осталось: $left."
    } else {
        Log "Ответ API: $($resp | ConvertTo-Json -Compress)"
        exit 1
    }
}
catch {
    Log "Сбой публикации: $($_.Exception.Message)"
    Log "Подсказки: (1) проверь access_token; (2) проверь, что accountIds верные (числа); (3) проверь интернет."
    exit 1
}

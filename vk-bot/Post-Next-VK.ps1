# Post-Next-VK.ps1 — публикует СЛЕДУЮЩИЙ пост из общей очереди в сообщество ВКонтакте.
# Запускается вручную или по расписанию (см. Setup-Schedule-VK.ps1).
# Требуется PowerShell 7+ (pwsh).
#
# Отличия от TG-бота:
#   - Публикует от имени сообщества (не личного аккаунта).
#   - VK требует сначала загрузить фото (получить upload_url), затем прикрепить к посту.
#   - Текст в ВК можно длинее (до 15 000 символов), хэштеги публикуем в конце.
#   - Если рядом с .txt лежит .png/.jpg — публикуем с фото; иначе — только текст.

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
$token    = $cfg.botToken     # access_token сообщества (НЕ путать с user token)
$groupId  = [int]$cfg.groupId  # ID сообщества (без минуса)
$apiVer   = if ($cfg.apiVersion) { $cfg.apiVersion } else { '5.199' }
if ([string]::IsNullOrWhiteSpace($token) -or $token -match 'ВСТАВЬ') {
    Write-Host "В config.json не вставлен токен сообщества."; exit 1
}

# --- папки ---
# VK-бот берёт из ОБЩЕЙ очереди tg-bot/queue/ (туда же пишет и TG-бот)
$rootTg = Split-Path -Parent $root
$queueDir = Join-Path $rootTg 'tg-bot/queue'
$sentDir  = Join-Path $root 'sent'
$logDir   = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $sentDir, $logDir | Out-Null
$logFile = Join-Path $logDir 'post.log'
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Tee-Object -FilePath $logFile -Append }

# --- берём самый первый пост по имени ---
$post = Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Sort-Object Name | Select-Object -First 1
if (-not $post) { Log "Очередь пуста — постить нечего. Добавь файлы .txt в папку queue."; exit 0 }

$text = Get-Content $post.FullName -Raw -Encoding UTF8

# --- ищем картинку с тем же именем ---
$base = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
$img = Get-ChildItem -Path $queueDir -File |
       Where-Object { $_.BaseName -eq $base -and $_.Extension -match '\.(jpg|jpeg|png)$' } |
       Select-Object -First 1

# --- хелпер для вызова VK API ---
function Vk-Call([string]$method, [hashtable]$params) {
    $params['access_token'] = $token
    $params['v'] = $apiVer
    $uri = "https://api.vk.com/method/$method"
    $body = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))"
    }) -join '&'
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    if ($resp.error) {
        throw "VK API error: $($resp.error.error_code) $($resp.error.error_msg)"
    }
    return $resp.response
}

# --- параметры самопроверки/повтора при сбое ---
$maxAttempts   = 4   # 1 основная попытка + 3 повтора
$retryDelaySec = 30  # пауза между попытками

# Полная публикация (загрузка фото + wall.post) с повтором. Возвращает результат wall.post.
# ВАЖНО: финальный wall.post — последний шаг; перенос файлов делается ПОСЛЕ успеха,
# поэтому повтор не приводит к двойной публикации (промежуточные шаги идемпотентны).
function Invoke-Publish {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $attachments = @()

            # Если есть картинка — загружаем через photos.getWallUploadServer
            if ($img) {
                $uploadInfo = Vk-Call 'photos.getWallUploadServer' @{ group_id = $groupId }
                $uploadUrl = $uploadInfo.upload_url
                $uploadResp = Invoke-RestMethod -Uri $uploadUrl -Method Post -Form @{ photo = Get-Item $img.FullName }
                if ($uploadResp.error) { throw "Upload error: $($uploadResp.error)" }
                $savedPhotos = Vk-Call 'photos.saveWallPhoto' @{
                    group_id = $groupId; photo = $uploadResp.photo; server = $uploadResp.server; hash = $uploadResp.hash
                }
                foreach ($p in $savedPhotos) { $attachments += "photo$($p.owner_id)_$($p.id)" }
            }

            # Публикуем пост от имени сообщества
            $postParams = @{ owner_id = -$groupId; from_group = 1; message = $text }
            if ($attachments.Count -gt 0) { $postParams['attachments'] = ($attachments -join ',') }
            $result = Vk-Call 'wall.post' $postParams
            if (-not $result.post_id) { throw "wall.post без post_id: $($result | ConvertTo-Json -Compress)" }
            if ($attempt -gt 1) { Log "Успех со $attempt-й попытки." }
            return $result
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
    Log "Публикую '$($post.Name)'..."
    $result = Invoke-Publish

    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Move-Item $post.FullName (Join-Path $sentDir "$ts-$($post.Name)")
    if ($img) { Move-Item $img.FullName (Join-Path $sentDir "$ts-$($img.Name)") }
    $left = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File | Measure-Object).Count
    Log "OK: опубликован '$($post.Name)' (post_id=$($result.post_id)). В очереди осталось: $left."
}
catch {
    Log "СБОЙ после $maxAttempts попыток: '$($post.Name)': $($_.Exception.Message)"
    Log "Подсказки: (1) пользовательский токен админа с правами wall,photos; (2) аккаунт — админ сообщества; (3) версия API актуальна."
    exit 1
}

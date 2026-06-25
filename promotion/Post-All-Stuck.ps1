# Post-All-Stuck.ps1 — публикует ВСЕ посты из общей очереди в IG+FB
# Использование: pwsh -File Post-All-Stuck.ps1 [-MaxCount N] [-SkipIG] [-SkipFB]
#
# После разблокировки Meta-токена отправляет все накопившиеся посты разом.
# Безопасно: каждый пост проверяется, пауза между публикациями 60 сек
# (защита от rate-limit Meta).

param(
    [int]$MaxCount = 0,    # 0 = все посты; >0 = только первые N
    [switch]$SkipIG = $false,
    [switch]$SkipFB = $false
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$queueDir     = Join-Path $scriptDir "..\tg-bot\queue"
$igConfigPath = Join-Path $scriptDir "..\ig-bot\config.json"
$fbConfigPath = Join-Path $scriptDir "..\fb-bot\config.json"
$igSentDir    = Join-Path $scriptDir "..\ig-bot\sent"
$fbSentDir    = Join-Path $scriptDir "..\fb-bot\sent"
$logFile      = Join-Path $scriptDir "logs\post-all-stuck.log"

New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null
New-Item -ItemType Directory -Force -Path $igSentDir | Out-Null
New-Item -ItemType Directory -Force -Path $fbSentDir | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Publish-ToIG($igId, $token, $imgbbKey, $apiVer, $imageFile, $caption) {
    $imgBytes  = [System.IO.File]::ReadAllBytes($imageFile)
    $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
    $imgbbResp = Invoke-RestMethod -Method Post -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" -Body @{ image = $imgBase64 } -TimeoutSec 30
    if (-not $imgbbResp.data.url) { throw "imgbb не вернул URL" }
    $container = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media" -Body @{
        image_url = $imgbbResp.data.url; caption = $caption; access_token = $token
    } -TimeoutSec 30
    if (-not $container.id) { throw "нет container id" }
    Start-Sleep -Seconds 10
    $pub = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media_publish" -Body @{
        creation_id = $container.id; access_token = $token
    } -TimeoutSec 30
    if (-not $pub.id) { throw "публикация не удалась" }
    return $pub.id
}

function Publish-ToFB($pageId, $token, $apiVer, $imageFile, $caption) {
    # 1. Загружаем фото напрямую в FB (без imgbb, через multipart)
    Add-Type -AssemblyName System.Net.Http
    $client = [System.Net.Http.HttpClient]::new()
    $content = [System.Net.Http.MultipartFormDataContent]::new()
    $fileStream = [System.IO.File]::OpenRead($imageFile)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
    $content.Add($fileContent, "source", (Split-Path -Leaf $imageFile))
    $content.Add([System.Net.Http.StringContent]::new($caption), "caption")
    $content.Add([System.Net.Http.StringContent]::new($token), "access_token")
    $resp = $client.PostAsync("https://graph.facebook.com/$apiVer/$pageId/photos", $content).Result
    $body = $resp.Content.ReadAsStringAsync().Result
    $fileStream.Close()
    if (-not $resp.IsSuccessStatusCode) { throw "FB upload failed: $body" }
    return $body
}

Write-Log "=== СТАРТ Post-All-Stuck.ps1 (SkipIG=$SkipIG SkipFB=$SkipFB MaxCount=$MaxCount) ==="

$igCfg = Get-Content $igConfigPath | ConvertFrom-Json
$fbCfg = Get-Content $fbConfigPath | ConvertFrom-Json

# Собираем список постов с картинками
$posts = Get-ChildItem -Path $queueDir -Filter "*.txt" | Sort-Object Name | ForEach-Object {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $png  = Join-Path $queueDir "$base.png"
    $jpg  = Join-Path $queueDir "$base.jpg"
    if (Test-Path $png) { return [PSCustomObject]@{ Name = $_.Name; Img = $png; Caption = (Get-Content $_.FullName -Raw -Encoding UTF8) } }
    if (Test-Path $jpg) { return [PSCustomObject]@{ Name = $_.Name; Img = $jpg; Caption = (Get-Content $_.FullName -Raw -Encoding UTF8) } }
} | Where-Object { $_ }

if ($MaxCount -gt 0) { $posts = $posts | Select-Object -First $MaxCount }

Write-Log "Найдено постов в очереди: $($posts.Count)"

$success = 0; $fail = 0
foreach ($p in $posts) {
    Write-Log "--- Пост: $($p.Name) ---"

    # IG
    if (-not $SkipIG) {
        try {
            $id = Publish-ToIG $igCfg.igUserId $igCfg.pageToken $igCfg.imgbbApiKey $igCfg.apiVersion $p.Img $p.Caption
            Write-Log "IG: ✅ опубликован, id=$id"
            Move-Item $p.Img -Destination (Join-Path $igSentDir (Split-Path -Leaf $p.Img)) -Force
            Move-Item (Join-Path $queueDir $p.Name) -Destination (Join-Path $igSentDir $p.Name) -Force
        } catch {
            Write-Log "IG: ❌ $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds 2

    # FB
    if (-not $SkipFB) {
        try {
            $resp = Publish-ToFB $fbCfg.pageId $fbCfg.pageToken $fbCfg.apiVersion $p.Img $p.Caption
            Write-Log "FB: ✅ опубликован"
            # FB файлы НЕ перемещаем — там своя логика (FB-бот сам забирает из queue/)
            # Просто логируем успех
        } catch {
            Write-Log "FB: ❌ $($_.Exception.Message)"
        }
    }

    $success++
    Write-Log "Пауза 60с перед следующим постом..."
    Start-Sleep -Seconds 60
}

Write-Log "=== ГОТОВО. Опубликовано: $success из $($posts.Count) ==="

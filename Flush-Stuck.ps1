# Flush-Stuck.ps1 — публикует все застрявшие посты из общей очереди в IG+FB
#
# Сценарий: Meta-токен был заблокирован, посты накопились в queue/.
# Этот скрипт проходит по очереди, публикует каждый пост и в IG, и в FB,
# после чего удаляет .txt/.png из очереди (чтобы TG/VK не публиковали дубли).
#
# Использование:
#   pwsh -File Flush-Stuck.ps1                 # все посты из queue/
#   pwsh -File Flush-Stuck.ps1 -MaxCount 3     # только первые 3 (для теста)

param(
    [int]$MaxCount = 0   # 0 = все; >0 = только N
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$queueDir     = Join-Path $scriptDir "tg-bot\queue"
$igConfigPath = Join-Path $scriptDir "ig-bot\config.json"
$fbConfigPath = Join-Path $scriptDir "fb-bot\config.json"
$logFile      = Join-Path $scriptDir "promotion\logs\flush-stuck.log"

New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Publish-IG($igId, $token, $imgbbKey, $apiVer, $imageFile, $caption) {
    $imgBytes  = [System.IO.File]::ReadAllBytes($imageFile)
    $imgBase64 = [System.Convert]::ToBase64String($imgBytes)
    $imgbbResp = Invoke-RestMethod -Method Post -Uri "https://api.imgbb.com/1/upload?key=$imgbbKey" -Body @{ image = $imgBase64 } -TimeoutSec 30
    if (-not $imgbbResp.data.url) { throw "imgbb не вернул URL" }
    $container = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media" -Body @{
        image_url = $imgbbResp.data.url; caption = $caption; access_token = $token
    } -TimeoutSec 30
    if (-not $container.id) { throw "нет container id: $(($container | ConvertTo-Json -Compress))" }
    Start-Sleep -Seconds 10
    $pub = Invoke-RestMethod -Method Post -Uri "https://graph.facebook.com/$apiVer/$igId/media_publish" -Body @{
        creation_id = $container.id; access_token = $token
    } -TimeoutSec 30
    if (-not $pub.id) { throw "публикация не удалась" }
    return $pub.id
}

function Publish-FB($pageId, $token, $apiVer, $imageFile, $caption) {
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
    $client.Dispose()
    if (-not $resp.IsSuccessStatusCode) { throw "FB upload failed ($($resp.StatusCode)): $body" }
    return $body
}

Write-Log "=== СТАРТ Flush-Stuck.ps1 (MaxCount=$MaxCount) ==="

$igCfg = Get-Content $igConfigPath | ConvertFrom-Json
$fbCfg = Get-Content $fbConfigPath | ConvertFrom-Json

# Собираем посты
$posts = @()
Get-ChildItem -Path $queueDir -Filter "*.txt" | Sort-Object Name | ForEach-Object {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    $png  = Join-Path $queueDir "$base.png"
    $jpg  = Join-Path $queueDir "$base.jpg"
    $imgPath = $null
    if (Test-Path $png) { $imgPath = $png }
    elseif (Test-Path $jpg) { $imgPath = $jpg }
    if ($imgPath) {
        $posts += [PSCustomObject]@{
            Name    = $_.Name
            ImgPath = $imgPath
            Caption = (Get-Content $_.FullName -Raw -Encoding UTF8)
        }
    }
}

if ($MaxCount -gt 0) { $posts = $posts | Select-Object -First $MaxCount }

Write-Log "Найдено постов в очереди: $($posts.Count)"

$okIG = 0; $failIG = 0; $okFB = 0; $failFB = 0
foreach ($p in $posts) {
    Write-Log "--- $($p.Name) ---"
    $igOk = $false; $fbOk = $false

    # --- IG ---
    try {
        $id = Publish-IG $igCfg.igUserId $igCfg.pageToken $igCfg.imgbbApiKey $igCfg.apiVersion $p.ImgPath $p.Caption
        Write-Log "  IG ✅ id=$id"
        $okIG++; $igOk = $true
    } catch {
        Write-Log "  IG ❌ $($_.Exception.Message)"
        $failIG++
    }

    Start-Sleep -Seconds 3

    # --- FB ---
    try {
        $respBody = Publish-FB $fbCfg.pageId $fbCfg.pageToken $fbCfg.apiVersion $p.ImgPath $p.Caption
        Write-Log "  FB ✅ $respBody"
        $okFB++; $fbOk = $true
    } catch {
        Write-Log "  FB ❌ $($_.Exception.Message)"
        $failFB++
    }

    # Если ОБА успешно — удаляем из общей очереди (TG/VK не опубликуют дубль)
    if ($igOk -and $fbOk) {
        Remove-Item $p.ImgPath -Force
        Remove-Item (Join-Path $queueDir $p.Name) -Force
        Write-Log "  🗑 удалено из общей очереди (TG/VK увидят, что постов меньше)"
    } elseif ($igOk -and -not $fbOk) {
        # IG уже запостил — НЕ удаляем, FB-бот подхватит завтра
        Write-Log "  ⚠️ Только IG запостил — оставляю в очереди для FB"
    } elseif (-not $igOk -and $fbOk) {
        # FB уже запостил — НЕ удаляем, IG-бот подхватит завтра
        Write-Log "  ⚠️ Только FB запостил — оставляю в очереди для IG"
    } else {
        Write-Log "  ❌ Оба упали — оставляю в очереди, попробуем позже"
    }

    Start-Sleep -Seconds 30   # пауза между постами (защита от rate-limit)
}

Write-Log "=== ГОТОВО ==="
Write-Log "IG: $okIG ✅ / $failIG ❌"
Write-Log "FB: $okFB ✅ / $failFB ❌"
Write-Log "Осталось в очереди: $((Get-ChildItem $queueDir -Filter '*.txt' | Measure-Object).Count) постов"

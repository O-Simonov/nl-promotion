# Проверка подключения Instagram-бота
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

$cfg    = Get-Content $configPath | ConvertFrom-Json
$token  = $cfg.pageToken
$igId   = $cfg.igUserId
$apiVer = $cfg.apiVersion

Write-Host "Проверяю Instagram аккаунт..." -ForegroundColor Cyan

try {
    $r = Invoke-RestMethod `
        -Uri "https://graph.facebook.com/$apiVer/$igId`?fields=id,username,name,followers_count&access_token=$token"
    Write-Host "OK! Аккаунт: @$($r.username) ($($r.name))" -ForegroundColor Green
    Write-Host "   ID: $($r.id)"
    Write-Host "   Подписчиков: $($r.followers_count)"
} catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
}

# Проверяем очередь
$queueDir   = Join-Path $scriptDir "..\tg-bot\queue"
$queueFiles = Get-ChildItem -Path $queueDir -Filter "*.txt" | Sort-Object Name
$withImage  = $queueFiles | Where-Object {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    (Test-Path (Join-Path $queueDir "$base.png")) -or (Test-Path (Join-Path $queueDir "$base.jpg"))
}

Write-Host ""
Write-Host "Постов в очереди: $($queueFiles.Count)" -ForegroundColor Cyan
Write-Host "Постов с картинкой (для Instagram): $($withImage.Count)" -ForegroundColor Cyan
if ($withImage.Count -gt 0) {
    Write-Host "Следующий пост: $($withImage[0].Name)" -ForegroundColor Yellow
}

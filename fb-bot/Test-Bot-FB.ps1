# Проверка подключения Facebook-бота
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

$cfg    = Get-Content $configPath | ConvertFrom-Json
$token  = $cfg.pageToken
$pageId = $cfg.pageId
$apiVer = $cfg.apiVersion

Write-Host "Проверяю Facebook страницу..." -ForegroundColor Cyan

try {
    $r = Invoke-RestMethod -Uri "https://graph.facebook.com/$apiVer/$pageId`?fields=id,name,fan_count&access_token=$token"
    Write-Host "OK! Страница: $($r.name)" -ForegroundColor Green
    Write-Host "   ID: $($r.id)"
    Write-Host "   Подписчиков: $($r.fan_count)"
} catch {
    Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
}

$queueDir   = Join-Path $scriptDir "..\tg-bot\queue"
$queueFiles = Get-ChildItem -Path $queueDir -Filter "*.txt" -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Постов в очереди: $($queueFiles.Count)" -ForegroundColor Cyan
if ($queueFiles.Count -gt 0) {
    Write-Host "Следующий пост: $($queueFiles | Sort-Object Name | Select-Object -First 1 -ExpandProperty Name)" -ForegroundColor Yellow
}

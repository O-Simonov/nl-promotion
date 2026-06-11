# Test-Bot-VK.ps1 — проверяет подключение к VK API.
# Использование: pwsh -File Test-Bot-VK.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$cfgPath = Join-Path $root 'config.json'
if (-not (Test-Path $cfgPath)) { Write-Host "Нет config.json рядом со скриптом."; exit 1 }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$token   = $cfg.botToken
$groupId = [int]$cfg.groupId
$apiVer  = if ($cfg.apiVersion) { $cfg.apiVersion } else { '5.199' }
if ([string]::IsNullOrWhiteSpace($token) -or $token -match 'ВСТАВЬ') {
    Write-Host "В config.json не вставлен токен сообщества."; exit 1
}

$body = @{
    access_token = $token
    v            = $apiVer
    group_id     = $groupId
    fields       = 'name,screen_name,description,members_count'
}
$uri = 'https://api.vk.com/method/groups.getById'
$bodyStr = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
$resp = Invoke-RestMethod -Uri $uri -Method Post -Body $bodyStr -ContentType 'application/x-www-form-urlencoded'

if ($resp.error) {
    Write-Host "❌ Ошибка: $($resp.error.error_msg) (код $($resp.error.error_code))"
    exit 1
}

# VK API v5.199+ возвращает response.groups[] — поддерживаем оба варианта
$grp = if ($resp.response.groups) { $resp.response.groups[0] } else { $resp.response[0] }
Write-Host "✅ Подключение к ВК работает!"
Write-Host "   Сообщество: $($grp.name)"
Write-Host "   ID:         $($grp.id)"
Write-Host "   Адрес:      https://vk.com/$($grp.screen_name)"
Write-Host "   Участников: $($grp.members_count)"
Write-Host ""
Write-Host "Готово. Можно настраивать расписание (Setup-Schedule-VK.ps1)."

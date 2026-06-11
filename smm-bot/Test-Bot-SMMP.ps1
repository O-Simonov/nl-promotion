# Test-Bot-SMMP.ps1 — проверяет подключение к SMMplanner API.
# Показывает список подключённых аккаунтов соцсетей с их ID.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$cfgPath = Join-Path $root 'config.json'
if (-not (Test-Path $cfgPath)) { Write-Host "Нет config.json рядом со скриптом."; exit 1 }
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$token = $cfg.accessToken
if ([string]::IsNullOrWhiteSpace($token) -or $token -match 'ВСТАВЬ') {
    Write-Host "В config.json не вставлен access_token."; exit 1
}

# Пробуем users/get — простой endpoint, проверяет токен
$uri = 'https://api.smmplanner.com/v1/users/get'
$resp = Invoke-RestMethod -Uri "$uri?key=$token" -Method Get

if ($resp.code -ne 200) {
    Write-Host "❌ Ошибка: $($resp | ConvertTo-Json -Compress)"
    exit 1
}

Write-Host "✅ Токен рабочий!"
Write-Host "   Пользователь: $($resp.name) ($($resp.email))"
Write-Host "   Тариф:        $($resp.tarif)"
Write-Host "   Аккаунтов:    $($resp.accounts_count)"
Write-Host ""
Write-Host "Чтобы узнать ID конкретных аккаунтов (для accountIds), см. файл accounts.json"
Write-Host "Он генерируется скриптом: pwsh -File Get-Accounts-SMMP.ps1"

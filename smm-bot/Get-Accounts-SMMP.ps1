# Get-Accounts-SMMP.ps1 — получает список подключённых аккаунтов соцсетей с их ID.
# Нужен для заполнения accountIds в config.json.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $root 'config.json'
$cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
$token = $cfg.accessToken

$uri = 'https://api.smmplanner.com/v1/accounts/get'
try {
    $resp = Invoke-RestMethod -Uri "$uri?key=$token" -Method Get
    if ($resp.code -ne 200) {
        Write-Host "Ошибка: $($resp | ConvertTo-Json -Compress)"
        exit 1
    }

    Write-Host "Подключённые аккаунты SMMplanner:"
    Write-Host "================================="
    foreach ($acc in $resp.data) {
        Write-Host "  ID: $($acc.id)  →  $($acc.name) [$($acc.type)]"
    }
    Write-Host ""
    Write-Host "Скопируй нужные ID в config.json (accountIds — массив)."
} catch {
    Write-Host "Сбой запроса: $($_.Exception.Message)"
}

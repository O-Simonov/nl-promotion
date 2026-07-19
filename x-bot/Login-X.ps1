# Ручной вход в X — открывает видимый браузер и ждёт, пока ты залогинишься сам.
# После успеха сохраняется session.json — дальше бот (Post-Next-X/Test-Bot-X) ходит сам,
# без повторного логина, и челленджи X появляются редко.
$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$sessionPath = Join-Path $scriptDir "session.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Нет config.json. Скопируй config.example.json → config.json и впиши login/password." -ForegroundColor Red
    exit 1
}
$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) { Write-Host "node не найден в PATH. См. x-bot\README-X.md." -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $scriptDir "node_modules\playwright"))) {
    Write-Host "Playwright не установлен. В x-bot\ выполни: npm install playwright ; npx playwright install chromium" -ForegroundColor Red
    exit 1
}

Write-Host "Открываю браузер для ручного входа в X..." -ForegroundColor Cyan
Write-Host "1) В открывшемся окне залогинься сам (логин/пароль, пройди челлендж/2FA если будут)." -ForegroundColor Yellow
Write-Host "2) Дождись, пока откроется лента X (home). Скрипт сам поймёт, что ты вошёл." -ForegroundColor Yellow
Write-Host "3) Не закрывай окно — оно закроется само. Ждать буду до 5 минут." -ForegroundColor Yellow
Write-Host ""

$env:X_LOGIN        = ''
$env:X_PASSWORD     = ''
$env:X_MANUAL       = '1'
$env:X_TEST         = ''
$env:X_HEADLESS     = 'false'   # окно видно — ручной вход
$env:X_SESSION_PATH = $sessionPath

$out = & $nodeExe (Join-Path $scriptDir "post-x.mjs") 2>&1
$jsonLine = ($out | Where-Object { $_ -match '^\s*\{.*\}\s*$' } | Select-Object -Last 1)

if (-not $jsonLine) {
    Write-Host "Нет JSON-ответа от воркера. Вывод:" -ForegroundColor Red
    Write-Host ($out | Out-String) -ForegroundColor DarkGray
    exit 1
}
$r = $jsonLine | ConvertFrom-Json
if ($r.ok) {
    Write-Host "OK! Сессия сохранена в $sessionPath" -ForegroundColor Green
    Write-Host "Теперь можно: pwsh -File x-bot\Test-Bot-X.ps1  (проверит вход по сессии), затем Setup-Schedule-X.ps1" -ForegroundColor Green
} else {
    Write-Host "ОШИБКА: $($r.error)" -ForegroundColor Red
    exit 1
}
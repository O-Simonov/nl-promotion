# Проверка подключения X-бота (браузерный вход + авторизация, без публикации)
$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Нет config.json. Скопируй config.example.json → config.json и впиши login/password." -ForegroundColor Red
    exit 1
}

$cfg      = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$login    = $cfg.login
$sessionPath = Join-Path $scriptDir "session.json"

$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeExe) { Write-Host "node не найден в PATH. См. x-bot\README-X.md." -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $scriptDir "node_modules\playwright"))) {
    Write-Host "Playwright не установлен. В x-bot\ выполни: npm install playwright ; npx playwright install chromium" -ForegroundColor Red
    exit 1
}

Write-Host "Проверяю вход в X (логин: $login; сессия: $(if (Test-Path $sessionPath) {'есть'} else {'нет — зайдёт впервые'}))..." -ForegroundColor Cyan
Write-Host "(Это откроет браузер. Первый раз — медленно; headless=false см. в config.json)" -ForegroundColor DarkGray
Write-Host ""

$env:X_LOGIN        = $login
$env:X_PASSWORD     = $cfg.password
$env:X_TEST         = '1'
$env:X_HEADLESS     = if ([bool]$cfg.headless) { 'true' } else { 'false' }
$env:X_SESSION_PATH = $sessionPath

$out = & $nodeExe (Join-Path $scriptDir "post-x.mjs") 2>&1
$code = $LASTEXITCODE
$jsonLine = ($out | Where-Object { $_ -match '^\s*\{.*\}\s*$' } | Select-Object -Last 1)

if (-not $jsonLine) {
    Write-Host "Нет JSON-ответа от воркера. Вывод:" -ForegroundColor Red
    Write-Host ($out | Out-String) -ForegroundColor DarkGray
    exit 1
}

$r = $jsonLine | ConvertFrom-Json
if ($r.ok) {
    Write-Host "OK! X-бот авторизован." -ForegroundColor Green
    Write-Host "   Учётка: $($r.user)"
} else {
    Write-Host "ОШИБКА: $($r.error)" -ForegroundColor Red
    if ($r.needManual) {
        Write-Host "⛔ X требует ручного входа (челлендж/2FA)." -ForegroundColor Yellow
        Write-Host "   Запусти один раз: pwsh -File x-bot\Test-Bot-X.ps1 с headless=false (или руками открой x.com и войди)," -ForegroundColor Yellow
        Write-Host "   пройди проверку — session.json сохранится, дальше бот будет ходить сам." -ForegroundColor Yellow
    }
    $shot = Join-Path $scriptDir "logs\x-error.png"
    if (Test-Path $shot) { Write-Host "   Скриншот ошибки: $shot" -ForegroundColor DarkGray }
    exit 1
}

$queueDir = Join-Path $scriptDir "..\tg-bot\queue"
$queueFiles = Get-ChildItem -Path $queueDir -Filter "*.txt" -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Постов в очереди: $($queueFiles.Count)" -ForegroundColor Cyan
if ($queueFiles.Count -gt 0) {
    Write-Host "Следующий пост: $($queueFiles | Sort-Object Name | Select-Object -First 1 -ExpandProperty Name)" -ForegroundColor Yellow
}
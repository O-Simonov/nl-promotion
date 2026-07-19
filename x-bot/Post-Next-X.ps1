# X (Twitter) автопостинг — следующий пост из очереди (через Playwright)
$ErrorActionPreference = "Stop"

# TLS 1.2/1.3 (на всякий случай; Playwright сам ходит по сети, но .NET-хозяйство берём под контроль)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$queueDir   = Join-Path $scriptDir "..\tg-bot\queue"
$sentDir    = Join-Path $scriptDir "sent"
$logFile    = Join-Path $scriptDir "logs\x-bot.log"
$sessionPath = Join-Path $scriptDir "session.json"

New-Item -ItemType Directory -Force -Path $sentDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir "logs") | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
Write-Log "=== СТАРТ Post-Next-X.ps1 (pid=$PID, user=$env:USERNAME) ==="
Write-Log "PowerShell = $($PSVersionTable.PSVersion), OS = $([System.Environment]::OSVersion.VersionString)"

# --- Обрезка подписи до 280 символов (лимит X) с сохранением реф-ссылки NL ---
function ConvertTo-TweetText {
    param([string]$Caption)
    $MAX = 280
    if ($Caption.Length -le $MAX) { return $Caption }

    # Реф-ссылка NL (nlstar.com) — приоритет; иначе последний URL.
    $m = [regex]::Matches($Caption, 'https?://nlstar\.com/[^\s]+')
    if ($m.Count -eq 0) { $m = [regex]::Matches($Caption, 'https?://[^\s]+') }
    $refUrl = if ($m.Count -gt 0) { ($m[$m.Count - 1].Value).TrimEnd('.', '…', ',', ')') } else { $null }

    # Тело = строки без URL и без чисто-хэштеговых строк.
    $lines = $Caption -split "`r?`n"
    $bodyLines = $lines | Where-Object { $_ -notmatch 'https?://' -and $_ -notmatch '^\s*#' }
    $body = (($bodyLines -join ' ') -replace '\s{2,}', ' ').Trim()

    if ($refUrl) {
        $budget = $MAX - $refUrl.Length - 3   # " … " = 3 символа
        if ($budget -lt 20) { $budget = 20 }
        if ($body.Length -gt $budget) { $body = $body.Substring(0, $budget).TrimEnd() }
        $tweet = "$body … $refUrl"
    } else {
        if ($body.Length -gt 277) { $body = $body.Substring(0, 277).TrimEnd() }
        $tweet = "$body…"
    }
    if ($tweet.Length -gt $MAX) { $tweet = $tweet.Substring(0, $MAX) }
    return $tweet
}

# --- Запуск Playwright-воркера. Возвращает @{ ok; error; needManual } ---
function Invoke-Worker {
    param([string]$TweetText, [string]$ImagePath)
    $env:X_LOGIN        = $login
    $env:X_PASSWORD     = $password
    $env:X_TEXT         = $TweetText
    $env:X_IMAGE        = $ImagePath
    $env:X_HEADLESS     = if ([bool]$cfg.headless) { 'true' } else { 'false' }
    $env:X_SESSION_PATH = $sessionPath
    # Воркер читает только X_* — старые LOGIN/PASSWORD/TEXT/IMAGE намеренно не ставим,
    # чтобы случайно не подхватить чужие env (например, от FB-бота).

    $out = & $nodeExe $worker 2>&1
    $code = $LASTEXITCODE
    # Воркер печатает ровно одну JSON-строку в конце; Playwright может сыпать предупреждения в stderr.
    $jsonLine = ($out | Where-Object { $_ -match '^\s*\{.*\}\s*$' } | Select-Object -Last 1)
    if ($jsonLine) {
        try {
            $r = $jsonLine | ConvertFrom-Json
            return @{ ok = [bool]$r.ok; error = [string]$r.error; needManual = [bool]$r.needManual }
        } catch {
            return @{ ok = ($code -eq 0); error = "не распарсил ответ воркера: $jsonLine"; needManual = $false }
        }
    }
    return @{ ok = ($code -eq 0); error = ($out | Out-String); needManual = $false }
}

# --- Конфиг ---
$cfg      = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$login    = $cfg.login
$password = $cfg.password

$nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
$worker  = Join-Path $scriptDir "post-x.mjs"
$pwMod   = Join-Path $scriptDir "node_modules\playwright"

# --- smoke-test: наличие node + воркера + Playwright. Дёшево, без запуска браузера. ---
if (-not $nodeExe) {
    Write-Log "❌ node не найден в PATH. Установи Node.js (winget install OpenJS.NodeJS) и см. x-bot\README-X.md."
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
    exit 1
}
if (-not (Test-Path $worker)) { Write-Log "❌ Не найден воркер $worker"; exit 1 }
if (-not (Test-Path $pwMod)) {
    Write-Log "❌ Playwright не установлен: выполни в x-bot\ `npm install playwright` и `npx playwright install chromium` (см. x-bot\README-X.md)."
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с ==="
    exit 1
}

# Берём первый пост из очереди
$post = Get-ChildItem -Path $queueDir -Filter "*.txt" -File | Sort-Object Name | Select-Object -First 1
if (-not $post) {
    Write-Log "Очередь пуста — нечего публиковать."
    exit 0
}

$captionRaw = Get-Content $post.FullName -Raw -Encoding UTF8
$base    = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
$pngPath = Join-Path $queueDir "$base.png"
$jpgPath = Join-Path $queueDir "$base.jpg"
$imgFile = if (Test-Path $pngPath) { $pngPath } elseif (Test-Path $jpgPath) { $jpgPath } else { $null }

$tweetText = ConvertTo-TweetText -Caption $captionRaw
Write-Log "Публикую: $($post.Name)$(if ($imgFile) {' + ' + (Split-Path -Leaf $imgFile)} else {' (без картинки)'})"
if ($tweetText.Length -ne $captionRaw.Length) {
    Write-Log "Подпись обрезана с $($captionRaw.Length) до $($tweetText.Length) симв. (лимит X — 280; реф-ссылка сохранена)"
}

# --- параметры повтора при сбое ---
$maxAttempts   = 4
$retryDelaySec  = 30

function Invoke-Publish {
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        if ($swTotal.Elapsed.TotalSeconds -gt 240) { throw "Глобальный таймаут 240с — прерываю" }
        try {
            Write-Log "→ node post-x.mjs (попытка $attempt/$maxAttempts)"
            $r = Invoke-Worker -TweetText $tweetText -ImagePath $(if ($imgFile) { $imgFile } else { '' })
            if ($r.ok) {
                if ($attempt -gt 1) { Write-Log "Успех со $attempt-й попытки." }
                return $true
            }
            # Челлендж/2FA не пройдут повтором — не тратим попытки.
            if ($r.needManual) {
                Write-Log "⛔ Нужен ручный вход (челлендж/2FA) — повторы не помогут: $($r.error)"
                throw ("ТРЕБУЕТСЯ РУЧНОЙ ВХОД: " + $r.error)
            }
            throw $r.error
        }
        catch {
            if ($attempt -lt $maxAttempts) {
                Write-Log "Попытка $attempt/$maxAttempts не удалась: $($_.Exception.Message). Повтор через $retryDelaySec c..."
                Start-Sleep -Seconds $retryDelaySec
            } else { throw }
        }
    }
}

try {
    $null = Invoke-Publish
    Write-Log "УСПЕХ! Твит опубликован: $($post.Name)"

    Move-Item -Path $post.FullName -Destination (Join-Path $sentDir $post.Name)
    if ($imgFile) { Move-Item -Path $imgFile -Destination (Join-Path $sentDir (Split-Path -Leaf $imgFile)) }
    Write-Log "Файлы перемещены в sent/"
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (ОК) ==="

    # Сброс счётчика ошибок при успехе
    $errCounter = Join-Path $scriptDir "logs\x-error-count.txt"
    if (Test-Path $errCounter) { Remove-Item $errCounter -Force }
}
catch {
    $errMsg = $_.Exception.Message
    Write-Log "СБОЙ после $maxAttempts попыток: $errMsg"
    Write-Log "=== СТОП $([int]$swTotal.Elapsed.TotalSeconds)с (FAIL) ==="

    $errCounter = Join-Path $scriptDir "logs\x-error-count.txt"
    $count = 0
    if (Test-Path $errCounter) { [int]$count = (Get-Content $errCounter -Raw).Trim() }
    $count++
    Set-Content -Path $errCounter -Value $count

    if ($count -ge 3) {
        try {
            $notifyScript = Join-Path $PSScriptRoot "..\Notify-Owner.ps1"
            if (Test-Path $notifyScript) {
                & pwsh -NoProfile -ExecutionPolicy Bypass -File $notifyScript `
                    -Message "⚠️ <b>X-бот</b> упал <b>$count раз подряд</b>.%0A%0AПоследняя ошибка:%0A<code>$([System.Web.HttpUtility]::HtmlEncode($errMsg))</code>%0A%0AВозможно, слетела сессия или X просит челлендж/2FA. Зайди в x-bot и запусти Test-Bot-X вручную, чтобы пройти вход, потом скажи мне — я разгребу очередь."
                Write-Log "🚨 Уведомление отправлено (ошибка #$count)"
            }
        } catch { Write-Log "⚠️ Не удалось отправить уведомление: $($_.Exception.Message)" }
    }
    exit 1
}
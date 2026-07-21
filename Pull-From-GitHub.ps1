# Pull-From-GitHub.ps1 — подтягивает main с GitHub перед постингом.
# Зачем: правки с телефона (новые посты в backlog/queue) появляются на ПК
# до NL-Queue-Refill (09:00) и NL-Telegram-AutoPost (10:00).
#
# Ручной запуск:  pwsh -File C:\NL_produkt\Pull-From-GitHub.ps1
# Расписание:     pwsh -File C:\NL_produkt\Setup-Schedule-Pull.ps1

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir  = Join-Path $root 'logs'
$logFile = Join-Path $logDir 'git-pull.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Set-Location $root

Write-Log '=== git pull start ==='

try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>&1).ToString().Trim()
    if ($branch -ne 'main') {
        Write-Log "WARN: текущая ветка '$branch', переключаюсь на main"
        git checkout main 2>&1 | ForEach-Object { Write-Log $_ }
    }

    # Локальные правки (часто: боты уже удалили опубликованный пост из queue)
    # временно убираем в stash, чтобы ff-only pull не падал.
    $dirty = git status --porcelain 2>&1
    $stashed = $false
    if ($dirty) {
        Write-Log 'Working tree dirty — git stash (включая untracked)'
        git stash push -u -m "auto-pull $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>&1 |
            ForEach-Object { Write-Log $_ }
        $stashed = $true
    }

    Write-Log 'git fetch origin'
    git fetch origin 2>&1 | ForEach-Object { Write-Log $_ }

    $local  = (git rev-parse HEAD).Trim()
    $remote = (git rev-parse origin/main).Trim()
    $behind = [int](git rev-list --count "HEAD..origin/main").Trim()
    $ahead  = [int](git rev-list --count "origin/main..HEAD").Trim()
    Write-Log "local=$($local.Substring(0,7)) remote=$($remote.Substring(0,7)) behind=$behind ahead=$ahead"

    if ($behind -eq 0) {
        Write-Log "Уже актуально (нет коммитов на GitHub, которых нет локально)"
        if ($ahead -gt 0) {
            Write-Log "INFO: локально на $ahead коммит(ов) впереди origin/main — нужен git push, pull ничего не берёт"
        }
    } else {
        Write-Log "Отстаём на $behind коммит(ов) — pull --ff-only"
        git pull --ff-only origin main 2>&1 | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only failed (exit $LASTEXITCODE). Нужен ручной разбор конфликтов."
        }
        $after = (git rev-parse HEAD).Trim()
        Write-Log "OK: обновлено до $($after.Substring(0,7))"
        git log --oneline "$local..$after" 2>&1 | ForEach-Object { Write-Log "  + $_" }
    }

    if ($stashed) {
        Write-Log 'Восстанавливаю stash'
        $pop = git stash pop 2>&1
        $pop | ForEach-Object { Write-Log $_ }
        # Конфликт stash не критичен для постинга — логируем и идём дальше
        if ($LASTEXITCODE -ne 0) {
            Write-Log "WARN: stash pop завершился с кодом $LASTEXITCODE (смотрите git status)"
        }
    }

    Write-Log '=== git pull done ==='
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log '=== git pull FAILED ==='
    exit 1
}

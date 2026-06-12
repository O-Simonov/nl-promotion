# Check-Queue-Refill.ps1 — проверяет очередь и пополняет из бэклога когда постов <= 6
$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$queueDir   = Join-Path $root 'queue'
$backlogDir = Join-Path $root 'backlog'
$logFile    = Join-Path $root 'logs\refill.log'

New-Item -ItemType Directory -Force -Path (Join-Path $root 'logs') | Out-Null

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

# Считаем посты в очереди
$queueCount = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File).Count
Write-Log "Постов в очереди: $queueCount"

# Порог: 8 постов = ~2 дня (4 бота × 2 дня = 8)
if ($queueCount -gt 8) {
    Write-Log "Очередь достаточная — пополнение не нужно."
    exit 0
}

Write-Log "ВНИМАНИЕ: постов мало! Пополняю из бэклога..."

# Берём следующие 10 постов из бэклога (по имени)
$backlogPosts = Get-ChildItem -Path $backlogDir -Filter '*.txt' -File | Sort-Object Name | Select-Object -First 10

if ($backlogPosts.Count -eq 0) {
    Write-Log "БЭКЛОГ ПУСТ! Новые посты нужно добавить вручную."
    exit 0
}

$moved = 0
foreach ($post in $backlogPosts) {
    $base   = [System.IO.Path]::GetFileNameWithoutExtension($post.Name)
    $txtSrc = $post.FullName
    $pngSrc = Join-Path $backlogDir "$base.png"
    $txtDst = Join-Path $queueDir $post.Name
    $pngDst = Join-Path $queueDir "$base.png"

    # Перемещаем txt
    Move-Item -Path $txtSrc -Destination $txtDst
    Write-Log "Перемещён: $($post.Name)"

    # Перемещаем png если есть
    if (Test-Path $pngSrc) {
        Move-Item -Path $pngSrc -Destination $pngDst
        Write-Log "Перемещён: $base.png"
    }

    $moved++
}

$newCount = (Get-ChildItem -Path $queueDir -Filter '*.txt' -File).Count
Write-Log "Готово! Перемещено постов: $moved. Теперь в очереди: $newCount."

$backlogLeft = (Get-ChildItem -Path $backlogDir -Filter '*.txt' -File).Count
if ($backlogLeft -le 10) {
    Write-Log "ПРЕДУПРЕЖДЕНИЕ: в бэклоге осталось мало постов ($backlogLeft). Пора писать новые!"
}

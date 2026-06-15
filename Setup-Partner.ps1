# Setup-Partner.ps1 — персонализация проекта NL AutoPost под нового партнёра.
# Заменяет реф-ссылки, имя, адрес сайта и соцсети Олега на ТВОИ — во всех постах,
# на сайте и в футере картинок. Запусти ОДИН раз в свежесклонированном репозитории:
#   pwsh -File Setup-Partner.ps1
# Откатить всё, если что-то пошло не так:  git checkout .
# Требуется PowerShell 7+.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Ask($prompt, $example) {
    Write-Host ""
    Write-Host $prompt -ForegroundColor Cyan
    if ($example) { Write-Host "   пример: $example" -ForegroundColor DarkGray }
    Write-Host "   (Enter — пропустить это поле)" -ForegroundColor DarkGray
    return (Read-Host "   твоё значение").Trim()
}

Write-Host "=== Персонализация NL AutoPost под тебя ===" -ForegroundColor Green
Write-Host "Отвечай на вопросы. Пустой ответ (Enter) — оставить как есть."

# --- Сбор значений ---
$name = Ask "Твоё имя (как подписывать посты и сайт):" "Иван Петров"

$prodRaw  = Ask "Продуктовая реф-ссылка (магазин nlstar):" "https://nlstar.com/ref/ABC123/"
$prodCode = if ($prodRaw -match '/ref/([^/?#]+)') { $Matches[1] } else { $prodRaw }

$bizRaw  = Ask "Бизнес реф-ссылка (nlstore):" "https://nlstore.com/ref/XYZ789/"
$bizCode = if ($bizRaw -match '/ref/([^/?#]+)') { $Matches[1] } else { $bizRaw }

$hubRaw = Ask "Твой сайт-хаб на Netlify (хост):" "ivan-nl.netlify.app"
$hub    = ($hubRaw -replace '^https?://', '' -replace '/.*$', '').Trim()

$tgRaw = Ask "Твой Telegram-юзернейм (без @):" "ivan_nl"
$tg    = ($tgRaw -replace '^@', '' -replace '^.*t\.me/', '').Trim()

$igRaw = Ask "Твой Instagram-юзернейм:" "ivan.nl"
$ig    = ($igRaw -replace '^@', '' -replace '^.*instagram\.com/', '' -replace '/.*$', '').Trim()

$vkRaw = Ask "Твоё VK-сообщество (часть после vk.com/):" "club123456789"
$vk    = ($vkRaw -replace '^.*vk\.com/', '' -replace '/.*$', '').Trim()

$fbRaw = Ask "ID твоей Facebook-страницы:" "1234567890"
$fb    = ($fbRaw -replace '\D', '').Trim()

# --- Пары замен (старое -> новое), только заполненные поля ---
$pairs = @()
if ($name)     { $pairs += , @('Олег Симонов', $name) }
if ($prodCode) { $pairs += , @('WEWxBD', $prodCode) }
if ($bizCode)  { $pairs += , @('rhhBvA', $bizCode) }
if ($hub)      { $pairs += , @('oleg-nl.netlify.app', $hub) }
if ($tg)       { $pairs += , @('Simka1969_nl', $tg) }
if ($ig)       { $pairs += , @('simonov3480', $ig) }
if ($vk)       { $pairs += , @('club239517960', $vk) }
if ($fb)       { $pairs += , @('1167094323156986', $fb) }

if ($pairs.Count -eq 0) { Write-Host "`nНичего не введено — выходим." -ForegroundColor Yellow; exit 0 }

# --- Какие файлы трогаем: посты + сайт + контент-доки + футер картинок ---
# НЕ трогаем: config.json (токены), sent/, logs/, SETUP.md/PARTNER.md (инструкции), .claude/, .git/
$targets = @()
$targets += Get-ChildItem -Path (Join-Path $root 'tg-bot\queue')   -Filter *.txt  -File -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path (Join-Path $root 'tg-bot\backlog') -Filter *.txt  -File -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path (Join-Path $root 'anons')          -Filter *.txt  -File -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path $root                              -Filter *.html -File -ErrorAction SilentlyContinue
$targets += Get-ChildItem -Path (Join-Path $root 'anons')          -Filter *.html -File -ErrorAction SilentlyContinue
foreach ($md in 'README.md', 'БАЗА-ЗНАНИЙ-NL.md', 'КОНТЕНТ-ПЛАН-NL.md') {
    $p = Join-Path $root $md
    if (Test-Path $p) { $targets += Get-Item $p }
}
$mk = Join-Path $root 'tg-bot\Make-PostImage.ps1'
if (Test-Path $mk) { $targets += Get-Item $mk }
$targets = $targets | Sort-Object FullName -Unique

# --- Применяем замены ---
Write-Host "`n=== Меняю в $($targets.Count) файлах ===" -ForegroundColor Green
$counts = @{}
foreach ($f in $targets) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if ($null -eq $text) { continue }
    $orig = $text
    foreach ($pair in $pairs) {
        if ($text.Contains($pair[0])) {
            $text = $text.Replace($pair[0], $pair[1])
            $counts[$pair[0]] = [int]$counts[$pair[0]] + 1
        }
    }
    if ($text -ne $orig) { Set-Content -LiteralPath $f.FullName -Value $text -Encoding UTF8 -NoNewline }
}

# --- Итог ---
Write-Host "`n=== Заменено ===" -ForegroundColor Green
foreach ($pair in $pairs) {
    $c = [int]$counts[$pair[0]]
    Write-Host ("  {0,-20} -> {1,-26} : {2} файлов" -f $pair[0], $pair[1], $c)
}

Write-Host "`n=== Осталось сделать руками ===" -ForegroundColor Yellow
Write-Host "1. Замени фото  foto.jpg  в корне на своё (имя файла оставь тем же)."
Write-Host "2. Заполни config.json в каждой папке *-bot своими токенами (см. SETUP.md)."
Write-Host "3. Проверь правки:  git diff     (откатить всё:  git checkout .)"
Write-Host "4. Залей на свой GitHub и подключи к Netlify — сайт обновится сам."
Write-Host "5. Официальный канал NL (t.me/nl25_news) НЕ трогаем — он общий для всех."
Write-Host "6. Пробегись по постам глазами на случай других личных упоминаний." -ForegroundColor DarkGray

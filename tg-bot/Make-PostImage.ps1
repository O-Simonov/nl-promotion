# Make-PostImage.ps1 — генерирует PNG-картинку для поста в Telegram.
# Использование:
#   pwsh -File Make-PostImage.ps1 -Title "Energy Diet" -Subtitle "Топ-3 вкуса" -Category product -Out "queue\18-vkusy-top.png"
# Категории: product (зелёный), business (синий), review (оранжевый), offer (красный), news (тёмно-зелёный).

param(
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $false)][string]$Subtitle = "",
    [ValidateSet("product", "business", "review", "offer", "news")]
    [string]$Category = "product",
    [Parameter(Mandatory = $true)][string]$Out
)

Add-Type -AssemblyName System.Drawing

$W = 1080
$H = 1080

$palettes = @{
    product  = @{ bg1 = "#0f766e"; bg2 = "#15a08c"; accent = "#16a34a"; emoji = "🥤" }
    business = @{ bg1 = "#1e3a8a"; bg2 = "#3b82f6"; accent = "#60a5fa"; emoji = "🚀" }
    review   = @{ bg1 = "#c2410c"; bg2 = "#f97316"; accent = "#fdba74"; emoji = "💬" }
    offer    = @{ bg1 = "#9f1239"; bg2 = "#e11d48"; accent = "#fda4af"; emoji = "📢" }
    news     = @{ bg1 = "#0b3d3a"; bg2 = "#0f766e"; accent = "#5eead4"; emoji = "🆕" }
}
$p = $palettes[$Category]

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

# Фон — линейный градиент
$rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.ColorTranslator]::FromHtml($p.bg1),
    [System.Drawing.ColorTranslator]::FromHtml($p.bg2),
    135.0
)
$g.FillRectangle($brush, $rect)
$brush.Dispose()

# Декоративные круги
$circleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 255, 255, 255))
$g.FillEllipse($circleBrush, -150, -150, 400, 400)
$g.FillEllipse($circleBrush, $W - 250, $H - 250, 400, 400)
$circleBrush.Dispose()

# Хелпер для шрифтов
function New-Font([string]$name, [float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font($name, $size, $style)
}

# Эмодзи
$emojiFont = New-Font "Segoe UI Emoji" 160
$emojiBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 255, 255, 255))
$emojiSize = $g.MeasureString($p.emoji, $emojiFont)
$g.DrawString($p.emoji, $emojiFont, $emojiBrush, (($W - $emojiSize.Width) / 2), 120)
$emojiBrush.Dispose(); $emojiFont.Dispose()

# Заголовок
$titleFont = New-Font "Segoe UI" 84 ([System.Drawing.FontStyle]::Bold)
$titleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$titleRect = New-Object System.Drawing.RectangleF 60, 380, ($W - 120), 280
$titleFormat = New-Object System.Drawing.StringFormat
$titleFormat.Alignment = [System.Drawing.StringAlignment]::Center
$titleFormat.LineAlignment = [System.Drawing.StringAlignment]::Near
$titleFormat.Trimming = [System.Drawing.StringTrimming]::Word
$g.DrawString($Title, $titleFont, $titleBrush, $titleRect, $titleFormat)
$titleBrush.Dispose(); $titleFont.Dispose()

# Подзаголовок
if ($Subtitle) {
    $subFont = New-Font "Segoe UI" 40
    $subBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(220, 240, 253, 250))
    $subRect = New-Object System.Drawing.RectangleF 80, 700, ($W - 160), 180
    $subFormat = New-Object System.Drawing.StringFormat
    $subFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $subFormat.LineAlignment = [System.Drawing.StringAlignment]::Near
    $subFormat.Trimming = [System.Drawing.StringTrimming]::Word
    $g.DrawString($Subtitle, $subFont, $subBrush, $subRect, $subFormat)
    $subBrush.Dispose(); $subFont.Dispose()
}

# Логотип NL (правый верх)
$logoFont = New-Font "Segoe UI" 36 ([System.Drawing.FontStyle]::Bold)
$logoBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 255, 255, 255))
$logoText = "NL"
$logoSize = $g.MeasureString($logoText, $logoFont)
$logoBgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 255, 255, 255))
$g.FillEllipse($logoBgBrush, ($W - $logoSize.Width - 30), 30, ($logoSize.Width + 20), ($logoSize.Height + 20))
$g.DrawString($logoText, $logoFont, $logoBrush, ($W - $logoSize.Width - 20), 40)
$logoBgBrush.Dispose(); $logoBrush.Dispose(); $logoFont.Dispose()

# Подпись внизу
$footerFont = New-Font "Segoe UI" 24
$footerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 255, 255, 255))
$footerText = "Олег Симонов · @Simka1969_nl · https://oleg-nl.netlify.app/"
$footerSize = $g.MeasureString($footerText, $footerFont)
$g.DrawString($footerText, $footerFont, $footerBrush, (($W - $footerSize.Width) / 2), ($H - 70))
$footerBrush.Dispose(); $footerFont.Dispose()

$g.Dispose()

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "✅ Создано: $Out"

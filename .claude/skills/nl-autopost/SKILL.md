---
name: nl-autopost
description: Скилл-методичка «как собрать систему автопостинга в 4 соцсети для дистрибьютора NL International с нуля». Содержит пошаговый план, шаблоны скриптов, настройки Windows Task Scheduler, чек-листы безопасности и правила оформления постов. Применяй, когда пользователь хочет поднять свою копию проекта, доработать существующую систему, добавить новую соцсеть или у него упал постинг.
version: 1.0.0
---

# NL AutoPost — методичка сборки с нуля

Полный рецепт: как дистрибьютор NL International (или любой партнёр с похожей задачей) поднимает систему автопостинга в 4 соцсети на PowerShell + Windows Task Scheduler.

## Когда применять

- Партнёр NL хочет свою копию автопостинга (клонировал репо → поднял бота за вечер)
- Сломалось расписание или упал постинг — нужна пошаговая диагностика
- Добавляем 5-ю соцсеть (YouTube Shorts, TikTok, MAX)
- Готовим нового партнёра: даём ему методичку, чтобы не задавал 50 вопросов

## Что должно получиться на выходе

Работающая система, которая **каждый день без ручного участия** публикует:
- 09:00 — автопополнение очереди (если постов ≤ 8)
- 10:00 — пост в Telegram
- 11:00 — пост в Facebook
- 12:00 — пост в Instagram
- 14:00 — пост в ВКонтакте
- 08:30 + 20:00 — сбор свежих новостей NL в `digest.md`

## Предусловия (что должно быть на машине)

| Компонент | Зачем | Как поставить |
|---|---|---|
| Windows 10/11 | Task Scheduler | уже есть |
| PowerShell 7+ (`pwsh`) | скрипты, API, JSON | `winget install Microsoft.PowerShell` |
| Git | клонировать репо | `winget install Git.Git` |
| Аккаунты в 4 соцсетях | точки публикации | руками |
| Токены API | доступ к публикации | см. таблицу ниже |

### Где взять токены

| Соцсеть | Где | Срок жизни | Что нужно для продления |
|---|---|---|---|
| Telegram | @BotFather → /newbot | бессрочно | ничего |
| ВКонтакте | vk.com/dev → ключи сообщества | бессрочно, но нужно standalone-приложение | пересоздать |
| Facebook + Instagram | developers.facebook.com → Graph API → System User | 60 дней (временный) или ∞ (постоянный) | **обязательно** настроить напоминание за 7 дней |
| ImgBB | api.imgbb.com | бессрочно | бесплатный, безлимит |

**⚠️ Никогда не коммитить токены в Git.** Использовать `config.json` (он в `.gitignore`) или переменные окружения.

## Структура проекта (золотой стандарт)

```
NL_produkt/
├── tg-bot/         # Telegram-бот (10:00)
├── vk-bot/         # ВКонтакте-бот (14:00)
├── fb-bot/         # Facebook-бот (11:00)
├── ig-bot/         # Instagram-бот (12:00)
├── news-watch/     # сборщик новостей (08:30 + 20:00)
├── Check-Queue-Refill.ps1       # автопополнение очереди (09:00)
├── Check-All-Bots.ps1           # статус всех ботов одной командой
├── index.html, biznes.html, prezentaciya.html, kak-zakazat.html  # сайт-хаб
├── netlify.toml     # publish = ".", команда сборки пустая
├── БАЗА-ЗНАНИЙ-NL.md           # справочник по продуктам
├── КОНТЕНТ-ПЛАН-NL.md           # темы постов по рубрикам
├── PROJECT.md                   # описание проекта (структура: проблема, пользователь, MVP, технологии)
├── prezentaciya-proekta/        # презентация о самом проекте
├── README.md                    # инструкция
├── PARTNER.md                   # быстрый старт для партнёра
├── SETUP.md                     # полная установка с нуля
└── Setup-Partner.ps1            # мастер подстановки своих реф-ссылок и соцсетей
```

## Шаблоны скриптов (минимальный бот)

Каждый бот = **3 файла + 1 конфиг**:

### 1. `Post-Next-<NETWORK>.ps1` — публикация следующего поста

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json

$queueDir = Join-Path $root 'queue'
$sentDir  = Join-Path $root 'sent'
$logFile  = Join-Path $root 'logs\post.log'
New-Item -ItemType Directory -Force -Path $sentDir, (Split-Path $logFile) | Out-Null
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" |
                     Tee-Object -FilePath $logFile -Append }

# Берём самый ранний пост по имени файла (01-foo.txt, 02-bar.txt, …)
$post = Get-ChildItem $queueDir -Filter '*.txt' -File | Sort-Object Name | Select -First 1
if (-not $post) { Log "Очередь пуста."; exit 0 }
$text = Get-Content $post.FullName -Raw -Encoding UTF8
$base = [IO.Path]::GetFileNameWithoutExtension($post.Name)
$img  = Get-ChildItem $queueDir -File | Where-Object { $_.BaseName -eq $base -and $_.Extension -match '\.(jpg|jpeg|png)$' } | Select -First 1

# === API-вызов (псевдокод — реальный код уникален для каждой сети) ===
# для TG: Invoke-RestMethod -Uri "https://api.telegram.org/bot$($cfg.botToken)/sendPhoto" -Method Post -Form @{chat_id=$cfg.channelId; photo=Get-Item $img.FullName; caption=$text}
# для VK: POST https://api.vk.com/method/wall.post с photos.upload + wall.post
# для FB: POST https://graph.facebook.com/v18.0/{page-id}/photos с url=imgbb-url
# для IG: два шага: POST /media (создать контейнер) → POST /media_publish

# При успехе:
Log "OK: опубликован '$($post.Name)'. В очереди осталось: $((Get-ChildItem $queueDir -Filter '*.txt').Count - 1)."
Move-Item $post.FullName $sentDir
if ($img) { Move-Item $img.FullName $sentDir }

# При ошибке (показать 4 попытки с паузой 30 сек):
for ($i=1; $i -le 4; $i++) {
    try { /* API call */ ; break }
    catch { Log "Попытка $i/4 не удалась: $($_.Exception.Message)"; if ($i -lt 4) { Start-Sleep 30 } }
}
```

### 2. `Setup-Schedule-<NETWORK>.ps1` — создать задачу

```powershell
param([string]$Time = "10:00")
$script = Join-Path $PSScriptRoot 'Post-Next-TG.ps1'
$action  = New-ScheduledTaskAction -Execute 'pwsh' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "NL-Telegram-AutoPost" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
```

### 3. `Test-Bot-<NETWORK>.ps1` — проверить доступ

Делает `getMe` / `groups.getById` / `me/accounts` — что-то дешёвое, чтобы убедиться, что токен валиден.

### 4. `config.example.json` — шаблон

```json
{
  "botToken": "ВСТАВЬ_СВОЙ_ТОКЕН",
  "channelId": "@my_nl_channel"
}
```

> В `config.json` (боевой) лежит реальный токен. Он в `.gitignore`.

## Правила оформления постов

| Правило | Зачем |
|---|---|
| Имя файла `NN-slug.txt` + `NN-slug.png` | очередь сортируется по имени, картинка привязывается к посту |
| Текст ≤ 800 символов | влезает во все 4 соцсети без обрезки |
| Первая строка — заголовок-крючок | это видно в ленте |
| Реф-ссылка NL в конце | иначе забыл — потерял продажу |
| Хэштеги: 3–5 штук | больше — выглядит как спам |
| Картинка 1080×1080 или 1080×1350 | универсально для всех 4 сетей |

## Чек-лист безопасности (для партнёра)

Перед `git push` убедись:

- [ ] `config.json` в `.gitignore` (токены не утекут)
- [ ] `git status` не показывает файлы с токенами
- [ ] `Setup-Partner.ps1` подставляет только публичные реф-ссылки (не пароль)
- [ ] Если партнёр прислал пароль — **не сохранять, попросить сменить**

## Диагностика: что делать, если постинг упал

| Симптом | Где смотреть | Что делать |
|---|---|---|
| LastResult=1 в планировщике | `*/logs/post.log` | прочитать последние 10 строк |
| 400 Bad Request (FB/IG) | Meta Graph API | перевыпустить токен, обновить `config.json` |
| 401 Unauthorized | `config.json` | токен протух, пересоздать |
| 27 Group authorization failed (VK) | `vk-bot/logs` | нужен standalone-токен сообщества, не пользовательский |
| Этот хост неизвестен (TG) | сеть/DNS | проверить интернет, иногда помогает VPN |
| Очередь пуста | `*/queue/` | `Check-Queue-Refill` сам пополнит в 09:00; можно вручную перетащить из `backlog/` |
| Картинка не прикрепляется | `*.png` битый? | перегенерить через `Make-PostImage.ps1` |

## Расширение: добавить новую соцсеть

1. Создать папку `<net>-bot/`
2. Скопировать туда 3 скрипта + `config.example.json` из существующего бота
3. Переписать в `Post-Next-<NETWORK>.ps1` блок API-вызова
4. Написать `Test-Bot-<NETWORK>.ps1`
5. Добавить `Setup-Schedule-<NETWORK>.ps1` с нужным временем
6. Обновить `Check-All-Bots.ps1` (добавить проверку новой сети)
7. Обновить `README.md` (расписание, токены)
8. Протестировать: `pwsh -File <net>-bot\Test-Bot-<NETWORK>.ps1`

## Связанные скиллы проекта

- `nl-price-check` — взять актуальную цену/характеристики с сайта NL перед написанием поста
- `content-strategy` — спланировать рубрикатор и темы
- `social` — лучшие практики оформления постов
- `image` — генерация обложек

## Чего НЕ делать (анти-паттерны)

- ❌ Не коммитить `config.json` с токенами
- ❌ Не ставить расписание на 09:00 / 18:00 / 13:00 ровно — сдвигать на 09:03, 18:07, 13:12 (анти-флад, на случай пересечения с другими партнёрами)
- ❌ Не публиковать один и тот же пост во все 4 сети одновременно — пусть будет интервал 1–2 часа
- ❌ Не использовать личный аккаунт для постинга — только страница/сообщество/канал
- ❌ Не игнорировать ротацию Meta-токена — иначе FB/IG встанут в самый неподходящий момент

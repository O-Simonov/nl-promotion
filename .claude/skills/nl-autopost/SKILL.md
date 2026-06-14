---
name: nl-autopost
description: This skill should be used when the user asks to "настроить автопостинг", "развернуть NL AutoPost", "добавить нового бота", "настроить расписание", "создать пост для NL", "сгенерировать картинку", "обновить токен", or discusses NL International social media automation setup.
version: 1.0.0
---

# NL AutoPost — Скилл развёртывания

Система автопубликации контента для дистрибьюторов NL International в 4 соцсети: Telegram, Facebook, Instagram, ВКонтакте.

## Когда применять этот скилл

- Пользователь хочет развернуть систему на новом компьютере
- Нужно добавить новую соцсеть или бота
- Требуется обновить токен доступа (Meta-токен из Explorer живёт ~1–2 часа — нужно делать бессрочный, см. раздел про токены)
- Нужно создать новый пост или пакет постов
- Что-то перестало работать — диагностика

---

## Архитектура системы

```
NL_produkt/
├── tg-bot/queue/       ← общая очередь для всех 4 ботов (.txt + .png)
├── tg-bot/backlog/     ← запас постов (автоматически перекладывается в queue)
├── tg-bot/             ← Telegram-бот (10:00)
├── fb-bot/             ← Facebook-бот (11:00)
├── ig-bot/             ← Instagram-бот (12:00)
└── vk-bot/             ← ВКонтакте-бот (14:00)
```

**Ключевой принцип:** все боты читают из `tg-bot/queue/`. Каждый бот перекладывает обработанный файл в свою папку `sent/`. Пост публикуется 4 раза (по одному в каждой соцсети).

**Автопополнение:** задача `NL-Queue-Refill` в 09:00 проверяет — если постов ≤ 8, перекладывает 10 штук из `backlog/` в `queue/`.

---

## Развёртывание с нуля

### Требования
- Windows 10/11
- PowerShell 7+ (`winget install Microsoft.PowerShell`)
- Аккаунты: Telegram, VK, Meta Developer (для Instagram + Facebook)
- Аккаунт imgbb.com (бесплатный — для хостинга картинок)

### Шаг 1 — Клонировать репозиторий
```powershell
git clone https://github.com/O-Simonov/nl-promotion.git NL_produkt
cd NL_produkt
```

### Шаг 2 — Настроить Telegram-бота
1. Открыть @BotFather → `/newbot` → получить токен вида `123456:ABC-DEF...`
2. Создать Telegram-канал, назначить бота администратором
3. Получить ID канала: отправить любое сообщение в канал, потом:
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
   ID канала будет в поле `channel_post.chat.id` (обычно `-100xxxxxxxxxx`)

Создать `tg-bot/config.json` (скопировать из `tg-bot/config.example.json`):
```json
{
  "botToken": "ТВОЙ_ТОКЕН_БОТА",
  "channelId": "-100XXXXXXXXXX"
}
```

### Шаг 3 — Настроить ВКонтакте-бота
1. Создать сообщество vk.com → Управление → Работа с API → Ключи доступа
2. Нужны права: `wall`, `photos`, `groups`

Создать `vk-bot/config.json`:
```json
{
  "accessToken": "ТОКЕН_VK",
  "groupId": "ID_ГРУППЫ_БЕЗ_МИНУСА"
}
```

### Шаг 4 — Настроить Instagram + Facebook (Meta)
**Оба бота используют Meta Graph API. Токен из Explorer живёт ~1–2 часа — обязательно делать БЕССРОЧНЫЙ (см. раздел «Бессрочный токен Meta» ниже).**

1. Зайти на developers.facebook.com → Мои приложения → выбрать приложение
2. Добавить use case: **"Управляйте всем на своей Странице"** (содержит `pages_manage_posts`)
3. Открыть Graph API Explorer → выбрать приложение
4. Добавить разрешения: `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`, `instagram_basic`, `instagram_content_publish`
5. "Создать токен доступа" → скопировать → **сделать бессрочным** (раздел ниже)

**Instagram Business Account ID** — найти в настройках Instagram → О профессиональном аккаунте.

Создать `ig-bot/config.json`:
```json
{
  "igUserId": "INSTAGRAM_BUSINESS_ACCOUNT_ID",
  "pageToken": "ТОКЕН_ИЗ_GRAPH_API_EXPLORER",
  "imgbbApiKey": "КЛЮЧ_С_IMGBB_COM",
  "apiVersion": "v25.0"
}
```

Создать `fb-bot/config.json`:
```json
{
  "pageToken": "ТОКЕН_ИЗ_GRAPH_API_EXPLORER",
  "pageId": "ID_СТРАНИЦЫ_FACEBOOK",
  "imgbbApiKey": "КЛЮЧ_С_IMGBB_COM",
  "apiVersion": "v25.0"
}
```

**imgbb API key:** зарегистрироваться на imgbb.com → Account → API → скопировать ключ.

### Шаг 5 — Создать расписание (запустить от администратора)
```powershell
pwsh -File tg-bot\Setup-Schedule.ps1
pwsh -File fb-bot\Setup-Schedule-FB.ps1
pwsh -File ig-bot\Setup-Schedule-IG.ps1
pwsh -File vk-bot\Setup-Schedule-VK.ps1
pwsh -File tg-bot\Check-Queue-Refill.ps1  # создаёт задачу NL-Queue-Refill
```

### Шаг 6 — Проверить подключение
```powershell
pwsh -File tg-bot\Test-Bot.ps1
pwsh -File fb-bot\Test-Bot-FB.ps1
pwsh -File ig-bot\Test-Bot-IG.ps1
pwsh -File vk-bot\Test-Bot-VK.ps1
```

### Шаг 7 — Общая проверка статуса
```powershell
pwsh -File Check-All-Bots.ps1
```

---

## Создание новых постов

### Формат файла поста
Файл `NN-название.txt` в `tg-bot/queue/` или `tg-bot/backlog/`:
```
Заголовок поста

Текст поста. Можно несколько абзацев.

#тег1 #тег2 #nlинтернэшнл
🔗 https://referral-link.example.com
```

Опционально рядом кладётся картинка `NN-название.png` (или `.jpg`).

### Генерация обложки
```powershell
pwsh -File tg-bot\Make-PostImage.ps1 `
  -Title "Заголовок поста" `
  -Subtitle "Подзаголовок (необязательно)" `
  -Category slimming `
  -Out "tg-bot\queue\NN-название.png"
```

**Категории и их иконки:**
| Категория | Иконка | Цвет | Применение |
|-----------|--------|------|-----------|
| `product` | 🥤 | зелёный | Общие продукты |
| `business` | 🚀 | синий | Бизнес-возможности |
| `review` | 💬 | оранжевый | Отзывы |
| `offer` | 📢 | красный | Акции и предложения |
| `news` | 🆕 | тёмно-зелёный | Новости |
| `slimming` | 🔥 | оранжево-красный | Продукты для похудения |
| `hair` | 💇 | фиолетовый | Уход за волосами |
| `skincare` | ✨ | розовый | Уход за кожей |
| `body` | 🧴 | зелёный | Уход за телом |
| `mens` | 🧔 | тёмно-синий | Мужская линейка |
| `kids` | 🌟 | янтарный | Детская линейка |
| `teeth` | 🦷 | голубой | Уход за зубами |

---

## Бессрочный токен Meta (делается один раз)

⚠️ Токен из Graph API Explorer живёт всего ~1–2 часа. Чтобы IG/FB-боты не падали, нужен БЕССРОЧНЫЙ page-токен:

1. Graph API Explorer (developers.facebook.com/tools/explorer): выбрать приложение, добавить разрешения `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`, `instagram_basic`, `instagram_content_publish` → «Создать токен доступа» → скопировать (короткий user-токен).
2. Взять **App ID** и **App Secret**: приложение → Настройки → Базовые.
3. Обменять на долгоживущий user-токен (открыть в браузере):
   `https://graph.facebook.com/v25.0/oauth/access_token?grant_type=fb_exchange_token&client_id=APP_ID&client_secret=APP_SECRET&fb_exchange_token=КОРОТКИЙ_ТОКЕН`
4. Получить бессрочный page-токен:
   `https://graph.facebook.com/v25.0/me/accounts?access_token=ДОЛГОЖИВУЩИЙ_USER_ТОКЕН` → скопировать `access_token` своей страницы.
5. Прописать его в `pageToken` в `ig-bot/config.json` и `fb-bot/config.json`.
6. Проверить срок: `https://graph.facebook.com/v25.0/debug_token?input_token=ТОКЕН&access_token=ТОКЕН` → `expires_at: 0` = бессрочный ✅
7. Тест: `pwsh -File ig-bot\Test-Bot-IG.ps1` и `pwsh -File fb-bot\Test-Bot-FB.ps1`

---

## Диагностика

### Проверить все задачи разом
```powershell
pwsh -File Check-All-Bots.ps1
```
Результат 0 = успех. Отличные от 0 коды — смотреть логи в `<бот>/logs/`.

### Запустить бота вручную (без расписания)
```powershell
pwsh -File tg-bot\Post-Next.ps1
pwsh -File fb-bot\Post-Next-FB.ps1
pwsh -File ig-bot\Post-Next-IG.ps1
pwsh -File vk-bot\Post-Next-VK.ps1
```

### Посмотреть статус очереди
```powershell
(Get-ChildItem tg-bot\queue -Filter *.txt).Count   # должно быть > 0
(Get-ChildItem tg-bot\backlog -Filter *.txt).Count  # запас постов
```

### Типичные ошибки
| Ошибка | Причина | Решение |
|--------|---------|---------|
| 401 Unauthorized | Токен истёк | Обновить токен (шаг выше) |
| 403 Forbidden | Нет нужного разрешения | Добавить use case в Meta App |
| Очередь пустая | Backlog закончился | Написать новые посты |
| Картинка не публикуется в IG/FB | imgbb ключ неверный | Проверить `imgbbApiKey` в конфиге |

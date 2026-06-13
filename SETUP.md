# Инструкция по развёртыванию NL AutoPost

Полное руководство: какие сервисы нужны, как получить API ключи и где разместить сайт.

---

## Обзор сервисов

| Сервис | Для чего | Цена |
|--------|----------|------|
| Telegram @BotFather | Публикация в Telegram-канал | Бесплатно |
| VK Developer | Публикация в сообщество ВКонтакте | Бесплатно |
| Meta Developer Platform | Публикация в Instagram и Facebook | Бесплатно |
| imgbb.com | Хостинг картинок для Instagram/Facebook | Бесплатно |
| GitHub | Хранение кода | Бесплатно |
| Netlify | Хостинг сайта-хаба | Бесплатно |

---

## 1. Telegram — бот для канала

### Что нужно
- Аккаунт Telegram
- Телеграм-канал (публичный или приватный)

### Шаги

**Создать бота:**
1. Открыть Telegram → найти **@BotFather**
2. Написать `/newbot`
3. Задать имя бота (например: `NL Олег Симонов`)
4. Задать username бота (например: `my_nl_bot`) — должен заканчиваться на `bot`
5. BotFather пришлёт токен вида: `123456789:AAGHyCobdGiNOaMObK57qM3ExCZxib1SzSw`

**Создать канал и добавить бота:**
1. Создать новый канал в Telegram
2. Зайти в настройки канала → Администраторы → Добавить администратора
3. Найти своего бота по username → добавить с правами на публикацию

**Получить ID канала:**
1. Отправить любое сообщение в канал
2. Открыть в браузере: `https://api.telegram.org/bot<ТОКЕН>/getUpdates`
3. Найти поле `channel_post.chat.id` — это и есть ID (вида `-1001234567890`)

**Записать в конфиг** `tg-bot/config.json`:
```json
{
  "botToken": "123456789:AAGHyCobdGiNOaMObK57qM3ExCZxib1SzSw",
  "channelId": "-1001234567890"
}
```

---

## 2. ВКонтакте — бот для сообщества

### Что нужно
- Аккаунт ВКонтакте
- Сообщество ВКонтакте (группа или публичная страница)

### Шаги

**Создать сообщество:**
1. Зайти на vk.com → раздел «Сообщества» → «Создать сообщество»
2. Выбрать тип: Публичная страница или Группа

**Получить API ключ:**
1. Зайти в сообщество → **Управление** (кнопка под обложкой)
2. → **Работа с API** → **Ключи доступа** → **Создать ключ**
3. Отметить разрешения: ✅ `Управление` ✅ `Фотографии` ✅ `Записи на стене`
4. Подтвердить через SMS

**Получить ID сообщества:**
- Открыть страницу сообщества → в адресной строке: `vk.com/club239517960`
- Число после `club` — это ID (в данном случае `239517960`)

**Записать в конфиг** `vk-bot/config.json`:
```json
{
  "botToken": "vk1.a.XXXXXXXXXXXXXXXX",
  "groupId": 239517960,
  "apiVersion": "5.199"
}
```

---

## 3. Instagram + Facebook — Meta Graph API

### Что нужно
- Аккаунт Facebook
- **Facebook Страница** (не личный профиль)
- **Instagram бизнес-аккаунт**, привязанный к этой странице
- Аккаунт на developers.facebook.com

### Шаги

**Перевести Instagram в бизнес-аккаунт:**
1. Instagram → Настройки → Аккаунт → Переключиться на профессиональный аккаунт
2. Выбрать тип: Бизнес
3. Привязать к своей Facebook странице

**Создать приложение Meta:**
1. Зайти на **developers.facebook.com** → **Мои приложения** → **Создать приложение**
2. Тип: **Бизнес**
3. Название приложения: любое (например `NL AutoPost`)

**Добавить нужный use case:**
1. В приложении → **Use cases** → **Добавить**
2. Найти и добавить: **«Управляйте всем на своей Странице»**
   - Это добавит разрешения `pages_manage_posts` и `instagram_content_publish`
3. Нажать **Настроить**

**Получить токен через Graph API Explorer:**
1. Открыть: **developers.facebook.com/tools/explorer**
2. Выбрать своё приложение (правый верхний угол)
3. Нажать **«Создать токен страницы»** → выбрать свою Facebook страницу
4. Добавить разрешения:
   - `pages_manage_posts`
   - `instagram_basic`
   - `instagram_content_publish`
5. Нажать **Создать** → скопировать токен

> ⚠️ **Токен живёт ~60 дней!** После истечения нужно повторить этот шаг.
> Система пришлёт напоминание в Telegram за 2 дня до истечения.

**Получить Instagram Business Account ID:**
1. В Graph API Explorer вставить: `me/accounts` → нажать **Выполнить**
2. Найти свою страницу и скопировать её `id` — это Facebook Page ID
3. Затем: `/{page-id}?fields=instagram_business_account` → скопировать `id` внутри

**Записать в конфиги:**

`ig-bot/config.json`:
```json
{
  "igUserId": "17841407515803031",
  "pageToken": "ТОКЕН_ИЗ_GRAPH_API_EXPLORER",
  "imgbbApiKey": "КЛЮЧ_С_IMGBB_COM",
  "apiVersion": "v25.0"
}
```

`fb-bot/config.json`:
```json
{
  "pageToken": "ТОКЕН_ИЗ_GRAPH_API_EXPLORER",
  "pageId": "1167094323156986",
  "imgbbApiKey": "КЛЮЧ_С_IMGBB_COM",
  "apiVersion": "v25.0"
}
```

---

## 4. imgbb.com — хостинг картинок

Нужен потому что Instagram и Facebook API принимают только **публичные URL** изображений — локальные файлы не подходят.

### Шаги
1. Зайти на **imgbb.com** → зарегистрироваться (бесплатно)
2. Открыть: **imgbb.com/account/api** (или Account → API)
3. Скопировать API Key
4. Вставить в `ig-bot/config.json` и `fb-bot/config.json` → поле `imgbbApiKey`

---

## 5. GitHub — хранение кода

### Шаги
1. Зарегистрироваться на **github.com**
2. Создать новый репозиторий (можно приватный)
3. Клонировать исходный проект и запушить в свой репозиторий:

```powershell
git clone https://github.com/O-Simonov/nl-promotion.git NL_produkt
cd NL_produkt
git remote set-url origin https://github.com/ТВО_ИМЯ/ТВОЙ_РЕПОЗИТОРИЙ.git
git push -u origin main
```

---

## 6. Netlify — хостинг сайта

Netlify автоматически публикует сайт при каждом push в GitHub.

### Шаги
1. Зарегистрироваться на **netlify.com**
2. **Add new project** → **Import from Git** → выбрать GitHub
3. Выбрать свой репозиторий
4. Настройки деплоя:
   - **Build command**: оставить пустым
   - **Publish directory**: `.` (точка — корень репозитория)
5. Нажать **Deploy**

> Файл `netlify.toml` в корне проекта уже содержит эти настройки, но лучше проверить в дашборде: **Project configuration → Continuous deployment → Build settings → Publish directory = `.`**

После деплоя сайт будет доступен по адресу вида `твой-проект.netlify.app`.

### Подключить своё фото
Положить файл `foto.jpg` в корень проекта и закоммитить:
```powershell
git add foto.jpg
git commit -m "добавлено фото"
git push
```

---

## 7. Настройка расписания (Windows)

После заполнения всех конфигов запустить от имени администратора:

```powershell
pwsh -File tg-bot\Setup-Schedule.ps1       # Telegram 10:00
pwsh -File fb-bot\Setup-Schedule-FB.ps1   # Facebook 11:00
pwsh -File ig-bot\Setup-Schedule-IG.ps1   # Instagram 12:00
pwsh -File vk-bot\Setup-Schedule-VK.ps1   # ВКонтакте 14:00
pwsh -File tg-bot\Check-Queue-Refill.ps1  # Автопополнение 09:00
pwsh -File tg-bot\Setup-Token-Reminder.ps1 # Напоминание о токенах
```

Проверить что всё работает:
```powershell
pwsh -File tg-bot\Test-Bot.ps1
pwsh -File fb-bot\Test-Bot-FB.ps1
pwsh -File ig-bot\Test-Bot-IG.ps1
pwsh -File vk-bot\Test-Bot-VK.ps1
pwsh -File Check-All-Bots.ps1
```

---

## Частые проблемы

| Проблема | Причина | Решение |
|----------|---------|---------|
| Instagram/Facebook 400 Bad Request | Токен истёк | Обновить токен в Graph API Explorer |
| Instagram/Facebook 403 Forbidden | Нет разрешения `pages_manage_posts` | Добавить use case в Meta Developer |
| Картинки не публикуются в IG/FB | Неверный imgbb ключ | Проверить `imgbbApiKey` в конфиге |
| Netlify: "Deploy directory 'site' does not exist" | Неверный Publish directory | Изменить на `.` в настройках Netlify |
| VK: нет прав | Токен без нужных разрешений | Создать новый ключ с правами wall+photos |
| Telegram: бот не пишет в канал | Бот не администратор | Добавить бота в администраторы канала |

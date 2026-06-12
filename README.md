# NL AutoPost — автоматическая публикация в 4 соцсети

Система автопостинга для дистрибьютора NL International. Публикует посты с картинками в Telegram, Facebook, Instagram и ВКонтакте по расписанию без ручного участия.

## Что делает проект

- **4 бота** публикуют посты ежедневно в Telegram (10:00), Facebook (11:00), Instagram (12:00), ВКонтакте (14:00)
- **Генератор картинок** создаёт обложки для постов с иконками и цветами по категории
- **Очередь и бэклог** — посты автоматически перекладываются из бэклога в очередь когда заканчиваются
- **Сайт-хаб** на Netlify с каталогом продуктов и реферальными ссылками

## Структура проекта

```
NL_produkt/
├── index.html                  # Сайт-хаб (задеплоен на Netlify)
├── Check-All-Bots.ps1          # Проверка статуса всех ботов
├── БАЗА-ЗНАНИЙ-NL.md           # База знаний о продуктах
│
├── tg-bot/                     # Telegram-бот
│   ├── Post-Next.ps1           # Публикация следующего поста
│   ├── Setup-Schedule.ps1      # Создание расписания (10:00)
│   ├── Test-Bot.ps1            # Проверка подключения
│   ├── Make-PostImage.ps1      # Генератор картинок
│   ├── Check-Queue-Refill.ps1  # Автопополнение очереди (09:00)
│   ├── config.json             # Токен бота и ID канала
│   ├── config.example.json     # Пример конфига
│   ├── queue/                  # Посты на публикацию (.txt + .png)
│   └── backlog/                # Запас постов (35 штук)
│
├── vk-bot/                     # ВКонтакте-бот
│   ├── Post-Next-VK.ps1
│   ├── Setup-Schedule-VK.ps1   # Расписание (14:00)
│   ├── Test-Bot-VK.ps1
│   └── config.json
│
├── ig-bot/                     # Instagram-бот
│   ├── Post-Next-IG.ps1
│   ├── Setup-Schedule-IG.ps1   # Расписание (12:00)
│   ├── Test-Bot-IG.ps1
│   └── config.json
│
└── fb-bot/                     # Facebook-бот
    ├── Post-Next-FB.ps1
    ├── Setup-Schedule-FB.ps1   # Расписание (11:00)
    ├── Test-Bot-FB.ps1
    └── config.json
```

## Быстрый старт

### Требования
- Windows 10/11
- PowerShell 7+ (`winget install Microsoft.PowerShell`)

### 1. Клонировать репозиторий
```powershell
git clone https://github.com/O-Simonov/nl-promotion.git
cd nl-promotion
```

### 2. Настроить конфиги
Скопировать `config.example.json` → `config.json` в каждой папке и вставить токены:

| Бот | Где взять токен |
|-----|----------------|
| Telegram | @BotFather → /newbot |
| ВКонтакте | vk.com/dev → Управление → Ключи доступа |
| Instagram | developers.facebook.com → Graph API Explorer |
| Facebook | developers.facebook.com → Graph API Explorer |

### 3. Создать расписание
```powershell
pwsh -File tg-bot\Setup-Schedule.ps1
pwsh -File vk-bot\Setup-Schedule-VK.ps1
pwsh -File ig-bot\Setup-Schedule-IG.ps1
pwsh -File fb-bot\Setup-Schedule-FB.ps1
```

### 4. Проверить подключение
```powershell
pwsh -File tg-bot\Test-Bot.ps1
pwsh -File vk-bot\Test-Bot-VK.ps1
pwsh -File ig-bot\Test-Bot-IG.ps1
pwsh -File fb-bot\Test-Bot-FB.ps1
```

### 5. Проверить статус всех ботов
```powershell
pwsh -File Check-All-Bots.ps1
```

## Расписание

| Время | Задача |
|-------|--------|
| 09:00 | Проверка очереди → пополнение из бэклога если ≤ 8 постов |
| 10:00 | Публикация в Telegram |
| 11:00 | Публикация в Facebook |
| 12:00 | Публикация в Instagram |
| 14:00 | Публикация в ВКонтакте |

## Генерация картинок

```powershell
pwsh -File tg-bot\Make-PostImage.ps1 `
  -Title "Заголовок поста" `
  -Subtitle "Подзаголовок" `
  -Category slimming `
  -Out "tg-bot\queue\post.png"
```

Категории: `product`, `business`, `review`, `offer`, `news`, `slimming`, `hair`, `skincare`, `body`, `mens`, `kids`, `teeth`

## Сайт

Сайт-хаб задеплоен на Netlify и автоматически обновляется при пуше в `main`:
🔗 https://oleg-nl.netlify.app/

## Соцсети

- Telegram: https://t.me/Simka1969_nl
- Instagram: https://www.instagram.com/simonov3480/
- ВКонтакте: https://vk.com/club239517960
- Facebook: https://www.facebook.com/profile.php?id=1167094323156986

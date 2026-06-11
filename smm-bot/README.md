# SMMplanner-бот для автопостинга через SMMplanner API.

Работает в тройке с Telegram- и VK-ботами. Берёт из общей очереди `../tg-bot/queue/`.

## Что делает

Один и тот же пост из нашей очереди → сразу в **несколько соцсетей** через SMMplanner:
- 💬 **MAX**
- 🆗 **ОК**  
- (любые другие, что подключишь в SMMplanner)

## Файлы

- **`Post-Next-SMMP.ps1`** — публикация одного поста через SMMplanner API v2.
- **`Test-Bot-SMMP.ps1`** — проверка, что токен SMMplanner рабочий.
- **`Get-Accounts-SMMP.ps1`** — получить ID подключённых аккаунтов (для `config.json`).
- **`Setup-Schedule-SMMP.ps1`** — задача в Windows Task Scheduler (ежедневно в 18:00).
- **`config.json`** — токен + ID аккаунтов (в `.gitignore`).

## Настройка (один раз)

1. Зайди в https://smmplanner.com → **Настройки → API-ключи** (или раздел "API").
2. Скопируй **API-ключ** в `config.json` (`accessToken`).
3. Запусти `pwsh -File Get-Accounts-SMMP.ps1` — получишь список ID аккаунтов.
4. Впиши нужные ID в `config.json` (`accountIds: [12345, 67890]`).
5. Запусти `pwsh -File Test-Bot-SMMP.ps1` — проверь, что токен рабочий.
6. Запусти `pwsh -File Setup-Schedule-SMMP.ps1` — создастся расписание.

## Схема работы всех ботов

```
[tg-bot/queue/03-den3.txt]
        │
        ├── 10:00 → Telegram-бот (NL-Telegram-AutoPost) → канал @Simka1969_nl
        │
        ├── 14:00 → VK-бот (NL-VK-AutoPost) → сообщество "NL с Олегом Симоновым"
        │
        └── 18:00 → SMMplanner-бот → MAX + ОК + др.
```

Каждый бот **берёт первый файл** из очереди → публикует → переносит в свой `sent/`.
Файл уходит из очереди только когда **все** боты с ним отработали.

## Важно

- Токен SMMplanner — секрет, не пиши его в чат/коммиты.
- Если токен утечёт — регенерируй в личном кабинете SMMplanner.
- Расписание работает **только когда ПК включён** (StartWhenAvailable срабатывает при следующем включении).

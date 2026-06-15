# 🤝 Памятка партнёра — как развернуть проект под себя

Это проект автопостинга и сайта-хаба для дистрибьютора NL. Ты можешь поднять **свою копию**
за 15 минут (только сайт) или полностью (сайт + 4 бота). Главное — **везде свои данные**.

> ⚠️ Система не «общая», а **копируется**: у тебя должны быть свои реф-ссылки, свои аккаунты
> и свои токены. Чужие токены не передаются (они в `.gitignore`). Но в постах зашиты ссылки
> автора — их **обязательно** заменить на свои (шаг 2), иначе будешь рекламировать не себя.

---

## Путь 1. Только сайт-хаб (быстро, ~15 мин, любой компьютер)

Нужен лендинг со ссылками и презентациями, без ботов.

1. **Форкни** этот репозиторий к себе на GitHub (кнопка Fork).
2. Зайди на **netlify.com** → *Add new site* → *Import from GitHub* → выбери свой форк.
   Сайт задеплоится автоматически (или жми кнопку **Deploy to Netlify** в README).
3. **Персонализируй** — замени ссылки/имя/фото:
   ```powershell
   pwsh -File Setup-Partner.ps1
   ```
   Скрипт спросит твои реф-ссылки, имя, соцсети и заменит их во всех файлах.
   Затем положи своё фото в `foto.jpg` (то же имя) и запушь на GitHub — Netlify обновится сам.

Готово. Токены и Windows тут не нужны.

---

## Путь 2. Сайт + автопостинг (полный, нужен Windows)

Боты публикуют посты сами в Telegram / Facebook / Instagram / VK по расписанию.

**Что нужно:** Windows 10/11, PowerShell 7 (`winget install Microsoft.PowerShell`),
свои каналы/страницы и токены к ним.

1. **Склонируй** репозиторий:
   ```powershell
   git clone https://github.com/O-Simonov/nl-promotion.git
   cd nl-promotion
   ```
2. **Персонализируй** посты и сайт:
   ```powershell
   pwsh -File Setup-Partner.ps1
   ```
3. **Заполни токены** — в каждой папке `*-bot` скопируй `config.example.json` → `config.json`
   и впиши свои ключи. Где их брать — подробно в **SETUP.md**:
   | Бот | Где взять токен |
   |-----|----------------|
   | Telegram | @BotFather → /newbot |
   | ВКонтакте | токен своего сообщества |
   | Facebook + Instagram | developers.facebook.com → Graph API Explorer |
   | Картинки | imgbb.com → API key |
4. **Запусти расписание** (создаёт задачи 10/11/12/14:00):
   ```powershell
   pwsh -File tg-bot\Setup-Schedule.ps1
   pwsh -File fb-bot\Setup-Schedule-FB.ps1
   pwsh -File ig-bot\Setup-Schedule-IG.ps1
   pwsh -File vk-bot\Setup-Schedule-VK.ps1
   ```
5. **Проверь**:
   ```powershell
   pwsh -File Check-All-Bots.ps1
   ```

Полная инструкция по токенам и частым проблемам — в **SETUP.md**.

---

## Чек-лист «что заменить под себя»

- [ ] Реф-ссылки (продуктовая + бизнес) — через `Setup-Partner.ps1`
- [ ] Имя, Telegram / Instagram / VK / Facebook — через `Setup-Partner.ps1`
- [ ] Адрес своего сайта на Netlify — через `Setup-Partner.ps1`
- [ ] Фото `foto.jpg` в корне — вручную
- [ ] `config.json` с токенами в каждой папке `*-bot` — вручную (SETUP.md)
- [ ] Официальный канал NL `t.me/nl25_news` — **НЕ трогать**, он общий

После `Setup-Partner.ps1` всегда проверь правки: `git diff` (откатить всё: `git checkout .`).

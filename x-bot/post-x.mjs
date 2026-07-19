// X (Twitter) — Playwright-воркер публикации твита.
// Запускается PowerShell-оркестратором Post-Next-X.ps1. Параметры передаются
// через переменные окружения (префикс X_ чтобы не пересекаться с другими ботами):
//   X_LOGIN, X_PASSWORD  — логин/пароль аккаунта
//   X_TEXT, X_IMAGE      — текст твита и путь к png/jpg (опц.)
//   X_HEADLESS           — 'true'/'false' (по умолчанию true)
//   X_SESSION_PATH       — путь к session.json (чтение/запись)
// Режимы:
//   X_TEST=1    — только сверить авторизацию, без публикации (Test-Bot-X.ps1)
//   X_MANUAL=1  — ручной вход: открыть x.com/login и ждать, пока человек залогинится
//                 сам; сессия сохраняется (Login-X.ps1)
// Выводит в stdout одну строку JSON: {"ok":true,"user":"..."} или {"ok":false,"error":"...","needManual":true?}
// Код выхода: 0 — успех, 1 — сбой.
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const login       = process.env.X_LOGIN || '';
const password    = process.env.X_PASSWORD || '';
const text        = process.env.X_TEXT || '';
const imagePath   = process.env.X_IMAGE || '';
const headless    = process.env.X_HEADLESS !== 'false';
const sessionPath = process.env.X_SESSION_PATH || './session.json';
const shotDir     = path.join(path.dirname(sessionPath) || '.', 'logs');

const result = { ok: false, user: '' };

(async () => {
  let browser, context, page;
  try {
    const ctxOpts = { userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
                      viewport: { width: 1280, height: 900 }, locale: 'en-US' };
    if (fs.existsSync(sessionPath)) ctxOpts.storageState = sessionPath;

    browser = await chromium.launch({ headless });
    context = await browser.newContext(ctxOpts);
    page = await context.newPage();
    page.setDefaultTimeout(45000);

    if (process.env.X_MANUAL === '1') {
      // Ручной вход: открываем x.com/login и ждём, пока человек залогинится сам
      // (пройдя любой челлендж). Сессию сохраняем — дальше бот ходит сам.
      await page.goto('https://x.com/login', { waitUntil: 'domcontentloaded' });
      const deadline = Date.now() + 5 * 60 * 1000;
      let ok = false;
      while (Date.now() < deadline) {
        await page.waitForTimeout(3000);
        if (await isLoggedIn(page)) { ok = true; break; }
      }
      if (!ok) { result.ok = false; result.error = 'Таймаут: за 5 минут ручной вход не завершён'; }
      else { await context.storageState({ path: sessionPath }); result.ok = true; result.user = '(сессия сохранена вручную)'; }
    } else {
      // 1. Пытаемся зайти на home и понять, авторизованы ли (по сохранённой сессии).
      await page.goto('https://x.com/home', { waitUntil: 'domcontentloaded' });
      let loggedIn = await isLoggedIn(page);

      // 2. Если не авторизованы — логинимся и сохраняем сессию (может упереться в троттл/челлендж).
      if (!loggedIn) {
        await loginFlow(page, login, password);
        await context.storageState({ path: sessionPath });
        loggedIn = await isLoggedIn(page);
        if (!loggedIn) {
          const e = new Error('Логин не прошёл: возможно, X показал 2FA/челлендж или тротлит вход — нужен ручной вход через Login-X.ps1');
          e.needManual = true;
          throw e;
        }
      }

      // 3. Режим проверки (Test-Bot-X): публикацию пропускаем, только сверяем авторизацию.
      if (process.env.X_TEST === '1') {
        result.ok = loggedIn;
        try {
          const btn = await page.$('[data-testid="SideNav_AccountSwitcher_Button"]');
          if (btn) result.user = (await btn.getAttribute('aria-label')) || (await btn.innerText()) || '(handle не удалось прочитать)';
          else result.user = '(кнопка аккаунта не найдена — но редактор твита есть)';
        } catch { result.user = '(handle не удалось прочитать)'; }
      } else {
        // Публикуем твит.
        await postTweet(page, text, imagePath);
        result.ok = true;
      }
    }
  } catch (e) {
    result.ok = false;
    result.error = e.message || String(e);
    if (e.needManual) result.needManual = true;
    try {
      if (!fs.existsSync(shotDir)) fs.mkdirSync(shotDir, { recursive: true });
      if (page) await page.screenshot({ path: path.join(shotDir, 'x-error.png'), fullPage: false });
    } catch {}
  } finally {
    try { if (context) await context.close(); } catch {}
    try { if (browser) await browser.close(); } catch {}
    console.log(JSON.stringify(result));
    process.exit(result.ok ? 0 : 1);
  }
})();

// Авторизованы, если на home виден редактор твита или кнопка аккаунта в сайдбаре.
async function isLoggedIn(page) {
  try {
    const sel = '[data-testid="tweetTextarea_0"], [data-testid="SideNav_AccountSwitcher_Button"]';
    const el = await page.$(sel);
    return !!el;
  } catch { return false; }
}

async function loginFlow(page, login, password) {
  await page.goto('https://x.com/i/flow/login', { waitUntil: 'domcontentloaded' });

  // Новый flow X (/i/jf/onboarding): поле по name. Сабмитим Enter'ом, а не кликом
  // по «Continue» — на странице задвоенные кнопки (моб.+десктоп), клик по ним хрупок.
  const userInput = page.locator('input[name="username_or_email"]').first();
  await userInput.waitFor({ timeout: 45000 });
  await userInput.fill(login);
  await userInput.press('Enter');

  // После сабмита X может показать: настоящее поле пароля, экран верификации
  // (телефон/имя/2FA) либо троттл входа. В DOM с самого начала лежит приманка-password
  // (aria-hidden=true, tabindex=-1) — её не трогаем; ждём настоящее поле без aria-hidden.
  const pwInput   = page.locator('input[type="password"]:not([aria-hidden="true"])');
  const challenge = page.locator('input[name="phone_or_username"], [data-testid="ocfEnterTextInput"]');
  const limited   = page.getByText(/temporarily limited|limited your login|try again later|suspicious login|unusual activity/i);
  let got = null;
  await Promise.race([
    pwInput.waitFor({ timeout: 20000 }).then(() => { got = 'pw'; }),
    challenge.waitFor({ timeout: 20000 }).then(() => { got = 'challenge'; }),
    limited.waitFor({ timeout: 20000 }).then(() => { got = 'limited'; }),
  ]).catch(() => {});

  if (got === 'limited') {
    const e = new Error('X троттлит вход («temporarily limited your login») — подожди пару часов и повтори, либо залогинись руками через Login-X.ps1 в своей RDP-сессии');
    e.needManual = true;
    throw e;
  }
  if (got !== 'pw') {
    const e = new Error('После логина X показал челлендж верификации (телефон/имя/2FA) — нужен ручной вход через Login-X.ps1');
    e.needManual = true;
    throw e;
  }
  await pwInput.fill(password);
  await pwInput.press('Enter');
  await page.waitForTimeout(3000);
}

async function postTweet(page, text, imagePath) {
  await page.goto('https://x.com/compose/post', { waitUntil: 'domcontentloaded' });
  const editor = page.locator('[data-testid="tweetTextarea_0"]');
  await editor.waitFor({ timeout: 30000 });
  await editor.click();
  // Вводим текст посимвольно (delay) — X иногда проглатывает мгновенную вставку.
  await page.keyboard.type(text, { delay: 6 });

  if (imagePath && fs.existsSync(imagePath)) {
    const fileInput = page.locator('input[type="file"]').first();
    await fileInput.setInputFiles(imagePath);
    // Ждём появления превью вложения — признак, что загрузка завершилась.
    await page.locator('[data-testid="tweetPhoto"], [data-testid="mediaImage"]').first()
      .waitFor({ timeout: 60000 });
  }

  const postBtn = page.getByRole('button', { name: 'Post' });
  await postBtn.waitFor({ state: 'visible', timeout: 10000 });
  // Кнопка «Post» кратковременно disabled, пока собирается пост/загружается медиа.
  for (let i = 0; i < 60; i++) {
    const disabled = await postBtn.getAttribute('disabled');
    if (disabled === null) break;
    await page.waitForTimeout(500);
  }
  await postBtn.click();

  // Пост опубликован, когда редактор закрылся (модалка пропала).
  await page.waitForSelector('[data-testid="tweetTextarea_0"]', { state: 'detached', timeout: 30000 })
    .catch(() => {});
}
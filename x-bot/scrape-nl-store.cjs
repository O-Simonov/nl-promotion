/**
 * NL Store scraper with rotating proxys.io proxies.
 * Usage:
 *   node scrape-nl-store.cjs
 *   node scrape-nl-store.cjs --cards
 *   node scrape-nl-store.cjs --url https://ng.nlstar.com/ru/product/74724
 *
 * Proxies: host:port:user:pass in Desktop\Прокси\proxys_*.txt (+ Desktop\proxys_*.txt)
 * SOCKS5 via proxy-chain. Mobile pools preferred (newer session / NL_PROXY_MOBILE=1).
 * Or set NL_PROXY_FILE / NL_PROXY (single host:port:user:pass)
 */
const { chromium } = require('playwright');
const ProxyChain = require('proxy-chain');
const fs = require('fs');
const path = require('path');

const LOG_DIR = path.join('C:', 'NL_produkt', 'logs');
const DESKTOP = path.join('C:', 'Users', 'Administrator', 'Desktop');
const PROXY_DIR = path.join(DESKTOP, 'Прокси');
const OUT = path.join(LOG_DIR, 'nl-store-scrape.json');
// Known mobile pool file ids from proxys.io (LTE/mobile sessions)
const MOBILE_POOL_IDS = new Set(['63368', '63374']);

fs.mkdirSync(LOG_DIR, { recursive: true });

function parseProxyLine(line) {
  const s = String(line || '').trim();
  if (!s || s.startsWith('#')) return null;
  const parts = s.split(':');
  if (parts.length < 4) return null;
  const [host, port, user, ...rest] = parts;
  const password = rest.join(':');
  // Chrome/Playwright cannot auth SOCKS5 — we anonymize via proxy-chain later
  const upstream = `socks5://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}`;
  return {
    upstream,
    label: `${host}:${port}`,
    user,
  };
}

function collectProxyFiles() {
  const files = [];
  const seen = new Set();
  const addDir = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const name of fs.readdirSync(dir)) {
      if (!/^proxys_\d+\.txt$/i.test(name)) continue;
      const full = path.join(dir, name);
      const key = name.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      files.push(full);
    }
  };
  if (process.env.NL_PROXY_FILE && fs.existsSync(process.env.NL_PROXY_FILE)) {
    return [process.env.NL_PROXY_FILE];
  }
  addDir(PROXY_DIR);
  addDir(DESKTOP);
  return files;
}

function isMobilePool(filePath, parsed) {
  const base = path.basename(filePath);
  const m = base.match(/proxys_(\d+)\.txt/i);
  if (m && MOBILE_POOL_IDS.has(m[1])) return true;
  // proxys.io mobile option often uses a distinct package id in username (o39642…)
  if (parsed && /o39642/i.test(parsed.user || '')) return true;
  return false;
}

function loadProxies() {
  if (process.env.NL_PROXY) {
    const one = parseProxyLine(process.env.NL_PROXY);
    return one ? [{ ...one, source: 'NL_PROXY', mobile: true }] : [];
  }
  const files = collectProxyFiles();
  const out = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
    // One entry per pool file (port 10000) — rotating pool, session in username
    const first = parseProxyLine(lines.find((l) => l.trim()));
    if (!first) continue;
    const mobile = isMobilePool(f, first);
    out.push({ ...first, source: path.basename(f), mobile });
  }
  // Prefer mobile only when explicitly requested; otherwise put them last
  // (current mobile sessions often fail SOCKS5 until reissued by provider)
  if (process.env.NL_PROXY_MOBILE === '1') {
    out.sort((a, b) => Number(b.mobile) - Number(a.mobile));
    const only = out.filter((p) => p.mobile);
    return only.length ? only : out;
  }
  out.sort((a, b) => Number(a.mobile) - Number(b.mobile));
  return out;
}

function pickProxy(proxies, attempt) {
  if (!proxies.length) return null;
  return proxies[attempt % proxies.length];
}

async function openContext(proxy) {
  const opts = {
    channel: 'chrome',
    headless: true,
    locale: 'ru-RU',
    viewport: { width: 1365, height: 900 },
    args: ['--disable-blink-features=AutomationControlled'],
    ignoreDefaultArgs: ['--enable-automation'],
  };
  let anonymizedUrl = null;
  if (proxy && proxy.upstream) {
    anonymizedUrl = await ProxyChain.anonymizeProxy(proxy.upstream);
    opts.proxy = { server: anonymizedUrl };
  }
  const browser = await chromium.launch(opts);
  const context = await browser.newContext({
    locale: 'ru-RU',
    userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  });
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });
  const close = async () => {
    await browser.close().catch(() => {});
    if (anonymizedUrl) await ProxyChain.closeAnonymizedProxy(anonymizedUrl, true).catch(() => {});
  };
  return { browser, context, close };
}

function isBlocked(text) {
  return /Forbidden|Access Denied|captcha|не робот/i.test((text || '').slice(0, 800));
}

async function dismissRegionModal(page) {
  const yes = page.getByRole('button', { name: /^Да$/i }).first();
  if (await yes.isVisible({ timeout: 2500 }).catch(() => false)) {
    await yes.click().catch(() => {});
    await page.waitForTimeout(800);
  }
}

async function scrapeListing(page, label, url) {
  const resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 120000 }).catch(async () =>
    page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 })
  );
  await dismissRegionModal(page);
  await page.waitForSelector('a[href*="/ru/product/"], a[href*="/ru/set/"]', { timeout: 25000 }).catch(() => {});
  await page.waitForTimeout(5000);
  const bodyText = await page.locator('body').innerText().catch(() => '');
  if (isBlocked(bodyText)) {
    return { label, url, blocked: true, status: resp && resp.status(), snippet: bodyText.slice(0, 300) };
  }
  const linkCount = await page.locator('a[href*="/ru/product/"], a[href*="/ru/set/"]').count().catch(() => 0);
  console.log(`  [${label}] body=${bodyText.length} chars, productLinks=${linkCount}`);
  if (linkCount === 0) {
    console.log('  snippet:', bodyText.slice(0, 200).replace(/\s+/g, ' '));
  }
  const items = await page.evaluate(() => {
    const out = [];
    const seen = new Set();
    const links = [...document.querySelectorAll('a[href*="/ru/product/"], a[href*="/ru/set/"]')];
    for (const a of links) {
      const href = a.href;
      if (seen.has(href)) continue;
      seen.add(href);
      let block = a;
      let cardText = '';
      for (let i = 0; i < 10 && block; i++) {
        const t = (block.textContent || '').replace(/\s+/g, ' ').trim();
        if (t.includes('₽') || /В корзину|Нет в наличии|Выбрать/.test(t)) {
          cardText = t;
          break;
        }
        block = block.parentElement;
      }
      if (!cardText) continue;
      let name = (a.textContent || '').replace(/\s+/g, ' ').trim();
      if (!name || name.length < 3 || name.length > 120) {
        const m = cardText.match(/[«"]([^»"]+)[»"]|\(([^)]+)\)|([A-Za-zА-Яа-яЁё][^₽]{4,80}?)(?=\s*(?:В корзину|Выбрать|\d))/);
        name = (m && (m[1] || m[2] || m[3]) || cardText.slice(0, 80)).trim();
      }
      out.push({
        name: name.slice(0, 160),
        price: (cardText.match(/\d[\d\s]*₽/) || [''])[0].replace(/\s+/g, ' '),
        badge: (cardText.match(/Новинка|Хит продаж|Марка №1|Выбор покупателей|СЕТ/i) || [''])[0],
        href,
      });
      if (out.length >= 20) break;
    }
    return out;
  });
  return { label, url, blocked: false, status: resp && resp.status(), items };
}

async function scrapeCard(page, url) {
  const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await dismissRegionModal(page);
  await page.waitForTimeout(4000);
  const data = await page.evaluate(() => {
    const text = (document.body.innerText || '').replace(/\s+/g, ' ');
    const title = (document.querySelector('h1')?.innerText || '').trim();
    const price = (text.match(/\d[\d\s]*₽/) || [''])[0].replace(/\s+/g, ' ').trim();
    const art = (text.match(/Арт\.?\s*\d+/i) || [''])[0];
    const pack =
      (text.match(/\d+\s*порци[^\s,]*(?:\s+по\s+\d+\s*г)?/i) || text.match(/\d+\s*шт/i) || [''])[0];
    const availability = /Нет в наличии/i.test(text)
      ? 'нет'
      : /В корзину|Купить/i.test(text)
        ? 'есть'
        : '';
    return { title, price, art, pack, availability, snippet: text.slice(0, 400) };
  });
  return {
    url,
    blocked: isBlocked(data.snippet) || data.title === 'Forbidden',
    status: resp && resp.status(),
    ...data,
  };
}

async function withProxyRetry(proxies, work) {
  const max = Math.max(proxies.length, 1) * 2;
  let lastErr;
  for (let attempt = 0; attempt < max; attempt++) {
    const proxy = pickProxy(proxies, attempt);
    console.log(`\n[proxy attempt ${attempt + 1}] ${proxy ? (proxy.mobile ? 'MOBILE ' : '') + proxy.label + ' (' + (proxy.source || '') + ')' : 'DIRECT'}`);
    let close;
    try {
      const opened = await openContext(proxy);
      close = opened.close;
      const page = await opened.context.newPage();
      const result = await work(page, proxy);
      if (result && result.blocked) {
        console.log('BLOCKED — switching proxy');
        await close();
        continue;
      }
      await close();
      return { ...result, proxyUsed: proxy ? proxy.label : 'direct' };
    } catch (e) {
      lastErr = e;
      console.log('ERR:', e.message);
      if (close) await close().catch(() => {});
    }
  }
  throw lastErr || new Error('All proxy attempts failed');
}

(async () => {
  const args = process.argv.slice(2);
  const cardsMode = args.includes('--cards');
  const urlIdx = args.indexOf('--url');
  const singleUrl = urlIdx >= 0 ? args[urlIdx + 1] : null;

  const proxies = loadProxies();
  const mobileN = proxies.filter((p) => p.mobile).length;
  console.log(`Loaded ${proxies.length} proxy pool(s) (${mobileN} mobile preferred first)`);
  for (const p of proxies) {
    console.log(`  - ${p.mobile ? 'MOBILE' : 'pool  '} ${p.source} @ ${p.label}`);
  }

  const productUrls = [
    'https://ng.nlstar.com/ru/product/74724',
    'https://ng.nlstar.com/ru/product/74822',
    'https://ng.nlstar.com/ru/product/74448',
    'https://ng.nlstar.com/ru/product/74707',
    'https://ng.nlstar.com/ru/product/74565',
    'https://ng.nlstar.com/ru/product/74100',
    'https://ng.nlstar.com/ru/product/74005',
    'https://ng.nlstar.com/ru/product/74122',
  ];

  if (singleUrl) {
    const r = await withProxyRetry(proxies, (page) => scrapeCard(page, singleUrl));
    console.log(JSON.stringify(r, null, 2));
    fs.writeFileSync(OUT, JSON.stringify(r, null, 2), 'utf8');
    return;
  }

  if (cardsMode) {
    const results = [];
    for (const url of productUrls) {
      try {
        const r = await withProxyRetry(proxies, (page) => scrapeCard(page, url));
        console.log(JSON.stringify(r, null, 2));
        results.push(r);
      } catch (e) {
        results.push({ url, error: e.message });
      }
    }
    fs.writeFileSync(OUT, JSON.stringify(results, null, 2), 'utf8');
    console.log('\nSaved', OUT);
    return;
  }

  const queries = [
    ['home', 'https://ng.nlstar.com/ru/'],
    ['novinka', 'https://ng.nlstar.com/ru/search?q=' + encodeURIComponent('новинка')],
    ['greenblend', 'https://ng.nlstar.com/ru/search?q=Greenblend'],
    ['cellcode', 'https://ng.nlstar.com/ru/search?q=Cellcode'],
    ['energy-diet', 'https://ng.nlstar.com/ru/search?q=Energy+Diet'],
  ];

  const results = [];
  // Use one proxy session for the whole listing pass; rotate only on block
  let proxyAttempt = 0;
  let page, proxy, close;
  const openFresh = async () => {
    if (close) await close().catch(() => {});
    proxy = pickProxy(proxies, proxyAttempt++);
    console.log(`\nUsing proxy: ${proxy ? (proxy.mobile ? 'MOBILE ' : '') + proxy.label + ' (' + (proxy.source || '') + ')' : 'DIRECT'}`);
    const opened = await openContext(proxy);
    close = opened.close;
    page = await opened.context.newPage();
  };
  await openFresh();

  for (const [label, url] of queries) {
    try {
      let r = await scrapeListing(page, label, url);
      if (r.blocked) {
        await openFresh();
        r = await scrapeListing(page, label, url);
      }
      console.log(`=== ${label} ===`, r.blocked ? 'BLOCKED' : `${(r.items || []).length} items`);
      if (!r.blocked) console.log(JSON.stringify(r.items, null, 2));
      results.push({ ...r, proxyUsed: proxy ? proxy.label : 'direct' });
    } catch (e) {
      console.error(label, e.message);
      results.push({ label, url, error: e.message });
      await openFresh();
    }
  }
  if (close) await close().catch(() => {});
  fs.writeFileSync(OUT, JSON.stringify(results, null, 2), 'utf8');
  console.log('\nSaved', OUT);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

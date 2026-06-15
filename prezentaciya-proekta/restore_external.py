"""Восстановить index.html с обычными <img src="...png"> + лоадером + ретраем на go()."""
import pathlib
HTML = pathlib.Path(r"C:\NL_produkt\prezentaciya-proekta\index.html")

tpl = '''<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>NL AutoPost — презентация проекта · Олег Симонов</title>
  <meta name="description" content="Презентация проекта NL AutoPost: автопостинг в 4 соцсети по расписанию." />
  <meta property="og:title" content="NL AutoPost — презентация проекта" />
  <meta property="og:description" content="Автопубликация в Telegram, ВК, Facebook, Instagram по расписанию." />
  <meta property="og:image" content="slides/01-cover.png" />
  <style>
    :root {
      --bg-0: #061310; --bg-1: #0a201a; --ink: #f4efe4; --muted: #9db5a8;
      --emerald: #37dca0; --gold: #e3b873; --stage-bg: #04100c;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: var(--stage-bg); font-family: -apple-system, "Segoe UI", system-ui, sans-serif; color: var(--ink); }
    .deck-viewport { position: fixed; inset: 0; overflow: hidden; background: var(--stage-bg); display: flex; align-items: center; justify-content: center; }
    .deck-stage { position: relative; width: 1920px; height: 1080px; transform-origin: 0 0; background: var(--bg-0); }
    .slide { position: absolute; inset: 0; opacity: 0; pointer-events: none; transition: opacity 0.4s ease; }
    .slide.active { opacity: 1; pointer-events: auto; }
    .slide img { width: 100%; height: 100%; object-fit: contain; display: block; }
    .nav { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); display: flex; gap: 12px; align-items: center; background: rgba(6,19,16,0.85); backdrop-filter: blur(10px); border: 1px solid rgba(244,239,228,0.12); border-radius: 999px; padding: 8px 14px; z-index: 100; }
    .nav button { background: var(--emerald); color: var(--bg-0); border: none; cursor: pointer; font-size: 20px; font-weight: 700; width: 40px; height: 40px; border-radius: 50%; display: flex; align-items: center; justify-content: center; }
    .nav button:hover { background: var(--gold); }
    .nav .counter { color: var(--muted); font-size: 14px; min-width: 60px; text-align: center; font-variant-numeric: tabular-nums; }
    .nav .counter strong { color: var(--ink); }
    .progress { position: fixed; top: 0; left: 0; height: 3px; background: var(--emerald); z-index: 100; transition: width 0.4s ease; width: 12.5%; }
    .hint { position: fixed; top: 16px; right: 16px; color: var(--muted); font-size: 12px; padding: 6px 12px; background: rgba(6,19,16,0.6); border: 1px solid rgba(244,239,228,0.12); border-radius: 999px; z-index: 100; }
    .hint kbd { background: rgba(255,255,255,0.1); padding: 1px 6px; border-radius: 4px; color: var(--ink); }
    .loading { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; background: var(--bg-0); color: var(--muted); z-index: 50; transition: opacity 0.5s; }
    .loading.hidden { opacity: 0; pointer-events: none; }
    .spinner { width: 36px; height: 36px; border: 3px solid rgba(55,220,160,0.2); border-top-color: var(--emerald); border-radius: 50%; animation: spin 0.8s linear infinite; margin-right: 16px; }
    @keyframes spin { to { transform: rotate(360deg); } }
    @media (max-width: 720px) { .hint { display: none; } }
  </style>
</head>
<body>
  <div class="loading" id="loading"><div class="spinner"></div>Загружаем слайды…</div>
  <div class="deck-viewport">
    <div class="deck-stage" id="stage">
      <div class="slide active"><img src="slides/01-cover.png" alt="Обложка" /></div>
      <div class="slide"><img src="slides/02-problem.png" alt="Проблема" /></div>
      <div class="slide"><img src="slides/03-user.png" alt="Пользователь" /></div>
      <div class="slide"><img src="slides/04-solution.png" alt="Решение" /></div>
      <div class="slide"><img src="slides/05-mvp.png" alt="MVP" /></div>
      <div class="slide"><img src="slides/06-plans.png" alt="Планы" /></div>
      <div class="slide"><img src="slides/07-tech.png" alt="Технологии" /></div>
      <div class="slide"><img src="slides/08-cta.png" alt="Спасибо" /></div>
    </div>
  </div>
  <div class="progress" id="progress"></div>
  <div class="hint">← <kbd>→</kbd> / пробел · <kbd>Esc</kbd> — на главную</div>
  <nav class="nav">
    <button id="prevBtn" aria-label="Назад">‹</button>
    <div class="counter"><strong id="cur">1</strong> / <span id="total">8</span></div>
    <button id="nextBtn" aria-label="Вперёд">›</button>
  </nav>
  <script>
    class Deck {
      constructor() {
        this.slides = Array.from(document.querySelectorAll('.slide'));
        this.current = 0;
        document.getElementById('total').textContent = this.slides.length;
        this.bind();
        this.fit();
        // Прелоад
        this.slides.forEach((s, i) => {
          const img = s.querySelector('img');
          const pre = new Image();
          pre.src = img.src;
        });
        // Лоадер убрать после загрузки 1-го
        const first = this.slides[0].querySelector('img');
        const done = () => document.getElementById('loading').classList.add('hidden');
        if (first.complete && first.naturalWidth > 0) done();
        else { first.onload = done; first.onerror = done; setTimeout(done, 5000); }
        window.addEventListener('resize', () => this.fit());
      }
      fit() {
        const stage = document.getElementById('stage');
        const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
        stage.style.transform = 'scale(' + s + ')';
      }
      bind() {
        document.getElementById('prevBtn').onclick = () => this.go(this.current - 1);
        document.getElementById('nextBtn').onclick = () => this.go(this.current + 1);
        document.addEventListener('keydown', (e) => {
          if (['ArrowRight','ArrowDown',' ','PageDown'].includes(e.key)) { e.preventDefault(); this.go(this.current + 1); }
          else if (['ArrowLeft','ArrowUp','PageUp'].includes(e.key))       { e.preventDefault(); this.go(this.current - 1); }
          else if (e.key === 'Home')  { e.preventDefault(); this.go(0); }
          else if (e.key === 'End')   { e.preventDefault(); this.go(this.slides.length - 1); }
          else if (e.key === 'Escape'){ window.location.href = '../index.html'; }
        });
        let x0 = null;
        document.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; }, {passive: true});
        document.addEventListener('touchend',   (e) => {
          if (x0 === null) return;
          const dx = e.changedTouches[0].clientX - x0;
          if (Math.abs(dx) > 50) this.go(this.current + (dx < 0 ? 1 : -1));
          x0 = null;
        });
        let wheelLock = 0;
        document.addEventListener('wheel', (e) => {
          if (Date.now() < wheelLock) return;
          wheelLock = Date.now() + 600;
          this.go(this.current + (e.deltaY > 0 ? 1 : -1));
        }, {passive: true});
      }
      go(n) {
        n = Math.max(0, Math.min(this.slides.length - 1, n));
        const target = this.slides[n].querySelector('img');
        // Если картинка не загрузилась — cache-buster + ретрай
        if (!target.complete || target.naturalWidth === 0) {
          target.src = target.src.split('?')[0] + '?r=' + Date.now();
        }
        this.slides[this.current].classList.remove('active');
        this.slides[n].classList.add('active');
        this.current = n;
        document.getElementById('cur').textContent = n + 1;
        document.getElementById('progress').style.width = ((n + 1) / this.slides.length * 100) + '%';
        history.replaceState(null, '', '#' + (n + 1));
      }
    }
    new Deck();
  </script>
</body>
</html>
'''
HTML.write_text(tpl, encoding="utf-8")
print(f"HTML restored: {len(tpl)//1024} KB, no base64")

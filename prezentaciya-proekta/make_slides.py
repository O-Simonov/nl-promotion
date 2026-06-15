"""Генерация 8 PNG-слайдов 1080x1350 для презентации о проекте NL AutoPost.
Стиль: глубокий изумрудный (как у prezentaciya.html) + Playfair Display / Manrope.
"""
from PIL import Image, ImageDraw, ImageFont
import os

# === ПАРАМЕТРЫ ХОЛСТА ===
W, H = 1080, 1350
OUT_DIR = r"C:\NL_produkt\prezentaciya-proekta\slides"
os.makedirs(OUT_DIR, exist_ok=True)

# === ПАЛИТРА (в тон prezentaciya.html) ===
BG_TOP    = (6, 19, 16)      # #061310
BG_BOT    = (10, 32, 26)     # #0a201a
EMERALD   = (55, 220, 160)   # #37dca0
EMERALD_D = (15, 118, 110)   # #0f766e
GOLD      = (227, 184, 115)  # #e3b873
INK       = (244, 239, 228)  # #f4efe4
MUTED     = (157, 181, 168)  # #9db5a8
LINE      = (244, 239, 228, 38)

# === ШРИФТЫ ===
# Используем системные, чтобы не зависеть от наличия Playfair
FONT_DISPLAY_CANDIDATES = [
    r"C:\Windows\Fonts\segoeuiz.ttf",   # Segoe UI Semibold
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\georgia.ttf",
    r"C:\Windows\Fonts\times.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
]
FONT_BODY_CANDIDATES = [
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arial.ttf",
    r"C:\Windows\Fonts\tahoma.ttf",
]

def find_font(candidates):
    for p in candidates:
        if os.path.exists(p):
            return p
    return None

DISPLAY = find_font(FONT_DISPLAY_CANDIDATES)
BODY    = find_font(FONT_BODY_CANDIDATES)

def font(path, size):
    return ImageFont.truetype(path, size) if path else ImageFont.load_default()

# === ФОНОВЫЙ ГРАДИЕНТ (изумрудный, по диагонали) ===
def make_bg():
    img = Image.new("RGB", (W, H), BG_TOP)
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(BG_TOP[0] * (1 - t) + BG_BOT[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOT[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOT[2] * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return img

# === ДЕКОР: тонкая изумрудная рамка + угловые акценты ===
def add_frame(img):
    d = ImageDraw.Draw(img, "RGBA")
    # внешняя тонкая линия
    d.rectangle([40, 40, W-40, H-40], outline=EMERALD + (90,), width=2)
    # угловые засечки
    L = 60
    for (cx, cy, dx, dy) in [(40,40,1,1), (W-40,40,-1,1), (40,H-40,1,-1), (W-40,H-40,-1,-1)]:
        d.line([(cx, cy), (cx + L*dx, cy)], fill=EMERALD, width=4)
        d.line([(cx, cy), (cx, cy + L*dy)], fill=EMERALD, width=4)
    return img

# === УТИЛИТЫ РИСОВАНИЯ ===
def wrap_text(draw, text, font_obj, max_w):
    lines = []
    for paragraph in text.split("\n"):
        if not paragraph:
            lines.append("")
            continue
        words = paragraph.split()
        cur = ""
        for w in words:
            test = (cur + " " + w).strip()
            if draw.textlength(test, font=font_obj) <= max_w:
                cur = test
            else:
                if cur:
                    lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
    return lines

def draw_text_block(img, text, x, y, w, font_obj, fill=INK, line_h=None):
    d = ImageDraw.Draw(img)
    lines = wrap_text(d, text, font_obj, w)
    if line_h is None:
        line_h = int(font_obj.size * 1.35)
    for i, line in enumerate(lines):
        d.text((x, y + i * line_h), line, font=font_obj, fill=fill)
    return y + len(lines) * line_h

def measure_block(text, font_obj, w):
    d = ImageDraw.Draw(Image.new("RGB", (1,1)))
    lines = wrap_text(d, text, font_obj, w)
    line_h = int(font_obj.size * 1.35)
    return len(lines) * line_h

def draw_pill(img, text, x, y, font_obj, fill=EMERALD, text_color=BG_TOP, pad_x=22, pad_y=10):
    d = ImageDraw.Draw(img, "RGBA")
    tw = d.textlength(text, font=font_obj)
    th = font_obj.size
    w = tw + pad_x * 2
    h = th + pad_y * 2
    d.rounded_rectangle([x, y, x + w, y + h], radius=h//2, fill=fill)
    d.text((x + pad_x, y + pad_y), text, font=font_obj, fill=text_color)
    return x + w + 12, y  # следующая позиция

def draw_divider(img, y, x1=80, x2=W-80):
    d = ImageDraw.Draw(img, "RGBA")
    d.line([(x1, y), (x2, y)], fill=EMERALD + (160,), width=2)

def draw_number(img, n, x, y):
    d = ImageDraw.Draw(img)
    f = font(DISPLAY, 140)
    d.text((x, y), f"{n:02d}", font=f, fill=EMERALD)

# === СЛАЙДЫ ===
def slide_01_cover():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    # верхний бейдж
    draw_pill(img, "КЕЙС · 2026", 80, 110, font(BODY, 22), fill=EMERALD)
    # заголовок
    f_title = font(DISPLAY, 96)
    d.text((80, 230), "NL AutoPost", font=f_title, fill=INK)
    # золотая подсветка
    d.text((80, 330), "как собрать", font=font(DISPLAY, 64), fill=GOLD)
    d.text((80, 400), "автопостинг в 4 соцсети", font=font(DISPLAY, 64), fill=INK)
    d.text((80, 470), "и не трогать его неделями", font=font(DISPLAY, 64), fill=INK)
    # разделитель
    draw_divider(img, 620)
    # тезисы
    f_body = font(BODY, 26)
    draw_text_block(img, "• 4 бота: Telegram, ВК, Facebook, Instagram", 80, 670, W-160, f_body, MUTED)
    draw_text_block(img, "• Расписание в Windows Task Scheduler", 80, 715, W-160, f_body, MUTED)
    draw_text_block(img, "• Очередь + бэклог пополняется сам", 80, 760, W-160, f_body, MUTED)
    draw_text_block(img, "• Сайт-хаб на Netlify", 80, 805, W-160, f_body, MUTED)
    draw_text_block(img, "• Партнёр NL поднимает свою копию за вечер", 80, 850, W-160, f_body, MUTED)
    # подвал
    draw_divider(img, H-200)
    d.text((80, H-160), "Олег Симонов", font=font(DISPLAY, 38), fill=INK)
    d.text((80, H-115), "независимый партнёр NL International", font=font(BODY, 22), fill=MUTED)
    d.text((80, H-78), "github.com/O-Simonov/nl-promotion", font=font(BODY, 20), fill=EMERALD)
    img.save(os.path.join(OUT_DIR, "01-cover.png"), "PNG", optimize=True)

def slide_02_problem():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "ПРОБЛЕМА", 80, 110, font(BODY, 22), fill=GOLD, text_color=BG_TOP)
    d.text((80, 200), "30–60 минут", font=font(DISPLAY, 110), fill=EMERALD)
    d.text((80, 330), "каждый день", font=font(DISPLAY, 80), fill=INK)
    d.text((80, 420), "уходит на ручной постинг", font=font(DISPLAY, 50), fill=MUTED)
    draw_divider(img, 560)
    f_body = font(BODY, 28)
    bullets = [
        "✗  4 соцсети — 4 интерфейса, разные правила",
        "✗  Пропустил день — упал охват, пошли отписки",
        "✗  Платные SMM-сервисы не дружат с ВК+IG",
        "✗  Платить подписку при малом товарообороте — дорого",
        "✗  Партнёры NL всё повторяют вручную каждый день",
    ]
    y = 620
    for b in bullets:
        d.text((80, y), b, font=f_body, fill=INK)
        y += 70
    img.save(os.path.join(OUT_DIR, "02-problem.png"), "PNG", optimize=True)

def slide_03_user():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "ДЛЯ КОГО", 80, 110, font(BODY, 22), fill=GOLD, text_color=BG_TOP)
    d.text((80, 200), "Пользователь", font=font(DISPLAY, 80), fill=INK)
    draw_divider(img, 330)
    # 2 карточки
    def card(x, y, w, h, badge, title, body, accent):
        d = ImageDraw.Draw(img, "RGBA")
        d.rounded_rectangle([x, y, x+w, y+h], radius=24, fill=(14, 42, 34, 220), outline=accent+(180,), width=2)
        d.text((x+30, y+25), badge, font=font(BODY, 20), fill=accent)
        d.text((x+30, y+70), title, font=font(DISPLAY, 38), fill=INK)
        d.text((x+30, y+135), body, font=font(BODY, 22), fill=MUTED)
    card(80, 380, W-160, 320, "ОСНОВНОЙ", "Дистрибьютор NL", "Ведёт 4 соцсети. Хочет публиковать\nбез ежедневной ручной работы,\nне теряя охват и продажи.", EMERALD)
    card(80, 730, W-160, 320, "ДОПОЛНИТЕЛЬНЫЙ", "Партнёр NL", "Клонирует репо, подставляет\nсвои реф-ссылки через мастер\nи получает ту же автоматизацию.", GOLD)
    img.save(os.path.join(OUT_DIR, "03-user.png"), "PNG", optimize=True)

def slide_04_solution():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "РЕШЕНИЕ", 80, 110, font(BODY, 22), fill=GOLD, text_color=BG_TOP)
    d.text((80, 200), "Что делает система", font=font(DISPLAY, 70), fill=INK)
    draw_divider(img, 320)
    # Вход
    f_section = font(DISPLAY, 34)
    f_body = font(BODY, 24)
    d.text((80, 380), "ВХОД", font=f_section, fill=EMERALD)
    d.text((80, 430), "• Папка с постами: queue/ и backlog/", font=f_body, fill=INK)
    d.text((80, 470), "• Файлы .txt + картинка .png того же имени", font=f_body, fill=INK)
    d.text((80, 510), "• Генератор обложек Make-PostImage.ps1", font=f_body, fill=INK)
    # стрелка
    d.polygon([(W//2-25, 580), (W//2+25, 580), (W//2, 615)], fill=EMERALD)
    # Выход
    d.text((80, 650), "ВЫХОД", font=f_section, fill=EMERALD)
    d.text((80, 700), "• Пост в Telegram, ВК, Facebook, Instagram", font=f_body, fill=INK)
    d.text((80, 740), "• С реф-ссылкой и хэштегами", font=f_body, fill=INK)
    d.text((80, 780), "• Сдвиг публикации 1 час между сетями", font=f_body, fill=INK)
    # вторая стрелка
    d.polygon([(W//2-25, 850), (W//2+25, 850), (W//2, 885)], fill=EMERALD)
    # результат
    d.text((80, 920), "РЕЗУЛЬТАТ", font=f_section, fill=EMERALD)
    d.text((80, 970), "• 4 поста в день без ручных действий", font=f_body, fill=GOLD)
    d.text((80, 1010), "• Лог всех публикаций в logs/", font=f_body, fill=GOLD)
    d.text((80, 1050), "• Сайт-хаб с каталогом на Netlify", font=f_body, fill=GOLD)
    img.save(os.path.join(OUT_DIR, "04-solution.png"), "PNG", optimize=True)

def slide_05_mvp():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "ЧТО РАБОТАЕТ СЕЙЧАС", 80, 110, font(BODY, 22), fill=EMERALD, text_color=BG_TOP)
    d.text((80, 200), "MVP", font=font(DISPLAY, 90), fill=INK)
    d.text((80, 305), "что уже в проде", font=font(DISPLAY, 44), fill=MUTED)
    draw_divider(img, 410)
    f_body = font(BODY, 26)
    items = [
        ("✓", "4 бота (TG, ВК, FB, IG) на PowerShell"),
        ("✓", "Расписание 09:00 → 10:00 → 11:00 → 12:00 → 14:00"),
        ("✓", "Автопополнение очереди из backlog (≤8 постов)"),
        ("✓", "Генератор обложек: 12 категорий"),
        ("✓", "Сайт-хаб на Netlify: 4 страницы"),
        ("✓", "News-Watch: новости NL из @nl25_news (08:30+20:00)"),
        ("✓", "Setup-Partner.ps1: мастер подстановки реф-ссылок"),
        ("✓", "Напоминание о ротации Meta-токена"),
    ]
    y = 470
    for mark, txt in items:
        d.text((100, y), mark, font=font(DISPLAY, 36), fill=EMERALD)
        d.text((160, y + 6), txt, font=f_body, fill=INK)
        y += 70
    img.save(os.path.join(OUT_DIR, "05-mvp.png"), "PNG", optimize=True)

def slide_06_plans():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "ПЛАНЫ", 80, 110, font(BODY, 22), fill=GOLD, text_color=BG_TOP)
    d.text((80, 200), "Что дальше", font=font(DISPLAY, 90), fill=INK)
    draw_divider(img, 330)
    f_body = font(BODY, 26)
    items = [
        ("YouTube Shorts", "вертикальные анонсы (генератор уже умеет mp4)"),
        ("TikTok",        "после стабилизации Meta-стека"),
        ("A/B-тесты",     "обложек: 2 варианта → авто-выбор лучшего по CTR"),
        ("Адаптивное время", "постинга по статистике охватов"),
        ("Mini-CRM",      "кто подписался, кто купил"),
        ("Веб-админка",   "подготовка постов без PowerShell"),
    ]
    y = 400
    for title, body in items:
        d.ellipse([100, y+12, 130, y+42], outline=GOLD, width=3)
        d.text((155, y), title, font=font(DISPLAY, 34), fill=INK)
        d.text((155, y + 50), body, font=f_body, fill=MUTED)
        y += 130
    img.save(os.path.join(OUT_DIR, "06-plans.png"), "PNG", optimize=True)

def slide_07_tech():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "СТЕК", 80, 110, font(BODY, 22), fill=EMERALD, text_color=BG_TOP)
    d.text((80, 200), "Технологии", font=font(DISPLAY, 80), fill=INK)
    draw_divider(img, 330)
    # 2 колонки
    f_label = font(BODY, 22)
    f_value = font(DISPLAY, 32)
    rows = [
        ("Язык",          "PowerShell 7+"),
        ("Планировщик",   "Windows Task Scheduler"),
        ("API",           "Telegram · VK Open · Meta Graph"),
        ("Картинки",      "ImgBB (бесплатный хостинг)"),
        ("Сайт",          "Статический HTML + Netlify"),
        ("Деплой",        "GitHub → Netlify (continuous)"),
        ("Хранилище",     "Файловая система (queue/, backlog/, sent/)"),
        ("БД",            "Нет. Только .json конфиги и .txt посты"),
    ]
    col_x = [80, W//2 + 20]
    row_h = 130
    y0 = 380
    for i, (k, v) in enumerate(rows):
        col = i % 2
        row = i // 2
        x = col_x[col]
        y = y0 + row * row_h
        d.text((x, y), k.upper(), font=f_label, fill=GOLD)
        d.text((x, y + 35), v, font=f_value, fill=INK)
    img.save(os.path.join(OUT_DIR, "07-tech.png"), "PNG", optimize=True)

def slide_08_cta():
    img = make_bg()
    add_frame(img)
    d = ImageDraw.Draw(img)
    draw_pill(img, "ИТОГО", 80, 110, font(BODY, 22), fill=GOLD, text_color=BG_TOP)
    d.text((80, 200), "Спасибо", font=font(DISPLAY, 140), fill=INK)
    d.text((80, 380), "за внимание", font=font(DISPLAY, 64), fill=MUTED)
    draw_divider(img, 500)
    # Что забрать
    f_body = font(BODY, 26)
    d.text((80, 560), "✓  Готовое решение для 4 соцсетей", font=f_body, fill=INK)
    d.text((80, 615), "✓  Код в open source — бери и адаптируй", font=f_body, fill=INK)
    d.text((80, 670), "✓  Партнёрам NL — мастер настройки за 5 минут", font=f_body, fill=INK)
    # Контакты
    draw_divider(img, 800)
    d.text((80, 860), "Олег Симонов · независимый партнёр NL", font=font(DISPLAY, 38), fill=INK)
    f_contacts = font(BODY, 24)
    d.text((80, 940), "github.com/O-Simonov/nl-promotion", font=f_contacts, fill=EMERALD)
    d.text((80, 985), "t.me/Simka1969_nl — мой Telegram-канал", font=f_contacts, fill=EMERALD)
    d.text((80, 1030), "t.me/Simka1969 — личка", font=f_contacts, fill=EMERALD)
    d.text((80, 1075), "oleg-nl.netlify.app — сайт-хаб", font=f_contacts, fill=EMERALD)
    img.save(os.path.join(OUT_DIR, "08-cta.png"), "PNG", optimize=True)

# === ЗАПУСК ===
if __name__ == "__main__":
    slide_01_cover()
    slide_02_problem()
    slide_03_user()
    slide_04_solution()
    slide_05_mvp()
    slide_06_plans()
    slide_07_tech()
    slide_08_cta()
    print("OK, 8 slides generated:")
    for f in sorted(os.listdir(OUT_DIR)):
        if f.endswith(".png"):
            p = os.path.join(OUT_DIR, f)
            sz = os.path.getsize(p)
            print(f"  {f}  {sz//1024} KB")

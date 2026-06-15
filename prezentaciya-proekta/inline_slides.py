"""Встроить слайды как base64 data: URL прямо в HTML.
100% обход любых CDN-проблем: ассет едет внутри HTML."""
import base64, os, re, pathlib

SLIDES = pathlib.Path(r"C:\NL_produkt\prezentaciya-proekta\slides")
HTML   = pathlib.Path(r"C:\NL_produkt\prezentaciya-proekta\index.html")

# Соберём все webp в base64
b64 = {}
for f in sorted(SLIDES.glob("*.webp")):
    name = f.stem
    data = base64.b64encode(f.read_bytes()).decode("ascii")
    b64[name] = data
    print(f"  {f.name}  -> {len(data)//1024} KB b64")

src = HTML.read_text(encoding="utf-8")
# Заменяем srcset/src на data: URL
for name, data in b64.items():
    src = src.replace(f'srcset="slides/{name}.webp"',
                      f'srcset="data:image/webp;base64,{data}"')
    src = src.replace(f'src="slides/{name}.png"',
                      f'src="data:image/webp;base64,{data}"')

HTML.write_text(src, encoding="utf-8")
print(f"\nHTML final: {len(src)//1024} KB")

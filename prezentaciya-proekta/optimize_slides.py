"""Оптимизация PNG: уменьшить размер, пересохранить без потери качества."""
from PIL import Image
import os

SLIDES = r"C:\NL_produkt\prezentaciya-proekta\slides"
for f in sorted(os.listdir(SLIDES)):
    if not f.endswith(".png"):
        continue
    p = os.path.join(SLIDES, f)
    img = Image.open(p).convert("RGB")  # RGB без альфа-канала
    # PNG palette-quantize до 256 цветов: сильно сжимает
    img_p = img.quantize(colors=192, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    out = p  # перезаписать
    img_p.save(out, "PNG", optimize=True)
    old = os.path.getsize(p)
    print(f"  {f}  -> {old//1024} KB")

"""Перегенерировать слайды в WebP (lossless). WebP в 3-5 раз легче PNG."""
from PIL import Image
import os, glob

SLIDES = r"C:\NL_produkt\prezentaciya-proekta\slides"
for f in sorted(glob.glob(os.path.join(SLIDES, "*.png"))):
    img = Image.open(f).convert("RGB")
    out = os.path.splitext(f)[0] + ".webp"
    img.save(out, "WEBP", lossless=True, method=6)
    p_size = os.path.getsize(f) // 1024
    w_size = os.path.getsize(out) // 1024
    print(f"  {os.path.basename(f)}  PNG={p_size}KB  WebP={w_size}KB  -{100 - 100*w_size//p_size}%")

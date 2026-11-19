#!/usr/bin/env python3
"""Disegna la grafica accessoria: bandiere delle sette potenze, pergamena, icona e schermata di caricamento.

Uso: python3 tools/costruisci_grafica.py
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy import ndimage as ndi

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
W, H = 240, 160


def bande_o(cols):
    im = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(im)
    n = len(cols)
    for i, c in enumerate(cols):
        d.rectangle([0, round(i * H / n), W, round((i + 1) * H / n)], fill=c)
    return im


def bande_v(cols):
    im = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(im)
    n = len(cols)
    for i, c in enumerate(cols):
        d.rectangle([round(i * W / n), 0, round((i + 1) * W / n), H], fill=c)
    return im


def bandiere():
    out = {}
    out[0] = bande_o(['#1a1a1a', '#f2c230'])                              # Austria-Ungheria: nero e oro degli Asburgo
    # Regno Unito
    im = Image.new('RGB', (W * 2, H * 2), '#1f3a7a')
    d = ImageDraw.Draw(im)
    w, h = W * 2, H * 2
    d.line([0, 0, w, h], fill='white', width=58)
    d.line([0, h, w, 0], fill='white', width=58)
    d.line([0, 0, w, h], fill='#c8102e', width=20)
    d.line([0, h, w, 0], fill='#c8102e', width=20)
    d.rectangle([w / 2 - 50, 0, w / 2 + 50, h], fill='white')
    d.rectangle([0, h / 2 - 50, w, h / 2 + 50], fill='white')
    d.rectangle([w / 2 - 30, 0, w / 2 + 30, h], fill='#c8102e')
    d.rectangle([0, h / 2 - 30, w, h / 2 + 30], fill='#c8102e')
    out[1] = im.resize((W, H), Image.LANCZOS)
    out[2] = bande_v(['#1f3f94', '#f4f4f0', '#d1232a'])                   # Francia
    out[3] = bande_o(['#151515', '#f4f4f0', '#c8202c'])                   # Impero tedesco
    # Regno d'Italia con lo scudo sabaudo
    im = bande_v(['#1f8a3a', '#f4f4f0', '#cf2a2a']).resize((W * 2, H * 2))
    d = ImageDraw.Draw(im)
    cx, cy = W, H
    d.polygon([(cx - 44, cy - 52), (cx + 44, cy - 52), (cx + 44, cy + 14), (cx, cy + 62), (cx - 44, cy + 14)], fill='#1f3f94')
    d.polygon([(cx - 34, cy - 42), (cx + 34, cy - 42), (cx + 34, cy + 10), (cx, cy + 48), (cx - 34, cy + 10)], fill='#cf2a2a')
    d.rectangle([cx - 9, cy - 42, cx + 9, cy + 40], fill='white')
    d.rectangle([cx - 34, cy - 12, cx + 34, cy + 6], fill='white')
    out[4] = im.resize((W, H), Image.LANCZOS)
    out[5] = bande_o(['#f4f4f0', '#22408f', '#c8202c'])                   # Impero russo
    # Impero ottomano
    im = Image.new('RGB', (W * 2, H * 2), '#c8102e')
    d = ImageDraw.Draw(im)
    cx, cy = W * 0.84, H
    d.ellipse([cx - 82, cy - 82, cx + 82, cy + 82], fill='white')
    d.ellipse([cx - 82 + 40, cy - 66, cx + 82 + 8, cy + 66], fill='#c8102e')
    sx, sy, r = cx + 96, cy, 34
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5 + math.pi / 2
        rr = r if k % 2 == 0 else r * 0.4
        pts.append((sx + math.cos(a + math.pi) * rr, sy + math.sin(a + math.pi) * rr))
    d.polygon(pts, fill='white')
    out[6] = im.resize((W, H), Image.LANCZOS)
    os.makedirs(R + '/assets/bandiere', exist_ok=True)
    for k, im in out.items():
        # un filo scuro attorno, come una bandierina di stoffa
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, W - 1, H - 1], outline='#2a2118', width=3)
        im.save(R + '/assets/bandiere/b%d.png' % k)


def rumore(shape, scala, seme):
    g = np.random.default_rng(seme)
    a = g.standard_normal((shape[0] // scala + 3, shape[1] // scala + 3))
    a = ndi.zoom(a, scala, order=3)[:shape[0], :shape[1]]
    return a / (np.abs(a).max() + 1e-9)


def pergamena():
    n = 768
    g = np.random.default_rng(3)
    a = rumore((n, n), 160, 1) * 0.5 + rumore((n, n), 40, 2) * 0.3 + rumore((n, n), 9, 3) * 0.2
    fibra = ndi.gaussian_filter(g.standard_normal((n, n)), (0.5, 6.0))
    base = np.ones((n, n, 3), np.float32) * np.array([233, 221, 190], np.float32)
    base *= (1 + a[..., None] * 0.07 + fibra[..., None] * 0.05)
    macchie = np.clip(rumore((n, n), 120, 9), 0.25, 1) - 0.25
    base -= macchie[..., None] * np.array([20, 26, 38], np.float32)
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).save(R + '/assets/misc/pergamena.jpg', quality=88)
    # panno verde da tavolo delle conferenze
    a = rumore((n, n), 90, 5) * 0.5 + g.standard_normal((n, n)) * 0.5
    base = np.ones((n, n, 3), np.float32) * np.array([24, 52, 40], np.float32)
    base *= (1 + a[..., None] * 0.10)
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).save(R + '/assets/misc/panno.jpg', quality=86)


def titoli():
    script = ImageFont.truetype(R + '/assets/fonts/PinyonScript-Regular.ttf', 150)
    serif = ImageFont.truetype(R + '/assets/fonts/OldStandard-Bold.ttf', 30)
    # schermata di caricamento
    im = Image.new('RGB', (820, 360), '#111816')
    d = ImageDraw.Draw(im)
    d.text((410, 150), 'Diplomacy', font=script, fill='#d9bd72', anchor='mm')
    d.line([230, 250, 590, 250], fill='#8a733c', width=2)
    d.text((410, 290), 'EUROPA  1901', font=serif, fill='#cfc4a4', anchor='mm')
    im.save(R + '/assets/misc/caricamento.png')
    # icona
    ic = Image.new('RGB', (512, 512), '#183328')
    d = ImageDraw.Draw(ic)
    d.ellipse([28, 28, 484, 484], outline='#c9a85a', width=10)
    d.ellipse([52, 52, 460, 460], outline='#8a733c', width=3)
    big = ImageFont.truetype(R + '/assets/fonts/PinyonScript-Regular.ttf', 330)
    d.text((262, 268), 'D', font=big, fill='#e3c97e', anchor='mm')
    ic.save(R + '/assets/misc/icona.png')


if __name__ == '__main__':
    bandiere()
    pergamena()
    titoli()
    print('grafica pronta')

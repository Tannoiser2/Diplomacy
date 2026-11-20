# Toglie dal tabellone originale le scritte inglesi e ci stampa i nomi italiani dell'interfaccia.
# Uso: python3 scritte.py <scansione originale> <base.jpg da scrivere> [cartella per i controlli]
import sys, math, json, cv2, numpy as np
from PIL import Image, ImageDraw, ImageFont
from etichette import E, R, EN, F as FORZA

SCAN, OUT = sys.argv[1], sys.argv[2]
DBG = sys.argv[3] if len(sys.argv) > 3 else None
import os
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../assets/fonts/') if len(sys.argv) <= 4 else sys.argv[4]
im = cv2.imread(SCAN)
H, W = im.shape[:2]
gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY).astype(np.float32)
fondo = cv2.medianBlur(cv2.cvtColor(im, cv2.COLOR_BGR2GRAY), 31).astype(np.float32)
diff = gray - fondo
# la piega orizzontale del tabellone (righe 1250-1265) non deve legarsi alle lettere che attraversa
for r in range(1250, 1266):
    t = (r - 1249) / 17.0
    diff[r] = diff[1249] * (1 - t) + diff[1266] * t
# chiare le scritte di terra sui fondi scuri, scure su quelli chiari della Russia; scuri mari e potenze
SCURE = {"FIN", "STP", "LVN", "MOS", "UKR", "SEV", "WAR"}
stelle = [(x * 2, y * 2) for x, y in json.load(open('stelle.json')).values()]


def componenti(b, ox, oy):
    n, cc, st, cen = cv2.connectedComponentsWithStats(b.astype(np.uint8), 8)
    out = []
    for i in range(1, n):
        x, y, w, h, a = st[i]
        out.append({'i': i, 'x': x + ox, 'y': y + oy, 'w': w, 'h': h, 'a': a, 'cx': cen[i][0] + ox, 'cy': cen[i][1] + oy})
    return n, cc, out


def lettera(c, bw, bh, ox, oy, hmax=44, ruotata=False):
    if c['x'] - ox <= 0 or c['y'] - oy <= 0 or c['x'] - ox + c['w'] >= bw or c['y'] - oy + c['h'] >= bh:
        return False          # tocca il bordo della finestra: è un confine o una costa, non una lettera
    if not ruotata and any(c['x'] - 3 <= sx <= c['x'] + c['w'] + 3 and c['y'] - 3 <= sy <= c['y'] + c['h'] + 3 for sx, sy in stelle):
        return False
    return c['h'] <= hmax and c['a'] >= 4 and c['a'] / float(c['w'] * c['h']) > 0.06


ALT = {'t': 15.5, 'm': 19.0, 'p': 23.0, 'c': 10.5}          # altezza delle maiuscole stampate, per stile


def larghezza_inglese(righe, stile):
    """Quanto è larga la scritta inglese, rifatta con un carattere simile alla stessa altezza."""
    w = 0
    for t in righe:
        _, l, _ = disegna_riga(t, stile, ALT[stile], 1.0)
        w = max(w, l)
    return w * (1.12 if stile == 'p' else 1.0)


def maschera_riga(cx, cy, righe, stile, polarita, en):
    """Le lettere di una scritta orizzontale, dentro il riquadro stimato dalla scritta inglese."""
    hc = ALT[stile]
    w = larghezza_inglese(en, stile) + 2.6 * hc + 30
    h = len(en) * 1.75 * hc + 0.9 * hc + 10
    ox, oy = int(max(0, cx - w / 2)), int(max(0, cy - h / 2))
    x1, y1 = int(min(W, cx + w / 2)), int(min(H, cy + h / 2))
    meglio = None
    for pol in polarita:
        b = pol * diff[oy:y1, ox:x1] > 16
        n, cc, comp = componenti(b, ox, oy)
        L = [c for c in comp if lettera(c, x1 - ox, y1 - oy, ox, oy, hmax=1.9 * hc) and (c['h'] >= 0.3 * hc or c['a'] >= 4)]
        # lettere fuse con un confine o con la piega: troppo alte, ma dentro la finestra. Se ne tiene
        # solo la fascia della scritta (dove stanno le altre lettere)
        alte = [c for c in comp if c['h'] > 1.9 * hc or not lettera(c, x1 - ox, y1 - oy, ox, oy, hmax=10 * hc)]
        punti = sum(c['a'] for c in L)
        if L and (meglio is None or punti > meglio[0]):
            m = np.zeros((H, W), np.uint8)
            m[oy:y1, ox:x1][np.isin(cc, [c['i'] for c in L])] = 1
            if alte:
                fascia = np.zeros(y1 - oy, bool)
                for c in L:
                    if c['h'] >= 0.5 * hc:
                        fascia[max(0, c['y'] - oy - 2):c['y'] - oy + c['h'] + 2] = True
                lx0 = min(c['x'] for c in L) - ox - 2; lx1 = max(c['x'] + c['w'] for c in L) - ox + 2
                colonne = np.zeros(x1 - ox, bool); colonne[max(0, lx0):lx1] = True
                sel = np.isin(cc, [c['i'] for c in alte]) & fascia[:, None] & colonne[None, :]
                m[oy:y1, ox:x1][sel] = 1
            meglio = (punti, m, pol, L)
    return meglio


def maschera_rett(cx, cy, lun, spe, ang):
    """Le lettere dentro un rettangolo ruotato (scritte piccole o oblique, targhette)."""
    # attorno al centro, su una tela con margine: le targhette stanno sul bordo dell'immagine
    P = 300
    M = cv2.getRotationMatrix2D((cx + P, cy + P), ang, 1.0)          # porta la scritta in orizzontale
    ruota = cv2.warpAffine(cv2.copyMakeBorder(diff, P, P, P, P, cv2.BORDER_CONSTANT, value=0), M, (W + 2 * P, H + 2 * P), flags=cv2.INTER_LINEAR)
    ox, oy = int(cx + P - lun / 2), int(cy + P - spe / 2)
    bw, bh = int(lun), int(spe)
    meglio = None
    for pol in (1, -1):
        b = pol * ruota[oy:oy + bh, ox:ox + bw] > 18
        n, cc, comp = componenti(b, ox, oy)
        L = [c for c in comp if lettera(c, bw, bh, ox, oy, hmax=spe, ruotata=True)]
        punti = sum(c['a'] for c in L)
        if L and (meglio is None or punti > meglio[0]):
            m = np.zeros((H + 2 * P, W + 2 * P), np.uint8)
            m[oy:oy + bh, ox:ox + bw][np.isin(cc, [c['i'] for c in L])] = 1
            Mi = cv2.getRotationMatrix2D((cx + P, cy + P), -ang, 1.0)
            m = cv2.warpAffine(m, Mi, (W + 2 * P, H + 2 * P), flags=cv2.INTER_NEAREST)[P:P + H, P:P + W]
            meglio = (punti, m, pol, L)
    return meglio


def colore(m, pol):
    if isinstance(m, tuple):
        mm = np.zeros((H, W), np.uint8); mm[m] = 1; m = mm
    nucleo = cv2.erode(m, np.ones((2, 2), np.uint8))
    if nucleo.sum() < 10:
        nucleo = m
    px = im[nucleo > 0].astype(np.float32)
    g = px.mean(1)
    sel = px[g >= np.percentile(g, 60)] if pol > 0 else px[g <= np.percentile(g, 40)]
    c = np.median(sel, 0)[::-1]
    # la scansione ha aloni colorati ai bordi delle lettere: si toglie metà della saturazione
    c = c * 0.5 + c.mean() * 0.5
    return tuple(int(v) for v in c)        # RGB


def altezza(lettere, tipica=None):
    hs = sorted(c['h'] for c in lettere if c['h'] >= 6)
    h = float(np.percentile(hs, 85)) if hs else 18.0
    return h if tipica is None else min(max(h, tipica * 0.85), tipica * 1.15)


F = {k: ImageFont.truetype(FONTS + f, 100) for k, f in (('r', 'OldStandard-Regular.ttf'), ('b', 'OldStandard-Bold.ttf'), ('i', 'OldStandard-Italic.ttf'))}
def cap_ratio(k):
    b = F[k].getbbox('H')
    return (b[3] - b[1]) / 100.0
CAP = {k: cap_ratio(k) for k in F}


def disegna_riga(testo, stile, hcap, scala):
    """Una riga come immagine RGBA (bianca) a 4x; restituisce l'immagine e la larghezza utile."""
    S = 4
    if stile in ('t', 'q'):
        k, piccolo = 'r', 0.80
    elif stile == 'p':
        k, piccolo = 'r', 1.0
    else:
        k, piccolo = 'i', 1.0
    sz = hcap / CAP[k] * scala * S
    fG = ImageFont.truetype(FONTS + {'r': 'OldStandard-Regular.ttf', 'i': 'OldStandard-Italic.ttf'}[k], max(8, int(sz)))
    fP = ImageFont.truetype(FONTS + {'r': 'OldStandard-Regular.ttf', 'i': 'OldStandard-Italic.ttf'}[k], max(8, int(sz * piccolo)))
    track = {'t': 0.06, 'q': 0.08, 'p': 0.22, 'm': 0.07, 'c': 0.02}[stile] * sz
    pezzi = []
    if stile in ('t', 'q'):
        inizio = True
        for ch in testo:
            if ch in " -(":
                pezzi.append((ch, fG)); inizio = True; continue
            pezzi.append((ch.upper(), fG if inizio else fP)); inizio = False
    elif stile == 'p':
        pezzi = [(ch.upper(), fG) for ch in testo]
    else:
        pezzi = [(ch, fG) for ch in testo]
    larg = sum(f.getlength(ch) + track for ch, f in pezzi) - track
    asc = fG.getmetrics()[0]
    img = Image.new('L', (int(larg + 8 * S), int(sz * 1.6)), 0)
    d = ImageDraw.Draw(img)
    x = 4 * S
    for ch, f in pezzi:
        d.text((x, asc - f.getmetrics()[0] + int(sz * 0.1)), ch, font=f, fill=255)
        x += f.getlength(ch) + track
    bb = img.getbbox()
    return img, larg / S, sz / S


def blocco(righe, stile, hcap, maxw):
    """Più righe centrate, ristrette se non entrano nella larghezza disponibile."""
    scala = 1.0
    for _ in range(12):
        imgs = [disegna_riga(t[1:], 'c', hcap * 0.8, scala) if t.startswith('~') else disegna_riga(t, stile, hcap, scala) for t in righe]
        w = max(i[1] for i in imgs)
        if w <= maxw or scala < 0.72:
            break
        scala *= 0.95
    S = 4
    passo = int(hcap * scala * 1.75 * S)
    Wb = max(i[0].width for i in imgs)
    Hb = imgs[0][0].height + passo * (len(imgs) - 1)
    tela = Image.new('L', (Wb, Hb), 0)
    for k, (im_, _, _) in enumerate(imgs):
        tela.paste(im_, ((Wb - im_.width) // 2, k * passo))
    bb = tela.getbbox()
    return tela.crop(bb)


def stampa(base, testo_img, cx, cy, ang, rgb, pol, ombra=True):
    S = 4
    t = testo_img.rotate(-ang, resample=Image.BICUBIC, expand=True)
    t = t.resize((max(1, t.width // S), max(1, t.height // S)), Image.LANCZOS)
    x0, y0 = int(round(cx - t.width / 2)), int(round(cy - t.height / 2))
    if ombra:
        # l'ombra o l'alone che ha la stampa originale, del colore opposto alla scritta
        alone = t.filter(__import__('PIL.ImageFilter', fromlist=['x']).GaussianBlur(1.2))
        col = (20, 16, 12) if pol > 0 else (235, 228, 210)
        a = alone.point(lambda v: int(v * (0.55 if pol > 0 else 0.35)))
        base.paste(Image.new('RGB', t.size, col), (x0 + (1 if pol > 0 else 0), y0 + (1 if pol > 0 else 0)), a)
    base.paste(Image.new('RGB', t.size, rgb), (x0, y0), t)


lavori = []
tutta = np.zeros((H, W), np.uint8)
for s, x, y, st, righe in E:
    cx, cy = x * 2, y * 2
    pol = (-1,) if (st in ('m', 'p') or s in SCURE) else (1,)
    r = maschera_riga(cx, cy, righe, st, pol, EN[s])
    if r is None:
        print('NON TROVATA', s); continue
    _, m, pol, L = r
    ys, xs = np.nonzero(m)
    m = (ys, xs)
    lavori.append(dict(s=s, st=st, righe=righe, m=m, pol=pol, cx=(xs.min() + xs.max()) / 2, cy=(ys.min() + ys.max()) / 2,
                       w=xs.max() - xs.min(), hcap=altezza(L, ALT[st]), ang=0, col=None))
for s, cx, cy, lun, spe, ang, st, righe in R:
    r = maschera_rett(cx, cy, lun, spe, ang)
    if r is None:
        print('NON TROVATA', s); continue
    _, m, pol, L = r
    m = np.nonzero(m)
    lavori.append(dict(s=s, st=st, righe=righe, m=m, pol=pol, cx=cx, cy=cy, w=lun * 0.92, hcap=altezza(L), ang=ang, col=None))
# scritte minuscole incastrate fra stelle e coste: si cancella tutto il loro riquadro
for s_, cx, cy, lun, spe, ang, st, righe, pol in FORZA:
    m = np.zeros((H, W), np.uint8)
    box = cv2.boxPoints(((cx, cy), (lun, spe), ang)).astype(np.int32)
    cv2.fillPoly(m, [box], 1)
    lettere = (pol * diff > 16) & (m > 0)
    m2 = np.nonzero(lettere.astype(np.uint8))
    lavori.append(dict(s=s_, st=st, righe=righe, m=np.nonzero(m), pol=pol, cx=cx, cy=cy, w=lun if st != 'q' else lun * 0.96,
                       hcap={'q': 17.0}.get(st, ALT.get(st, 15.5)), ang=ang, col=None, mcol=m2))
for l in lavori:
    tutta[l['m']] = 1
    l['col'] = colore(l.get('mcol', l['m']), l['pol'])
# si cancella: le lettere con un margine che prende anche ombre e aloni, poi si ricostruisce lo sfondo
cancella = cv2.dilate(tutta, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
pulita = cv2.inpaint(im, cancella, 7, cv2.INPAINT_TELEA)
# un velo di grana, perché le zone ricostruite non sembrino lisce come plastica
rumore = cv2.GaussianBlur(np.random.default_rng(3).normal(0, 4.0, im.shape).astype(np.float32), (0, 0), 0.7)
pulita = np.where(cancella[..., None] > 0, np.clip(pulita.astype(np.float32) + rumore, 0, 255), pulita).astype(np.uint8)
# le targhette: si ridipinge l'interno con il loro color crema (l'inpaint tirerebbe dentro gli aloni dei bordi)
for l in lavori:
    if l['st'] != 'q':
        continue
    ys, xs = l['m']
    px = im[ys, xs].astype(np.float32)
    g = px.mean(1)
    crema = np.median(px[g >= np.percentile(g, 55)], 0)
    grana = np.random.default_rng(5).normal(0, 3.5, (len(ys), 3))
    pulita[ys, xs] = np.clip(crema + grana, 0, 255).astype(np.uint8)
base = Image.fromarray(cv2.cvtColor(pulita, cv2.COLOR_BGR2RGB))
for l in lavori:
    hcap = l['hcap']
    if l['st'] == 't':
        hcap = max(hcap, 15)
    maxw = max(l['w'] * 1.3, l['w'] + 30) if l['st'] not in ('q',) else l['w']
    if l['st'] == 'q':
        maxw = l['w']
    img = blocco(l['righe'], l['st'], hcap, maxw)
    stampa(base, img, l['cx'], l['cy'], l['ang'], l['col'], l['pol'], ombra=l['st'] in ('t', 'q', 'c'))
base.save(OUT, quality=88)
if DBG:
    o = im.copy()
    o[cancella > 0] = (o[cancella > 0] * 0.3 + np.array([0, 0, 255]) * 0.7).astype(np.uint8)
    cv2.imwrite(DBG + '/maschera.jpg', o, [cv2.IMWRITE_JPEG_QUALITY, 85])
    json.dump([{k: (v if not isinstance(v, np.ndarray) else None) for k, v in l.items() if k not in ('m', 'mcol')} for l in lavori], open(DBG + '/lavori.json', 'w'), default=float, indent=0)
print('scritte:', len(lavori))

#!/usr/bin/env python3
"""Costruisce i dati e le immagini della mappa 3D di Diplomacy.

Uso: python3 tools/costruisci_mappa.py
Serve il pacchetto Python «diplomacy» (pip install diplomacy): da lì si prendono
- la geometria delle province (mappa SVG di jDip, di Zach DelProposto e J. Fatula III, licenza GPL);
- le adiacenze della mappa standard.

Produce:
- data/mappa.json            province, nomi italiani, adiacenze, posizioni di pedine, centri ed etichette
- assets/mappa/id.png        R = numero della provincia + 1 (0 = fuori gioco), G = terra, B = distanza dalla costa
- assets/mappa/base.jpg      la carta: pergamena, ombreggiatura dei rilievi, confini a inchiostro
- assets/mappa/quota.png     le altezze per il rilievo 3D
"""
import json, os, re, sys
import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageFilter
from scipy import ndimage as ndi
import diplomacy
from diplomacy import Game

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SVG = os.path.join(os.path.dirname(diplomacy.__file__), 'maps', 'svg', 'standard.svg')
W, H = 1835, 1360          # dimensioni della mappa SVG
S = 2                      # scala delle immagini
OX, OY = 195, 170          # traslazione dello strato della mappa
rng = np.random.default_rng(1901)

# sigle jDip diverse da quelle standard
ALIAS = {'nat': 'nao', 'nrg': 'nwg', 'mid': 'mao', 'gol': 'lyo', 'tyn': 'tys'}

NOMI = {
    'adr': 'Mare Adriatico', 'aeg': 'Mar Egeo', 'alb': 'Albania', 'ank': 'Ankara', 'apu': 'Puglia',
    'arm': 'Armenia', 'bal': 'Mar Baltico', 'bar': 'Mare di Barents', 'bel': 'Belgio', 'ber': 'Berlino',
    'bla': 'Mar Nero', 'boh': 'Boemia', 'bot': 'Golfo di Botnia', 'bre': 'Brest', 'bud': 'Budapest',
    'bul': 'Bulgaria', 'bur': 'Borgogna', 'cly': 'Clyde', 'con': 'Costantinopoli', 'den': 'Danimarca',
    'eas': 'Mediterraneo Orientale', 'edi': 'Edimburgo', 'eng': 'La Manica', 'fin': 'Finlandia',
    'gal': 'Galizia', 'gas': 'Guascogna', 'gre': 'Grecia', 'lyo': 'Golfo del Leone',
    'hel': 'Baia di Helgoland', 'hol': 'Olanda', 'ion': 'Mar Ionio', 'iri': "Mare d'Irlanda",
    'kie': 'Kiel', 'lvp': 'Liverpool', 'lvn': 'Livonia', 'lon': 'Londra', 'mar': 'Marsiglia',
    'mao': 'Medio Atlantico', 'mos': 'Mosca', 'mun': 'Monaco', 'nap': 'Napoli', 'nao': 'Nord Atlantico',
    'naf': 'Nord Africa', 'nth': 'Mare del Nord', 'nwy': 'Norvegia', 'nwg': 'Mare di Norvegia',
    'par': 'Parigi', 'pic': 'Piccardia', 'pie': 'Piemonte', 'por': 'Portogallo', 'pru': 'Prussia',
    'rom': 'Roma', 'ruh': 'Ruhr', 'rum': 'Romania', 'ser': 'Serbia', 'sev': 'Sebastopoli',
    'sil': 'Slesia', 'ska': 'Skagerrak', 'smy': 'Smirne', 'spa': 'Spagna', 'stp': 'San Pietroburgo',
    'swe': 'Svezia', 'syr': 'Siria', 'tri': 'Trieste', 'tun': 'Tunisi', 'tus': 'Toscana',
    'tyr': 'Tirolo', 'tys': 'Mar Tirreno', 'ukr': 'Ucraina', 'ven': 'Venezia', 'vie': 'Vienna',
    'wal': 'Galles', 'war': 'Varsavia', 'wes': 'Mediterraneo Occidentale', 'yor': 'Yorkshire',
}
POTENZE = ['AUSTRIA', 'ENGLAND', 'FRANCE', 'GERMANY', 'ITALY', 'RUSSIA', 'TURKEY']
# province di casa (anche senza centro) per la tinta di base della carta
CASA = {
    0: 'boh bud gal tri tyr vie', 1: 'cly edi lvp lon wal yor', 2: 'bre bur gas mar par pic',
    3: 'ber kie mun pru ruh sil', 4: 'apu nap pie rom tus ven', 5: 'fin lvn mos sev stp ukr war',
    6: 'ank arm con smy syr',
}


def bezier(p0, p1, p2, p3, n=8):
    t = np.linspace(0, 1, n + 1)[1:, None]
    return ((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3)


def parse_path(d):
    """Tracciato SVG (solo M, C, z assoluti) -> elenco di poligoni."""
    tok = re.findall(r'[MCz]|-?\d+(?:\.\d+)?', d)
    polys, cur, i, cmd = [], [], 0, None
    pos = None
    while i < len(tok):
        t = tok[i]
        if t in 'MCz':
            cmd = t
            i += 1
            if t == 'z':
                if len(cur) > 2:
                    polys.append(np.array(cur))
                cur = []
            continue
        if cmd == 'M':
            pos = np.array([float(tok[i]), float(tok[i + 1])])
            cur = [pos]
            i += 2
        elif cmd == 'C':
            p = [np.array([float(tok[i + k]), float(tok[i + k + 1])]) for k in (0, 2, 4)]
            cur.extend(bezier(pos, p[0], p[1], p[2]))
            pos = p[2]
            i += 6
    if len(cur) > 2:
        polys.append(np.array(cur))
    return polys


def raster(polys):
    """Maschera (pari-dispari) di un insieme di poligoni, alla scala S."""
    m = Image.new('1', (W * S, H * S), 0)
    for p in polys:
        t = Image.new('1', (W * S, H * S), 0)
        pts = [((x - OX) * S, (y - OY) * S) for x, y in p]
        ImageDraw.Draw(t).polygon(pts, fill=1)
        m = ImageChops.logical_xor(m, t)
    return np.array(m, dtype=bool)


def rumore(shape, scala, seme):
    g = np.random.default_rng(seme)
    a = g.standard_normal((shape[0] // scala + 3, shape[1] // scala + 3))
    a = ndi.zoom(a, scala, order=3)[:shape[0], :shape[1]]
    return a / (np.abs(a).max() + 1e-9)


def main():
    svg = open(SVG, encoding='utf-8').read()
    a = svg.find('<g id="MapLayer"')
    strato = svg[a:svg.find('</g>', a)]
    g = Game()
    m = g.map
    sigle = sorted(NOMI.keys())
    idx = {s: i for i, s in enumerate(sigle)}

    idmap = np.zeros((H * S, W * S), np.uint8)
    terra = np.zeros((H * S, W * S), bool)
    coperto = np.zeros((H * S, W * S), bool)
    stretti = {}
    voci = []
    for attr in re.findall(r'<path([^>]*)/>', strato):
        d = re.search(r' d="([^"]*)"', attr).group(1)
        pid = re.search(r'id="([^"]*)"', attr).group(1)
        cls = re.search(r'class="([^"]*)"', attr).group(1)
        voci.append((pid, cls, parse_path(d)))
    # prima il mare, poi la terra (che copre)
    for pid, cls, polys in sorted(voci, key=lambda v: v[1] != 'water'):
        mask = raster(polys)
        nome = pid.lstrip('_')
        nome = ALIAS.get(nome, nome)
        if pid == 'denmark_water':
            stretti['den'] = mask
            continue
        if pid == 'constantinople_water':
            stretti['con'] = mask
            continue
        coperto |= mask
        if cls == 'water':
            terra[mask] = False
            idmap[mask] = idx[nome] + 1 if nome in idx else 0
        else:
            terra[mask] = True
            idmap[mask] = idx[nome] + 1 if nome in idx else 0
    # gli stretti (Danimarca, Costantinopoli) sono acqua ma appartengono alla provincia
    for s, mask in stretti.items():
        terra[mask] = False
        idmap[mask] = idx[s] + 1
        coperto |= mask
    # le linee di confine dell'SVG sono buchi: si riempiono con la provincia più vicina
    ind = ndi.distance_transform_edt(~coperto, return_distances=False, return_indices=True)
    idmap = idmap[ind[0], ind[1]]
    terra = terra[ind[0], ind[1]]

    # distanza dalla costa (positiva in mare e in terra), in pixel 1x
    d_mare = ndi.distance_transform_edt(~terra) / S
    d_terra = ndi.distance_transform_edt(terra) / S

    # ---------- posizioni ----------
    pos = {}
    for nome, x, y in re.findall(r'PROVINCE name="([^"]*)">\s*<jdipNS:UNIT x="([\d.]+)" y="([\d.]+)"', svg):
        pos[nome] = [float(x) + 0.0, float(y) + 0.0]
    sc = {n.lower(): [float(x) + 10, float(y) + 10] for x, n, y in
          re.findall(r'<use height="20" id="sc_(\w+)" width="20" x="([\d.]+)" xlink:href="#SupplyCenter" y="([\d.]+)"', svg)
          for x, n in [(x, n)]} if False else {}
    for n, x, y in re.findall(r'id="sc_(\w+)" width="20" x="([\d.]+)" xlink:href="#SupplyCenter" y="([\d.]+)"', svg):
        sc[n.lower()] = [float(x) + 10, float(y) + 10]

    # ---------- adiacenze ----------
    locs = []          # 0..74 province, poi le coste
    for s in sigle:
        locs.append(s)
    coste = ['bul/ec', 'bul/sc', 'spa/nc', 'spa/sc', 'stp/nc', 'stp/sc']
    locs += coste
    li = {l: i for i, l in enumerate(locs)}
    tipo = {}
    for s in sigle:
        t = m.loc_type.get(s.upper()) or m.loc_type.get(s)
        tipo[s] = {'WATER': 'mare', 'COAST': 'costa', 'LAND': 'terra'}[t]
    multi = {'bul', 'spa', 'stp'}
    adj_a = {s: [] for s in sigle}
    adj_f = {l: [] for l in locs}
    for s in sigle:
        if tipo[s] != 'mare':
            for t in sigle:
                if t != s and tipo[t] != 'mare' and m.abuts('A', s.upper(), '-', t.upper()):
                    adj_a[s].append(idx[t])
    for l in locs:
        base = l.split('/')[0]
        if tipo[base] == 'terra' or (base in multi and '/' not in l):
            continue
        for t in locs:
            tb = t.split('/')[0]
            if tb == base or tipo[tb] == 'terra' or (tb in multi and '/' not in t):
                continue
            if m.abuts('F', l.upper(), '-', t.upper()):
                adj_f[l].append(li[t])

    centri = [s.lower() for s in m.scs]
    casa_sc = {}
    for p, n in enumerate(POTENZE):
        for s in m.homes[n]:
            casa_sc[s.lower()] = p
    casa = {}
    for p, lista in CASA.items():
        for s in lista.split():
            casa[s] = p
    iniziali = []
    for p, n in enumerate(POTENZE):
        for u in g.get_units(n):
            t, l = u.split()
            iniziali.append([p, 0 if t == 'A' else 1, li[l.lower()]])

    # baricentro robusto di ogni provincia (punto più interno) per le etichette
    etichette = {}
    for s in sigle:
        mask = idmap == idx[s] + 1
        if s in ('den', 'con'):
            mask &= terra
        dt = ndi.distance_transform_edt(mask)
        y, x = np.unravel_index(np.argmax(dt), dt.shape)
        etichette[s] = [x / S, y / S]

    province = []
    for s in sigle:
        u = pos.get(s) or pos.get({v: k for k, v in ALIAS.items()}.get(s, s))
        province.append({
            'sigla': s.upper(), 'nome': NOMI[s], 'tipo': tipo[s],
            'centro': s in centri, 'casa_centro': casa_sc.get(s, -1), 'casa': casa.get(s, -1),
            'pedina': [round(u[0] + 22, 1), round(u[1] + 22, 1)],
            'stella': [round(v, 1) for v in sc[s]] if s in sc else None,
            'etichetta': [round(u[0] + 22, 1), round(u[1] + 46, 1)],
            'adj_a': adj_a[s], 'adj_f': adj_f[s],
        })
    lista_coste = []
    for c in coste:
        b, k = c.split('/')
        u = pos[b + '-' + k]
        lista_coste.append({'sigla': c.upper(), 'provincia': idx[b], 'costa': k.upper(),
                            'pedina': [round(u[0] + 22, 1), round(u[1] + 22, 1)], 'adj_f': adj_f[c]})
    dati = {'larghezza': W, 'altezza': H, 'scala': S, 'potenze': POTENZE,
            'province': province, 'coste': lista_coste, 'iniziali': iniziali}
    os.makedirs(R + '/data', exist_ok=True)
    json.dump(dati, open(R + '/data/mappa.json', 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

    # ---------- quota ----------
    hh, ww = H * S, W * S
    yy, xx = np.mgrid[0:hh, 0:ww]

    # catene montuose in coordinate della mappa: (punti, larghezza, altezza)
    catene = [
        ([(615, 1000), (608, 950), (660, 925), (720, 915), (790, 915), (835, 900)], 20, 1.0),      # Alpi
        ([(385, 978), (440, 1010), (495, 1035)], 13, 0.85),                                        # Pirenei
        ([(930, 850), (1000, 860), (1075, 900), (1092, 960), (1040, 1000), (985, 1010)], 16, 0.8), # Carpazi
        ([(700, 500), (740, 400), (800, 300), (880, 200), (960, 140)], 24, 0.85),                  # Alpi scandinave
        ([(1490, 1050), (1580, 1085), (1690, 1100)], 17, 1.0),                                     # Caucaso
        ([(700, 1020), (735, 1070), (790, 1120), (820, 1160)], 9, 0.6),                            # Appennini
        ([(800, 985), (860, 1040), (910, 1090), (935, 1140), (960, 1190)], 13, 0.7),               # Alpi Dinariche e Pindo
        ([(1000, 1085), (1060, 1080), (1110, 1075)], 11, 0.55),                                    # Balcani
        ([(1180, 1250), (1300, 1265), (1420, 1250), (1520, 1230)], 18, 0.8),                       # Tauro
        ([(1250, 1115), (1380, 1105), (1480, 1110)], 13, 0.6),                                     # monti del Ponto
        ([(1500, 1150), (1600, 1140), (1700, 1150)], 16, 0.7),                                     # altopiano armeno
        ([(230, 1290), (380, 1265), (520, 1250), (620, 1275)], 15, 0.7),                           # Atlante
        ([(455, 490), (465, 520)], 9, 0.5),                                                        # Highlands
        ([(1790, 150), (1800, 300), (1782, 450)], 18, 0.6),                                        # Urali
        ([(215, 1010), (300, 1015), (360, 1020)], 10, 0.5),                                        # Cantabrici
        ([(230, 1080), (310, 1075)], 9, 0.4),                                                      # Sistema Centrale
        ([(250, 1150), (320, 1160)], 10, 0.5),                                                     # Sierra Nevada
        ([(770, 800), (810, 790), (850, 805)], 8, 0.4),                                            # Sudeti
        ([(520, 950), (530, 985)], 12, 0.4),                                                       # Massiccio Centrale
        ([(430, 648), (428, 662)], 6, 0.3),                                                        # Galles
        ([(375, 135), (400, 140)], 12, 0.45),                                                      # Islanda
    ]
    monti = np.zeros((hh, ww), np.float32)
    for punti, larg, alt in catene:
        im = Image.new('L', (ww, hh), 0)
        ImageDraw.Draw(im).line([(x * S, y * S) for x, y in punti], fill=255, width=int(larg * S * 0.5), joint='curve')
        r = ndi.gaussian_filter(np.array(im, np.float32) / 255.0, larg * S * 0.55)
        r = r / (r.max() + 1e-9) * alt
        monti = np.maximum(monti, r)
    fr = (rumore((hh, ww), 24, 1) * 0.5 + rumore((hh, ww), 10, 2) * 0.3 + rumore((hh, ww), 4, 3) * 0.2)
    creste = 1.0 - np.abs(rumore((hh, ww), 14, 7))
    creste2 = 1.0 - np.abs(rumore((hh, ww), 7, 8))
    monti = monti * (0.30 + 0.45 * creste ** 2 + 0.25 * creste2 ** 2) * (0.8 + 0.4 * fr)
    colline = np.clip(rumore((hh, ww), 60, 4) * 0.5 + rumore((hh, ww), 26, 5) * 0.5, 0, 1) * 0.10
    riva = np.clip(d_terra / 13.0, 0, 1)
    riva = riva * riva * (3 - 2 * riva)
    quota = np.where(terra, (0.10 + colline + monti * 0.9) * (0.25 + 0.75 * riva) * riva ** 0.5, 0.0)
    quota = ndi.gaussian_filter(quota, 2.2)
    quota = np.clip(quota, 0, 1)
    q_img = Image.fromarray((quota * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    q_img.save(R + '/assets/mappa/quota.png')

    # ---------- id ----------
    b = np.clip(np.where(terra, 0, d_mare) * 4, 0, 255).astype(np.uint8)
    idimg = np.dstack([idmap, np.where(terra, 255, 0).astype(np.uint8), b])
    Image.fromarray(idimg, 'RGB').save(R + '/assets/mappa/id.png', optimize=True)

    # ---------- carta ----------
    # ombreggiatura dei rilievi (luce da nord-ovest)
    gy, gx = np.gradient(ndi.gaussian_filter(quota, 1.0))
    luce = np.clip(0.5 - (gx * 0.9 + gy * 0.9) * 26.0, 0.05, 1.0)
    carta_r = rumore((hh, ww), 90, 11) * 0.5 + rumore((hh, ww), 7, 12) * 0.3 + rng.standard_normal((hh, ww)) * 0.12
    fibra = ndi.gaussian_filter(rng.standard_normal((hh, ww)), (0.6, 5.0)) * 0.9
    perg = np.array([232, 216, 176], np.float32)
    base = np.ones((hh, ww, 3), np.float32) * perg
    base *= (1.0 + carta_r[..., None] * 0.07 + fibra[..., None] * 0.035)
    # tinta verdolina in pianura, bruna in quota
    alta = np.clip((quota - 0.3) / 0.5, 0, 1)[..., None]
    base = base * (1 - alta * 0.25) + np.array([150, 120, 84], np.float32) * alta * 0.25
    ombra = (0.55 + 0.9 * luce)[..., None]
    base = np.where(terra[..., None], base * np.clip(ombra, 0.55, 1.28), base)
    # mare: carta azzurro-grigia, più chiara verso riva, con le linee di costa delle carte antiche
    mare = np.array([150, 176, 186], np.float32) * (1.0 + carta_r[..., None] * 0.06 + fibra[..., None] * 0.03)
    fondo = np.clip(d_mare / 60.0, 0, 1)[..., None]
    mare = mare * (1.08 - 0.20 * fondo)
    onde = (np.cos(np.clip(d_mare, 0, 17) * (2 * np.pi / 5.5)) * 0.5 + 0.5) * np.clip(1 - d_mare / 17.0, 0, 1)
    mare = mare * (1 - 0.16 * onde[..., None])
    fuori = (terra & (idmap == 0))[..., None]
    grigio = base.mean(axis=2, keepdims=True)
    base = np.where(fuori, (base * 0.45 + grigio * 0.55) * 0.80, base)
    base = np.where(terra[..., None], base, mare)

    # confini
    def bordo(mask, spess):
        return ndi.binary_dilation(mask, iterations=spess) if spess > 0 else mask
    diff = np.zeros((hh, ww), bool)
    diff[:, 1:] |= idmap[:, 1:] != idmap[:, :-1]
    diff[1:, :] |= idmap[1:, :] != idmap[:-1, :]
    costa = np.zeros((hh, ww), bool)
    costa[:, 1:] |= terra[:, 1:] != terra[:, :-1]
    costa[1:, :] |= terra[1:, :] != terra[:-1, :]
    conf_terra = diff & terra & ~bordo(costa, 2)
    conf_mare = diff & ~terra & ~bordo(costa, 2)
    # i confini di mare sono tratteggiati
    tratto = ((xx + yy) // (5 * S)) % 2 == 0
    k_costa = ndi.gaussian_filter(bordo(costa, 1).astype(np.float32), 0.8)
    k_terra = ndi.gaussian_filter(bordo(conf_terra, 1).astype(np.float32), 0.9)
    k_mare = ndi.gaussian_filter((bordo(conf_mare, 1) & tratto).astype(np.float32), 0.8)
    ink = np.array([58, 40, 24], np.float32)
    ink_m = np.array([70, 96, 112], np.float32)
    for k, col, f in ((k_terra, ink, 0.80), (k_mare, ink_m, 0.75), (k_costa, ink, 0.95)):
        kk = np.clip(k * 1.6, 0, 1)[..., None] * f
        base = base * (1 - kk) + col * kk
    # confini di Stato più marcati (fra province di casa di potenze diverse o verso i neutrali)
    naz = np.full(len(sigle) + 1, -1, np.int16)
    for s in sigle:
        naz[idx[s] + 1] = casa.get(s, -2 - idx[s] if False else -1)
    nm = naz[idmap]
    dn = np.zeros((hh, ww), bool)
    dn[:, 1:] |= nm[:, 1:] != nm[:, :-1]
    dn[1:, :] |= nm[1:, :] != nm[:-1, :]
    dn &= terra & ~bordo(costa, 3)
    k_naz = ndi.gaussian_filter(bordo(dn, 2).astype(np.float32), 1.0)
    kk = np.clip(k_naz * 1.5, 0, 1)[..., None] * 0.85
    base = base * (1 - kk) + ink * kk
    # vignettatura dei margini
    vx = np.minimum(xx, ww - 1 - xx) / (ww * 0.06)
    vy = np.minimum(yy, hh - 1 - yy) / (hh * 0.06)
    vig = np.clip(np.minimum(vx, vy), 0, 1) ** 0.6
    base *= (0.72 + 0.28 * vig)[..., None]
    out = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), 'RGB')
    out.save(R + '/assets/mappa/base.jpg', quality=88)

    # anteprima di controllo (non entra nel gioco)
    if '--prova' in sys.argv:
        dbg = out.copy()
        dr = ImageDraw.Draw(dbg)
        for p in province:
            x, y = p['pedina']
            dr.ellipse([x * S - 8, y * S - 8, x * S + 8, y * S + 8], outline=(200, 0, 0), width=3)
            x, y = p['etichetta']
            dr.text((x * S, y * S), p['sigla'], fill=(0, 0, 160))
            if p['stella']:
                x, y = p['stella']
                dr.rectangle([x * S - 5, y * S - 5, x * S + 5, y * S + 5], fill=(0, 120, 0))
        for c in lista_coste:
            x, y = c['pedina']
            dr.ellipse([x * S - 8, y * S - 8, x * S + 8, y * S + 8], outline=(200, 0, 200), width=3)
        dbg.resize((W, H)).save('/tmp/mappa_prova.jpg', quality=85)
    print('province', len(province), 'centri', len(centri), 'unità iniziali', len(iniziali))


if __name__ == '__main__':
    main()

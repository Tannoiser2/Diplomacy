#!/usr/bin/env python3
"""Modella le pedine 3D «classiche» di Diplomacy: il cannone da campagna (armata) e la corazzata (flotta).

Uso: python3 tools/costruisci_modelli.py
Scrive assets/modelli/cannone.obj e corazzata.obj. Ogni modello ha tre materiali:
«colore» (prende il colore della potenza), «metallo» e «legno».
"""
import math, os
import numpy as np

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


class Mesh:
    def __init__(self):
        self.v, self.n, self.f = [], [], {}     # f: materiale -> [(v, n) x3]

    def tri(self, mat, pts, norms=None):
        a, b, c = [np.array(p, float) for p in pts]
        if norms is None:
            nn = np.cross(b - a, c - a)
            l = np.linalg.norm(nn)
            if l < 1e-12:
                return
            norms = [nn / l] * 3
        idx = []
        for p, n in zip((a, b, c), norms):
            self.v.append(p)
            self.n.append(np.array(n, float))
            idx.append(len(self.v))
        self.f.setdefault(mat, []).append(idx)

    def quad(self, mat, p, norms=None):
        self.tri(mat, [p[0], p[1], p[2]], None if norms is None else [norms[0], norms[1], norms[2]])
        self.tri(mat, [p[0], p[2], p[3]], None if norms is None else [norms[0], norms[2], norms[3]])

    def cilindro(self, mat, p0, p1, r0, r1, n=18, tappi=True):
        p0, p1 = np.array(p0, float), np.array(p1, float)
        ax = p1 - p0
        L = np.linalg.norm(ax)
        ax = ax / L
        t = np.array([0, 1, 0]) if abs(ax[1]) < 0.9 else np.array([1, 0, 0])
        u = np.cross(ax, t)
        u /= np.linalg.norm(u)
        w = np.cross(ax, u)
        ring0, ring1, nrm = [], [], []
        for i in range(n):
            a = 2 * math.pi * i / n
            d = math.cos(a) * u + math.sin(a) * w
            ring0.append(p0 + d * r0)
            ring1.append(p1 + d * r1)
            nrm.append(d)
        for i in range(n):
            j = (i + 1) % n
            self.quad(mat, [ring0[i], ring0[j], ring1[j], ring1[i]], [nrm[i], nrm[j], nrm[j], nrm[i]])
        if tappi:
            for i in range(n):
                j = (i + 1) % n
                if r0 > 1e-9:
                    self.tri(mat, [p0, ring0[j], ring0[i]])
                if r1 > 1e-9:
                    self.tri(mat, [p1, ring1[i], ring1[j]])

    def scatola(self, mat, c, s, rot_y=0.0, rot_z=0.0):
        c = np.array(c, float)
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        cz, sz = math.cos(rot_z), math.sin(rot_z)
        cy, sy = math.cos(rot_y), math.sin(rot_y)

        def T(p):
            x, y, z = p
            x, y = x * cz - y * sz, x * sz + y * cz
            x, z = x * cy + z * sy, -x * sy + z * cy
            return c + np.array([x, y, z])
        P = [T(p) for p in [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
                            (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]]
        for q in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)]:
            self.quad(mat, [P[i] for i in q])

    def salva(self, nome):
        with open(nome, 'w') as f:
            f.write('# Pedina di Diplomacy generata da tools/costruisci_modelli.py\n')
            for v in self.v:
                f.write('v %.5f %.5f %.5f\n' % tuple(v))
            for n in self.n:
                f.write('vn %.4f %.4f %.4f\n' % tuple(n))
            for mat, facce in self.f.items():
                f.write('usemtl %s\n' % mat)
                for a, b, c in facce:
                    f.write('f %d//%d %d//%d %d//%d\n' % (a, a, b, b, c, c))


def cannone():
    m = Mesh()
    # base rotonda della pedina
    m.cilindro('colore', (0, 0, 0), (0, 0.05, 0), 0.50, 0.47, 28)
    # ruote a raggi
    for sx in (-1, 1):
        x = sx * 0.27
        yc = 0.05 + 0.24
        # cerchione (anello) e mozzo
        n = 20
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            for r_in, r_out, dx in ((0.19, 0.24, 0.035),):
                p = []
                for (a, r) in ((a0, r_in), (a1, r_in), (a1, r_out), (a0, r_out)):
                    p.append((x, yc + math.sin(a) * r, math.cos(a) * r))
                e = np.array([dx, 0, 0])
                A = [np.array(q) - e for q in p]
                B = [np.array(q) + e for q in p]
                m.quad('legno', [A[0], A[1], A[2], A[3]])
                m.quad('legno', [B[3], B[2], B[1], B[0]])
                m.quad('legno', [A[3], A[2], B[2], B[3]])
                m.quad('legno', [A[1], A[0], B[0], B[1]])
        for k in range(8):
            a = math.pi * k / 4
            m.cilindro('legno', (x, yc, 0), (x, yc + math.sin(a) * 0.20, math.cos(a) * 0.20), 0.016, 0.014, 6, False)
        m.cilindro('metallo', (x - sx * 0.05, yc, 0), (x + sx * 0.05, yc, 0), 0.045, 0.04, 10)
    # asse
    m.cilindro('metallo', (-0.27, 0.29, 0), (0.27, 0.29, 0), 0.022, 0.022, 8)
    # affusto con la coda a terra
    m.scatola('colore', (0, 0.30, 0.02), (0.20, 0.07, 0.24))
    for sx in (-1, 1):
        a0 = np.array([sx * 0.07, 0.29, -0.05])
        a1 = np.array([sx * 0.03, 0.075, -0.44])
        m.cilindro('legno', a0, a1, 0.03, 0.026, 8)
    m.scatola('metallo', (0, 0.075, -0.44), (0.12, 0.03, 0.06))
    # scudo
    m.scatola('colore', (0, 0.40, 0.10), (0.42, 0.22, 0.02), 0, 0)
    # canna, alzata di qualche grado
    el = math.radians(14)
    d = np.array([0, math.sin(el), math.cos(el)])
    b0 = np.array([0, 0.36, -0.10])
    m.cilindro('metallo', b0, b0 + d * 0.22, 0.062, 0.056, 16)
    m.cilindro('metallo', b0 + d * 0.22, b0 + d * 0.66, 0.050, 0.036, 16)
    m.cilindro('metallo', b0 + d * 0.66, b0 + d * 0.70, 0.044, 0.044, 16)
    m.cilindro('metallo', b0 - d * 0.04, b0, 0.03, 0.062, 12)
    m.salva(R + '/assets/modelli/cannone.obj')


def corazzata():
    m = Mesh()
    # scafo: sezioni lungo l'asse z (prua a +z)
    L = 1.15
    sez = []
    for i in range(15):
        t = i / 14.0
        z = -L / 2 + t * L
        # larghezza: poppa tonda, prua affilata
        w = 0.165 * (math.sin(math.pi * min(1.0, t * 1.25 + 0.12)) ** 0.75 if t < 0.78 else (1 - (t - 0.78) / 0.22) ** 0.9 * math.sin(math.pi * min(1.0, 0.78 * 1.25 + 0.12)) ** 0.75)
        w = max(w, 0.004)
        ponte = 0.20 + 0.03 * max(0.0, (t - 0.7) / 0.3) ** 2      # la prua si alza un poco
        sez.append((z, w, ponte))

    def anello(z, w, top):
        return [np.array([-w, top, z]), np.array([-w * 0.92, 0.09, z]), np.array([-w * 0.45, 0.012, z]),
                np.array([w * 0.45, 0.012, z]), np.array([w * 0.92, 0.09, z]), np.array([w, top, z])]
    anelli = [anello(*s) for s in sez]
    for a, b in zip(anelli[:-1], anelli[1:]):
        for k in range(5):
            m.quad('colore', [a[k], a[k + 1], b[k + 1], b[k]])
        m.quad('legno', [a[5], a[0], b[0], b[5]])            # ponte
    m.quad('colore', [anelli[0][0], anelli[0][5], anelli[0][4], anelli[0][1]])
    m.quad('colore', [anelli[0][1], anelli[0][4], anelli[0][3], anelli[0][2]])
    # fascia chiara sul bordo
    # sovrastruttura
    m.scatola('chiaro', (0, 0.245, -0.02), (0.20, 0.09, 0.46))
    m.scatola('chiaro', (0, 0.32, 0.10), (0.14, 0.07, 0.14))          # plancia
    m.scatola('chiaro', (0, 0.305, -0.16), (0.12, 0.04, 0.12))
    # fumaioli
    for z in (-0.10, 0.0):
        m.cilindro('metallo', (0, 0.28, z), (0, 0.50, z - 0.015), 0.042, 0.038, 14)
        m.cilindro('colore', (0, 0.45, z - 0.012), (0, 0.475, z - 0.0135), 0.041, 0.040, 14, False)
    # alberi
    m.cilindro('metallo', (0, 0.34, 0.14), (0, 0.66, 0.13), 0.010, 0.006, 6)
    m.cilindro('metallo', (0, 0.30, -0.22), (0, 0.56, -0.23), 0.009, 0.006, 6)
    m.scatola('metallo', (0, 0.54, 0.132), (0.10, 0.008, 0.008))
    # torri binate a prua e a poppa
    for z, verso in ((0.30, 1), (-0.36, -1)):
        m.cilindro('chiaro', (0, 0.20, z), (0, 0.262, z), 0.085, 0.075, 16)
        for sx in (-0.03, 0.03):
            m.cilindro('metallo', (sx, 0.24, z + verso * 0.05), (sx, 0.262, z + verso * 0.27), 0.014, 0.011, 8)
    # cannoni secondari
    for z in (-0.04, 0.08):
        for sx in (-1, 1):
            m.cilindro('metallo', (sx * 0.09, 0.235, z), (sx * 0.19, 0.24, z), 0.010, 0.008, 6)
    # bandiera a poppa
    m.cilindro('metallo', (0, 0.20, -0.54), (0, 0.36, -0.56), 0.005, 0.004, 5)
    m.scatola('colore', (0, 0.33, -0.60), (0.004, 0.05, 0.08))
    m.salva(R + '/assets/modelli/corazzata.obj')


def pulisci_tts():
    """I modelli del modulo TTS (carro e nave): si tolgono i riferimenti ai materiali esterni."""
    for src, dst in (('/tmp/tts_tank.obj', 'carro.obj'), ('/tmp/tts_navy.obj', 'nave.obj')):
        if not os.path.exists(src):
            continue
        righe = [r for r in open(src) if not r.startswith(('mtllib', 'usemtl', 'o ', 's ', 'g '))]
        open(R + '/assets/modelli/' + dst, 'w').write('usemtl colore\n' + ''.join(righe))


if __name__ == '__main__':
    os.makedirs(R + '/assets/modelli', exist_ok=True)
    cannone()
    corazzata()
    pulisci_tts()
    print('modelli pronti')

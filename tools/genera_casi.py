#!/usr/bin/env python3
"""Genera i casi di prova dell'arbitro confrontandosi con il pacchetto Python «diplomacy».

Uso: python3 tools/genera_casi.py [numero di casi casuali]
Scrive tests/casi_arbitro.json con:
- i casi DATC (Diplomacy Adjudicator Test Cases) contenuti nelle prove del pacchetto;
- posizioni casuali con ordini casuali (anche sbagliati), risolte dal motore di riferimento.
"""
import json, os, random, sys, inspect
from diplomacy import Game
from diplomacy.tests import test_datc

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
M = json.load(open(R + '/data/mappa.json', encoding='utf-8'))
LOCS = [p['sigla'] for p in M['province']] + [c['sigla'] for c in M['coste']]
LI = {s: i for i, s in enumerate(LOCS)}
PROV = {s: (i if i < 75 else M['coste'][i - 75]['provincia']) for i, s in enumerate(LOCS)}
POT = M['potenze']
TIPO = [p['tipo'] for p in M['province']]


def unita(game):
    out = []
    for pi, p in enumerate(POT):
        for u in game.get_units(p):
            if u.startswith('*'):
                continue
            t, l = u.split()
            out.append([pi, 0 if t == 'A' else 1, LI[l]])
    return sorted(out)


def traduci(o):
    """'A PAR S A MAR - BUR' -> (provincia, [tipo, a, b]) oppure None."""
    w = o.replace(' VIA', ' VIA').split()
    try:
        if len(w) < 3 or w[1] not in LI:
            return None
        pr = PROV[w[1]]
        if w[2] == 'H':
            return pr, [0, -1, -1]
        if w[2] == '-':
            if w[3] not in LI:
                return pr, [1, 99, 0]
            return pr, [1, LI[w[3]], 1 if w[-1] == 'VIA' else 0]
        if w[2] in ('S', 'C'):
            r = w[3:]
            if r[0] in ('A', 'F'):
                r = r[1:]
            a = PROV[r[0]]
            b = PROV[r[2]] if len(r) >= 3 and r[1] == '-' else a
            if len(r) >= 3 and r[1] == '-' and b == a:
                b = -1          # «sostiene X - X» non è un ordine valido
            return pr, [2 if w[2] == 'S' else 3, a, b]
    except (KeyError, IndexError):
        return None
    return None


def caso(nome, game, grezzi):
    """Registra posizione e ordini, fa risolvere al motore e registra il risultato."""
    prima = unita(game)
    di = {PROV[LOCS[u[2]]]: u[0] for u in prima}
    ordini = {}
    for pi, lista in grezzi.items():
        for o in lista:
            t = traduci(o)
            if t is None:
                continue
            pr, v = t
            if di.get(pr) != pi:
                continue          # si ordinano solo le proprie unità
            ordini[str(pr)] = v
    game.process()
    dopo = unita(game)
    rit = {}
    st = game.get_state()
    for p, d in (st.get('retreats') or {}).items():
        for u, opz in d.items():
            rit[str(PROV[u.split()[1]])] = sorted(LI[x] for x in opz)
    return {'nome': nome, 'unita': prima, 'ordini': ordini, 'dopo': dopo, 'ritirate': rit}


def casi_datc():
    out = []
    reg = {}

    class Spia(test_datc.TestDATC):
        pass
    t = Spia()
    orig_set = test_datc.TestDATC.set_orders
    stato = {'nome': '', 'grezzi': {}, 'n': 0}

    def set_orders(game, power_name, orders):
        if game.phase_type == 'M':
            stato['grezzi'].setdefault(POT.index(power_name), []).extend(orders)
        orig_set(game, power_name, orders)

    def process(game):
        if game.phase_type == 'M':
            # si rifà la risoluzione su una copia per registrare il caso
            copia = Game()
            copia.clear_units()
            for p in POT:
                copia.set_units(p, [u for u in game.get_units(p) if not u.startswith('*')])
            for pi, lista in stato['grezzi'].items():
                copia.set_orders(POT[pi], lista)
            stato['n'] += 1
            out.append(caso('%s#%d' % (stato['nome'], stato['n']), copia, stato['grezzi']))
        stato['grezzi'] = {}
        game.process()

    Spia.set_orders = staticmethod(set_orders)
    Spia.process = staticmethod(process)
    for nome, f in inspect.getmembers(Spia, predicate=inspect.isfunction):
        if not nome.startswith('test_'):
            continue
        stato.update(nome=nome[5:], grezzi={}, n=0)
        try:
            getattr(t, nome)()
        except Exception as e:      # le asserzioni del pacchetto non ci interessano
            reg[nome] = str(e)[:80]
    return out


def casuale(rnd, n):
    """Posizione casuale fitta, con ordini che interagiscono."""
    g = Game()
    g.clear_units()
    libere = list(range(75))
    rnd.shuffle(libere)
    # si concentra l'azione in una zona
    semi = rnd.sample(range(75), 2)
    def vicino(p):
        return min(abs(M['province'][p]['pedina'][0] - M['province'][s]['pedina'][0]) +
                   abs(M['province'][p]['pedina'][1] - M['province'][s]['pedina'][1]) for s in semi)
    libere.sort(key=lambda p: vicino(p) + rnd.random() * 250)
    nu = rnd.randint(6, 18)
    us = []
    per_pot = {i: [] for i in range(7)}
    npot = rnd.randint(2, 5)
    for p in libere[:nu]:
        tp = TIPO[p]
        t = 'F' if tp == 'mare' else ('A' if tp == 'terra' else rnd.choice('AAF'))
        loc = LOCS[p]
        if t == 'F':
            cs = [c['sigla'] for c in M['coste'] if c['provincia'] == p]
            if cs:
                loc = rnd.choice(cs)
        pot = rnd.randrange(npot)
        per_pot[pot].append('%s %s' % (t, loc))
        us.append((pot, t, loc, p))
    for pot, l in per_pot.items():
        g.set_units(POT[pot], l)
    occ = {u[3]: u for u in us}
    grezzi = {}
    mosse = {}
    # primo giro: mosse e ferme
    for pot, t, loc, p in us:
        r = rnd.random()
        if t == 'A':
            dest = [LOCS[x] for x in M['province'][p]['adj_a']]
        else:
            li = LI[loc]
            adj = M['province'][li]['adj_f'] if li < 75 else M['coste'][li - 75]['adj_f']
            dest = [LOCS[x] for x in adj]
        if r < 0.55 and dest:
            d = rnd.choice(dest)
            # preferenza per i bersagli occupati o contesi
            for _ in range(2):
                if PROV[d] not in occ and rnd.random() < 0.5:
                    d = rnd.choice(dest)
            mosse[p] = d
    # armate convogliate
    flotte_mare = [u for u in us if u[1] == 'F' and TIPO[u[3]] == 'mare']
    conv = {}
    for pot, t, loc, p in us:
        if t == 'A' and TIPO[p] == 'costa' and flotte_mare and rnd.random() < 0.25:
            f = rnd.choice(flotte_mare)
            cost = [x for x in range(75) if TIPO[x] == 'costa' and x != p]
            d = rnd.choice(cost)
            mosse[p] = LOCS[d] + (' VIA' if rnd.random() < 0.6 else '')
            conv[f[3]] = (p, d)
            for f2 in flotte_mare:
                if rnd.random() < 0.5:
                    conv[f2[3]] = (p, d)
    for pot, t, loc, p in us:
        o = None
        if p in conv and rnd.random() < 0.85:
            a, d = conv[p]
            o = '%s %s C A %s - %s' % (t, loc, LOCS[a], LOCS[d])
        elif p in mosse:
            o = '%s %s - %s' % (t, loc, mosse[p])
        else:
            r = rnd.random()
            altri = [u for u in us if u[3] != p]
            if r < 0.75 and altri:
                # sostegno: di preferenza a una mossa vera verso una provincia vicina
                rnd.shuffle(altri)
                fatto = False
                for q in altri:
                    if q[3] in mosse and rnd.random() < 0.9:
                        d = mosse[q[3]].replace(' VIA', '')
                        o = '%s %s S %s %s - %s' % (t, loc, q[1], LOCS[q[3]], LOCS[PROV[d]])
                        fatto = True
                        if rnd.random() < 0.7:
                            break
                if not fatto:
                    q = altri[0]
                    o = '%s %s S %s %s' % (t, loc, q[1], LOCS[q[3]])
            else:
                o = '%s %s H' % (t, loc)
        grezzi.setdefault(pot, []).append(o)
    for pot, l in grezzi.items():
        g.set_orders(POT[pot], l)
    return caso('casuale%d' % n, g, grezzi)


def main():
    quanti = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
    casi = casi_datc()
    nd = len(casi)
    rnd = random.Random(1901)
    for i in range(quanti):
        casi.append(casuale(rnd, i))
    json.dump(casi, open(R + '/tests/casi_arbitro.json', 'w'), separators=(',', ':'))
    print('casi DATC', nd, 'casuali', quanti)


if __name__ == '__main__':
    main()

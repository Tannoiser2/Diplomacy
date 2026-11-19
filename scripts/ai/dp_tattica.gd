class_name DPTattica
extends RefCounted
## Il motore tattico dell'IA.
##
## 1. Valore delle province (sul modello del DumbBot di David Norman): ogni centro vale per quanto è
##    appetibile da conquistare o urgente da difendere, e il valore si diffonde alle province vicine.
## 2. Candidati: per ogni potenza si generano molti insiemi di ordini plausibili (mosse verso le
##    province di valore, sostegni alle mosse contese, convogli, difese).
## 3. Ricerca: ogni candidato viene arbitrato contro campioni degli ordini probabili delle altre
##    potenze e si sceglie quello con il risultato atteso migliore (miglior risposta campionata,
##    come nei bot da torneo senza rete neurale).
##
## L'ostilità verso ogni potenza (0 alleato fidato, 0.5 neutrale, 1 nemico) arriva dal diplomatico.

const PESI_PRIMAVERA := [100.0, 1000.0, 30.0, 10.0, 6.0]
const PESI_AUTUNNO := [1000.0, 100.0, 30.0, 10.0, 6.0]
## Sotto questa ostilità una potenza è trattata da amica: non la si attacca.
const AMICO := 0.34

var adj := DPAdj.new()
var rng := RandomNumberGenerator.new()
var _occ := PackedInt32Array()
var _occ_t := PackedInt32Array()


func _init() -> void:
	_occ.resize(DPMap.N_PROV)
	_occ_t.resize(DPMap.N_PROV)
	rng.randomize()


# ---------------------------------------------------------------- valori

## Valori delle province per la potenza p: [per le armate, per le flotte, difesa dei propri centri].
func valori(st: DPState, p: int, ost: PackedFloat32Array, autunno: bool, anno: int, extra: Dictionary = {}) -> Array:
	var n := DPMap.N_PROV
	var base := PackedFloat32Array()
	base.resize(n)
	var difesa := PackedFloat32Array()
	difesa.resize(n)
	var nu := st.conta_unita()
	var nc := st.conta_centri()
	var capo := 0
	for q in 7:
		capo = maxi(capo, nc[q])
	for c in DPMap.centri:
		var o := st.sc[c]
		if o == p:
			# quanto è minacciato: unità altrui che possono entrarci
			var m := 0.0
			for j in DPMap.adj_tutte[c]:
				var q := st.up[j]
				if q >= 0 and q != p and DPMap.tocca(st.ut[j], st.ul[j], c):
					m += ost[q]
			if st.up[c] >= 0 and st.up[c] != p:
				m += 1.5 * ost[st.up[c]]
			var d := minf(m, 2.5) * 0.85
			if DPMap.casa_centro[c] == p:
				d *= 1.35
			difesa[c] = d
			base[c] = d
		elif o < 0:
			base[c] = 1.45 if anno <= 1902 else 1.25
		else:
			# centro di un'altra potenza: vale secondo l'ostilità e la debolezza del proprietario
			var f := 0.02 if ost[o] < AMICO else lerpf(0.35, 1.3, clampf((ost[o] - AMICO) / 0.6, 0.0, 1.0))
			f *= 1.0 + 1.2 / (1.0 + float(nu[o]))
			if nc[o] >= 13 and nc[o] == capo:
				f = maxf(f, 1.2) * 1.3          # fermare chi sta per vincere
			base[c] = f
		if extra.has(c):
			base[c] += float(extra[c])
	var va := _diffondi(base, DPMap.adj_a, autunno, true)
	var vf := _diffondi(base, DPMap.adj_fp, autunno, false)
	return [va, vf, difesa]


func _diffondi(base: PackedFloat32Array, adjs: Array, autunno: bool, armata: bool) -> PackedFloat32Array:
	var n := DPMap.N_PROV
	var pesi: Array = PESI_AUTUNNO if autunno else PESI_PRIMAVERA
	var cur := PackedFloat32Array()
	cur.resize(n)
	for i in n:
		var ok := (DPMap.tipo[i] != DPMap.MARE) if armata else (DPMap.tipo[i] != DPMap.TERRA)
		cur[i] = base[i] if ok else 0.0
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = cur[i] * pesi[0]
	for k in range(1, pesi.size()):
		var nx := PackedFloat32Array()
		nx.resize(n)
		for i in n:
			var s := cur[i]
			for j in adjs[i]:
				s += cur[j]
			nx[i] = s / 5.0
		cur = nx
		for i in n:
			out[i] += cur[i] * pesi[k]
	return out


# ---------------------------------------------------------------- candidati

## Un insieme di ordini di movimento per p: {provincia: [tipo, a, b]}.
## temp: quanta casualità (0 = sempre la scelta migliore). vincoli: ordini già decisi (accordi).
## vietate: {provincia: penalità} province in cui non entrare (zone smilitarizzate, alleati).
func candidato(st: DPState, p: int, val: Array, ost: PackedFloat32Array, temp: float,
		vincoli: Dictionary = {}, vietate: Dictionary = {}) -> Dictionary:
	var va: PackedFloat32Array = val[0]
	var vf: PackedFloat32Array = val[1]
	var difesa: PackedFloat32Array = val[2]
	var unita := Array(st.unita_di(p))
	var ordini := {}
	var arrivo := {}      # provincia -> unità che ci sarà (resta o arriva)
	var parte := {}       # unità che lasciano la provincia
	for u in vincoli:
		var o: Array = vincoli[u]
		if st.up[u] != p:
			continue
		ordini[u] = o
		if int(o[0]) == DPAdj.M:
			arrivo[DPMap.loc_prov[int(o[1])]] = u
			parte[u] = true
		else:
			arrivo[u] = u
	# ordine di decisione: prima chi ha le opzioni migliori (con un po' di rumore)
	var chiavi := []
	for u in unita:
		if ordini.has(u):
			continue
		var v: PackedFloat32Array = va if st.ut[u] == 0 else vf
		var best := v[u]
		for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
			best = maxf(best, v[DPMap.loc_prov[l]])
		chiavi.append([-best * (1.0 + temp * rng.randf_range(-0.6, 0.6)), u])
	chiavi.sort()
	var convogli := _opzioni_convoglio(st, p, va, ordini) if temp > 0.0 or true else {}
	for ch in chiavi:
		var u: int = ch[1]
		if ordini.has(u):
			continue
		var t := st.ut[u]
		var v: PackedFloat32Array = va if t == 0 else vf
		var opz := []        # [punteggio, loc, via_convoglio, flotta]
		# restare: vale la provincia, di più se è un proprio centro minacciato
		var qui := v[u] * 0.82
		if st.sc[u] == p and difesa[u] > 0.0:
			qui += difesa[u] * 900.0
		elif DPMap.centro[u] == 1 and st.sc[u] != p and st.sc[u] >= 0 and ost[st.sc[u]] > 0.25:
			qui = v[u] * 1.35         # si sta occupando un centro altrui: va tenuto fino all'autunno
		elif DPMap.centro[u] == 1 and st.sc[u] < 0:
			qui = v[u] * 1.35
		opz.append([qui, st.ul[u], 0, -1])
		for l in DPMap.destinazioni(t, st.ul[u]):
			var d := DPMap.loc_prov[l]
			var s := v[d]
			var occ := st.up[d]
			if occ == p and not parte.has(d) and ordini.has(d):
				continue                      # c'è una propria unità che resta
			if occ >= 0 and occ != p:
				# attaccare un'unità: ha senso verso i nemici, mai verso gli amici
				if ost[occ] < AMICO:
					continue
				s *= _freno(ost[occ])
			elif DPMap.centro[d] == 1 and st.sc[d] >= 0 and st.sc[d] != p:
				if ost[st.sc[d]] < AMICO:
					continue
				s *= _freno(ost[st.sc[d]])
			if vietate.has(d):
				s *= float(vietate[d])
			opz.append([s, l, 0, -1])
		if t == 0 and convogli.has(u):
			for c in convogli[u]:
				var d: int = c[0]
				var s := va[d] * 0.92
				if st.up[d] >= 0 and st.up[d] != p:
					if ost[st.up[d]] < AMICO:
						continue
					s *= _freno(ost[st.up[d]])
				elif DPMap.centro[d] == 1 and st.sc[d] >= 0 and st.sc[d] != p:
					if ost[st.sc[d]] < AMICO:
						continue
					s *= _freno(ost[st.sc[d]])
				if vietate.has(d):
					s *= float(vietate[d])
				if not ordini.has(c[1]):
					opz.append([s, d, 1, c[1]])
		opz.sort_custom(func(a, b): return a[0] > b[0])
		var fatto := false
		var tent := 0
		while not fatto and tent < 6 and not opz.is_empty():
			tent += 1
			var k := _scegli(opz, temp)
			var o: Array = opz[k]
			opz.remove_at(k)
			var l: int = o[1]
			var d := DPMap.loc_prov[l]
			if d == u:
				if arrivo.has(u) and arrivo[u] != u:
					continue          # un'altra unità sta venendo qui
				ordini[u] = [DPAdj.H, -1, -1]
				arrivo[u] = u
				fatto = true
			elif arrivo.has(d):
				# la provincia è già di un'altra propria unità: la si sostiene se serve
				var w: int = arrivo[d]
				if _contesa(st, p, d, ost) and DPMap.tocca(t, st.ul[u], d) and o[2] == 0:
					ordini[u] = [DPAdj.S, w, d]
					if not arrivo.has(u):
						arrivo[u] = u
					fatto = true
			elif st.up[d] == p and not parte.has(d) and ordini.has(d):
				continue
			else:
				if o[2] == 1:
					var f: int = o[3]
					if ordini.has(f):
						continue
					ordini[f] = [DPAdj.C, u, d]
					arrivo[f] = f
					ordini[u] = [DPAdj.M, d, 1]
				else:
					ordini[u] = [DPAdj.M, l, 0]
				arrivo[d] = u
				parte[u] = true
				fatto = true
		if not fatto:
			ordini[u] = [DPAdj.H, -1, -1]
			arrivo[u] = u
	# chi resta fermo sostiene, se può, una mossa contesa o un vicino minacciato
	for u in unita:
		var o: Array = ordini[u]
		if int(o[0]) != DPAdj.H or vincoli.has(u):
			continue
		var best := 0.0
		var scelto := []
		for w in unita:
			if w == u:
				continue
			var ow: Array = ordini[w]
			if int(ow[0]) == DPAdj.M:
				var d := DPMap.loc_prov[int(ow[1])]
				if d != u and DPMap.tocca(st.ut[u], st.ul[u], d) and _contesa(st, p, d, ost):
					var s := (va[d] if st.ut[w] == 0 else vf[d]) * (1.6 if st.up[d] >= 0 and st.up[d] != p else 1.0)
					if s > best:
						best = s
						scelto = [DPAdj.S, w, d]
			elif DPMap.tocca(st.ut[u], st.ul[u], w) and _contesa(st, p, w, ost):
				var s := (va[w] if st.ut[w] == 0 else vf[w]) * 0.7 + difesa[w] * 600.0
				if s > best:
					best = s
					scelto = [DPAdj.S, w, w]
		# se il proprio posto è un centro minacciato, restare fermi è già una difesa; il sostegno lo
		# si dà comunque (un'unità che sostiene tiene la provincia come una ferma)
		if not scelto.is_empty() and (temp <= 0.0 or rng.randf() < 0.85):
			ordini[u] = scelto
	return ordini


## Quanto conta un bersaglio secondo l'ostilità verso chi lo possiede: con gli amici (patti sinceri)
## non si entra affatto, con i neutrali si va cauti.
static func _freno(o: float) -> float:
	if o < AMICO:
		return 0.01
	return lerpf(0.2, 1.0, clampf((o - AMICO) / 0.4, 0.0, 1.0))


func _scegli(opz: Array, temp: float) -> int:
	if temp <= 0.0 or opz.size() == 1:
		return 0
	var mx: float = maxf(opz[0][0], 1.0)
	var pesi := []
	var tot := 0.0
	for o in opz:
		var w := exp((o[0] - mx) / (mx * temp * 0.35))
		pesi.append(w)
		tot += w
	var r := rng.randf() * tot
	for i in pesi.size():
		r -= pesi[i]
		if r <= 0.0:
			return i
	return 0


## La provincia è occupata da altri o raggiungibile da unità non amiche?
func _contesa(st: DPState, p: int, d: int, ost: PackedFloat32Array) -> bool:
	if st.up[d] >= 0 and st.up[d] != p:
		return true
	for j in DPMap.adj_tutte[d]:
		var q := st.up[j]
		if q >= 0 and q != p and ost[q] > 0.12 and DPMap.tocca(st.ut[j], st.ul[j], d):
			return true
	return false


## Per ogni armata sulla costa: [[provincia di sbarco, flotta che convoglia], …] (convogli con una flotta
## e catene di due flotte, per esempio Londra - Mare del Nord - Norvegia).
func _opzioni_convoglio(st: DPState, p: int, va: PackedFloat32Array, ordini: Dictionary) -> Dictionary:
	var out := {}
	for u in st.unita_di(p):
		if st.ut[u] != 0 or DPMap.tipo[u] != DPMap.COSTA:
			continue
		var l := []
		for f in DPMap.adj_fp[u]:
			if DPMap.tipo[f] == DPMap.MARE and st.up[f] == p and not ordini.has(f):
				for d in DPMap.adj_fp[f]:
					if DPMap.tipo[d] == DPMap.COSTA and d != u and not (DPMap.adj_a[u] as PackedInt32Array).has(d):
						l.append([d, f])
		if not l.is_empty():
			out[u] = l
	return out


## I candidati di una potenza: il primo è il «migliore» senza casualità, gli altri variazioni.
func candidati(st: DPState, p: int, val: Array, ost: PackedFloat32Array, quanti: int,
		vincoli: Dictionary = {}, vietate: Dictionary = {}) -> Array:
	var out := []
	var visti := {}
	var tent := 0
	while out.size() < quanti and tent < quanti * 3:
		var temp := 0.0 if tent == 0 else (0.35 + 0.9 * rng.randf())
		tent += 1
		var c := candidato(st, p, val, ost, temp, vincoli, vietate)
		var k := var_to_str(c).hash()
		if visti.has(k):
			continue
		visti[k] = true
		out.append(c)
	if out.is_empty():
		out.append({})
	return out


# ---------------------------------------------------------------- ricerca

## Sceglie il candidato migliore di p contro campioni degli ordini delle altre potenze.
## pool: per ogni potenza l'elenco dei suoi candidati. pesi_pool: probabilità del primo candidato.
## Restituisce {indice, punteggi, media}.
func scegli(st: DPState, p: int, pool: Array, ctx: Dictionary, campioni: int) -> Dictionary:
	var miei: Array = pool[p]
	var somme := PackedFloat32Array()
	somme.resize(miei.size())
	var minimi := PackedFloat32Array()
	minimi.resize(miei.size())
	minimi.fill(1e9)
	for s in campioni:
		adj.pulisci()
		for q in 7:
			if q == p or (pool[q] as Array).is_empty():
				continue
			var k := 0
			if s > 0 and rng.randf() > 0.4:
				k = rng.randi() % (pool[q] as Array).size()
			adj.carica(pool[q][k])
		for i in miei.size():
			for u in st.unita_di(p):
				adj.ordina(u, DPAdj.H)
			adj.carica(miei[i])
			adj.risolvi(st)
			var v := valuta(st, p, ctx)
			somme[i] += v
			minimi[i] = minf(minimi[i], v)
	var best := 0
	var bv := -1e18
	var punti := []
	var prud: float = ctx.get("prudenza", 0.25)
	for i in miei.size():
		var v := somme[i] / float(campioni) * (1.0 - prud) + minimi[i] * prud
		v += float(ctx.get("bonus", {}).get(i, 0.0))
		punti.append(v)
		if v > bv:
			bv = v
			best = i
	return {"indice": best, "punteggi": punti, "valore": bv}


## Valutazione della posizione che esce dall'ultima risoluzione di adj, per la potenza p.
## ctx: {ost, val, autunno, capo}.
func valuta(st: DPState, p: int, ctx: Dictionary) -> float:
	var n := DPMap.N_PROV
	var ost: PackedFloat32Array = ctx["ost"]
	var val: Array = ctx["val"]
	var va: PackedFloat32Array = val[0]
	var vf: PackedFloat32Array = val[1]
	var autunno: bool = ctx["autunno"]
	_occ.fill(-1)
	var s := 0.0
	for i in n:
		var q := st.up[i]
		if q < 0:
			continue
		if q == p and (adj.ot[i] == DPAdj.M or (adj.ot[i] == DPAdj.S and adj.oa[i] != adj.ob[i])):
			# la parola data: muovere (o sostenere una mossa) contro l'unità o il centro vuoto di un amico
			var dd := DPMap.loc_prov[adj.oa[i]] if adj.ot[i] == DPAdj.M else adj.ob[i]
			var vitt := st.up[dd]
			if vitt < 0 and DPMap.centro[dd] == 1:
				vitt = st.sc[dd]
			if vitt >= 0 and vitt != p and ost[vitt] < AMICO:
				s -= 70.0
		if adj.ot[i] == DPAdj.M and adj.esito[i] == 1:
			var d := DPMap.loc_prov[adj.oa[i]]
			_occ[d] = q
			_occ_t[d] = st.ut[i]
		elif adj.sloggiata[i] < 0:
			_occ[i] = q
			_occ_t[i] = st.ut[i]
		else:
			# unità scacciata
			if q == p:
				s -= 38.0
			else:
				s += 16.0 * ost[q] if st.up[adj.sloggiata[i]] == p else 5.0 * ost[q]
	for c in DPMap.centri:
		var o := st.sc[c]
		var x := _occ[c]
		if autunno:
			var dopo := x if x >= 0 else o
			if dopo == p:
				s += 100.0
				if o >= 0 and o != p and ost[o] < AMICO:
					s -= 150.0          # non si portano via i centri agli amici
			elif dopo >= 0:
				s -= 11.0 * ost[dopo]
				if dopo == ctx.get("capo", -1):
					s -= 30.0
		else:
			if o == p:
				s += 100.0
				if x >= 0 and x != p:
					s -= 62.0 * clampf(ost[x] * 2.0, 0.2, 1.0)
			elif x == p:
				s += 52.0 if (o < 0 or ost[o] >= AMICO) else -40.0
	for i in n:
		if _occ[i] == p:
			s += (va[i] if _occ_t[i] == 0 else vf[i]) * 0.022
			# centri propri lasciati scoperti con nemici accanto
	for c in DPMap.centri:
		if st.sc[c] != p or _occ[c] == p:
			continue
		var m := 0.0
		for j in DPMap.adj_tutte[c]:
			var q := _occ[j]
			if q >= 0 and q != p:
				m += ost[q]
		s -= minf(m, 2.0) * (16.0 if autunno else 34.0) * (1.3 if DPMap.casa_centro[c] == p else 1.0)
	return s


# ---------------------------------------------------------------- ritirate e aggiustamenti

func ritirate(g: DPGame, p: int, val: Array) -> Dictionary:
	var out := {}
	var prese := {}
	for r in g.ritirate_di(p):
		var v: PackedFloat32Array = val[0] if r["t"] == 0 else val[1]
		var best := -1
		var bv := -1.0
		for l in r["opzioni"]:
			var d := DPMap.loc_prov[l]
			if prese.has(d):
				continue
			var s := v[d] + (400.0 if g.st.sc[d] == p else 0.0) + rng.randf() * 5.0
			if DPMap.centro[d] == 1 and g.st.sc[d] != p and g.fase == DPGame.RIT_AUTUNNO:
				s += 1500.0          # ritirarsi su un centro altrui in autunno lo conquista
			if s > bv:
				bv = s
				best = l
		out[r["prov"]] = best
		if best >= 0:
			prese[DPMap.loc_prov[best]] = true
	return out


## Quota di flotte desiderata per potenza (dalle abitudini dei giocatori esperti).
const QUOTA_FLOTTE := [0.15, 0.68, 0.42, 0.28, 0.5, 0.3, 0.45]

func aggiustamenti(g: DPGame, p: int, val: Array, ost: PackedFloat32Array) -> Dictionary:
	var st := g.st
	var d := g.saldo(p)
	if d > 0:
		var c := []
		var libere := Array(g.case_libere(p))
		var nf := 0
		var nu := 0
		for u in st.unita_di(p):
			nu += 1
			nf += st.ut[u]
		for k in d:
			var best := []
			var bv := -1e9
			for pr in libere:
				for t in 2:
					if t == 1 and DPMap.tipo[pr] != DPMap.COSTA:
						continue
					var locs := [pr]
					if t == 1 and not (DPMap.coste_di[pr] as PackedInt32Array).is_empty():
						locs = Array(DPMap.coste_di[pr])
					for l in locs:
						var v: PackedFloat32Array = val[t]
						var s := v[pr]
						for l2 in DPMap.destinazioni(t, l):
							s += v[DPMap.loc_prov[l2]] * 0.6
							for l3 in DPMap.destinazioni(t, l2):
								s += v[DPMap.loc_prov[l3]] * 0.12
						var quota := float(nf + (1 if t == 1 else 0)) / float(nu + 1)
						s *= 1.0 - 0.9 * absf(quota - QUOTA_FLOTTE[p])
						s *= 1.0 + rng.randf() * 0.1
						if s > bv:
							bv = s
							best = [t, l]
			if best.is_empty():
				break
			c.append(best)
			libere.erase(DPMap.loc_prov[best[1]])
			nu += 1
			nf += best[0]
		return {"c": c}
	if d < 0:
		var u := []
		for pr in st.unita_di(p):
			var v: PackedFloat32Array = val[st.ut[pr]]
			var s := v[pr]
			for l2 in DPMap.destinazioni(st.ut[pr], st.ul[pr]):
				s = maxf(s, v[DPMap.loc_prov[l2]] * 0.8)
			if st.sc[pr] == p:
				s += 300.0 + (val[2] as PackedFloat32Array)[pr] * 800.0
			u.append([s, pr])
		u.sort()
		var sc := []
		for k in mini(-d, u.size()):
			sc.append(u[k][1])
		return {"s": sc}
	return {}

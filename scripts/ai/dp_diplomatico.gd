class_name DPDiplomatico
extends RefCounted
## Il diplomatico di una potenza guidata dall'IA: sceglie alleati e bersagli, tratta, mantiene o
## tradisce la parola, valuta di chi fidarsi e decide gli ordini.
##
## I principi vengono dalla letteratura dei giocatori da torneo (Diplomatic Pouch, Diplomacy
## Archive, Diplomacy World):
## - parlare con tutti fin dalla primavera 1901 e tenersi almeno due amici;
## - non combattere su due fronti; attaccare chi è già attaccato da altri;
## - la pugnalata si fa solo se frutta almeno due centri o decide la partita, mai a metà partita
##   per un centro solo, e continuando a rassicurare la vittima fino all'ultimo;
## - la fiducia si costruisce mantenendo le promesse piccole; chi tradisce una volta è segnato;
## - quando una potenza si avvicina ai 18 centri, tutti gli altri fanno fronte comune.

const TIPI_CARATTERE := [
	# nome, lealtà, audacia, doppiezza, rancore
	["leale", 0.85, 0.45, 0.15, 0.7],
	["opportunista", 0.5, 0.6, 0.55, 0.4],
	["volpe", 0.3, 0.5, 0.9, 0.5],
	["mastino", 0.6, 0.9, 0.3, 0.95],
	["prudente", 0.7, 0.2, 0.35, 0.6],
	["calcolatore", 0.55, 0.55, 0.6, 0.3],
]

## Quanto ogni potenza guarda alle altre come primo bersaglio (teoria delle aperture).
const BERSAGLI_NATURALI := [
	[0.0, 0.0, 0.0, 0.05, 0.4, 0.45, 0.5],     # Austria: Turchia, Russia, Italia
	[0.0, 0.0, 0.5, 0.45, 0.0, 0.3, 0.0],      # Inghilterra: Francia, Germania, Russia
	[0.0, 0.5, 0.0, 0.5, 0.25, 0.0, 0.0],      # Francia: Inghilterra, Germania, Italia
	[0.05, 0.4, 0.45, 0.0, 0.0, 0.35, 0.0],    # Germania: Francia, Inghilterra, Russia
	[0.36, 0.0, 0.32, 0.0, 0.0, 0.0, 0.42],    # Italia: Turchia (Lepanto), Austria, Francia
	[0.38, 0.25, 0.0, 0.2, 0.0, 0.0, 0.5],     # Russia: Turchia, Austria, Inghilterra
	[0.38, 0.0, 0.0, 0.0, 0.3, 0.5, 0.0],      # Turchia: Russia, Austria, Italia
]
## Le zone calde del 1901 fra due vicini: buone candidate a restare sgombre.
const ZONE_CALDE := {
	"1-2": ["ENG"], "2-3": ["BUR"], "3-5": ["PRU", "SIL"], "0-5": ["GAL"], "5-6": ["BLA"],
	"0-4": ["TYR"], "2-4": ["PIE"], "0-3": ["TYR", "BOH"], "1-3": ["HEL"],
}

var io := 0
var corte: DPCorte
var rng := RandomNumberGenerator.new()

var carattere := "leale"
var lealta := 0.7
var audacia := 0.5
var doppiezza := 0.4
var rancore := 0.6

var rel := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])      # -1 nemico … +1 amico
var fid := PackedFloat32Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])   # fiducia nella loro parola
var bersaglio := -1
var alleato := -1
var pugnala := -1          # potenza che si sta per tradire (segreto)
var patti: Array = []      # {con, tipo, d, anno, sincero}
var promesse_mie: Array = []    # {a, u, o, sincera}
var promesse_loro: Array = []   # {da, u, o}
var rifiuti := {}          # "potenza:tipo" -> anno dell'ultimo rifiuto
var guerra_da := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])   # anno dell'ultimo scontro
var tradito_da := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])  # anno in cui mi hanno tradito
var appello := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])     # anno dell'ultimo appello alla coalizione
var apertura := ""
var diario: Array = []     # ragionamenti dell'IA (si leggono negli archivi a fine partita)
var _inviati := 0


func crea(p: int, c: DPCorte, seme: int) -> void:
	io = p
	corte = c
	rng.seed = seme
	var t: Array = TIPI_CARATTERE[rng.randi() % TIPI_CARATTERE.size()]
	carattere = t[0]
	lealta = clampf(t[1] + rng.randf_range(-0.1, 0.1), 0.05, 0.95)
	audacia = clampf(t[2] + rng.randf_range(-0.1, 0.1), 0.05, 0.95)
	doppiezza = clampf(t[3] + rng.randf_range(-0.1, 0.1), 0.05, 0.95)
	rancore = clampf(t[4] + rng.randf_range(-0.1, 0.1), 0.05, 0.95)
	if corte.livello == 0:
		# il Console è ingenuo: si fida, tradisce di rado
		doppiezza *= 0.4
		lealta = minf(0.95, lealta + 0.2)


func g() -> DPGame:
	return corte.g


func nota(s: String) -> void:
	diario.append("%s: %s" % [g().nome_fase(), s])
	if diario.size() > 120:
		diario.pop_front()


# ------------------------------------------------------------------ patti

func ha_patto(q: int, tipo := "") -> bool:
	for p in patti:
		if p["con"] == q and (tipo == "" or p["tipo"] == tipo):
			return true
	return false


func amico(q: int) -> bool:
	return ha_patto(q, "pace") or ha_patto(q, "alleanza")


func patto_sincero(q: int) -> bool:
	for p in patti:
		if p["con"] == q and p["sincero"] and p["tipo"] != "dmz":
			return true
	return false


func _firma(q: int, tipo: String, d: Dictionary, sincero: bool) -> void:
	if sincero and tipo != "dmz" and q == bersaglio:
		bersaglio = -1            # si è fatta la pace con il nemico di ieri
	for p in patti:
		if p["con"] == q and p["tipo"] == tipo and (tipo != "dmz" or p["d"] == d):
			p["sincero"] = sincero
			p["anno"] = g().anno
			return
	patti.append({"con": q, "tipo": tipo, "d": d, "anno": g().anno, "sincero": sincero})


func _rompi(q: int) -> void:
	var r := []
	for p in patti:
		if p["con"] != q:
			r.append(p)
	patti = r


## Province che ci si è impegnati sinceramente a lasciare sgombre.
func zone_sgombre() -> Dictionary:
	var o := {}
	for p in patti:
		if p["tipo"] == "dmz" and p["sincero"] and p["con"] != pugnala:
			for pr in p["d"]["prov"]:
				o[int(pr)] = 0.04
	return o


# ------------------------------------------------------------------ strategia

func vicino(q: int) -> bool:
	var st := g().st
	for u in st.unita_di(io):
		for c in DPMap.centri:
			if st.sc[c] == q and DPMap.dist_q[u][c] <= 2:
				return true
	for u in st.unita_di(q):
		for c in DPMap.centri:
			if st.sc[c] == io and DPMap.dist_q[u][c] <= 2:
				return true
	return false


func capo() -> int:
	var c := g().st.conta_centri()
	var best := -1
	var mx := 0
	for q in 7:
		if c[q] > mx:
			mx = c[q]
			best = q
	return best


## La potenza che minaccia di vincere (e contro cui fare fronte comune), -1 se nessuna.
func minaccia() -> int:
	var c := g().st.conta_centri()
	var k := capo()
	if k < 0:
		return -1
	var secondo := 0
	for q in 7:
		if q != k:
			secondo = maxi(secondo, c[q])
	if c[k] >= 13 or (c[k] >= 10 and c[k] - secondo >= 3):
		return k
	return -1


func punteggio_bersaglio(q: int) -> float:
	var st := g().st
	if q == io or not g().viva(q):
		return -99.0
	var s: float = BERSAGLI_NATURALI[io][q] * (1.2 if g().anno <= 1903 else 0.5)
	if not vicino(q):
		s -= 1.5
	# forze al confine: le mie contro le sue
	var mie := 0
	var sue := 0
	for u in st.unita_di(io):
		for c in DPMap.centri:
			if st.sc[c] == q and DPMap.dist_q[u][c] <= 2:
				mie += 1
				break
	for u in st.unita_di(q):
		for c in DPMap.centri:
			if st.sc[c] == io and DPMap.dist_q[u][c] <= 2:
				sue += 1
				break
	s += 0.12 * float(mie - sue)
	# chi è già attaccato da altri è una preda più facile
	var gia := 0.0
	for x in 7:
		if x != io and x != q:
			gia += 0.15 * minf(corte.aggr[x][q], 2.0)
	s += minf(gia, 0.3)
	s += 0.25 * minf(corte.aggr[q][io], 3.0)        # chi mi attacca
	s -= 0.5 * rel[q]
	if patto_sincero(q):
		s -= 0.45 * lealta + 0.25
	var nc := st.conta_centri()
	if q == minaccia():
		s += 1.5
	elif nc[q] <= 2:
		s += 0.25          # finire chi è in ginocchio
	return s


func aggiorna_strategia() -> void:
	var best := -1
	var bv := -98.0
	var punti := []
	for q in 7:
		var s := punteggio_bersaglio(q) + rng.randf() * 0.15
		punti.append(s)
		if patto_sincero(q) and q != minaccia():
			continue
		if s > bv:
			bv = s
			best = q
	var vecchio := bersaglio
	if bersaglio >= 0 and g().viva(bersaglio) and vicino(bersaglio) and punti[bersaglio] > bv - 0.35 \
			and not patto_sincero(bersaglio):
		best = bersaglio          # non si cambia nemico a ogni stagione
	if best >= 0 and bv < -0.6 and best != minaccia():
		best = -1                 # nessun bersaglio conveniente: si consolida
	if best >= 0 and patto_sincero(best):
		# chi sta per vincere va fermato: il patto si disdice apertamente
		nota("disdico il patto con %s, che sta per vincere" % DPMap.POTENZE_BREVI[best])
		_rompi(best)
		_manda(best, "nota", {"k": "disdetta"})
	if best < 0 and g().anno >= 1903 and g().fase == DPGame.PRIMAVERA:
		# tutti i vicini sono amici: i leali disdicono un patto alla luce del sole, gli altri aspettano l'occasione
		var cand := -1
		var cv := -98.0
		for q in 7:
			if q != io and g().viva(q) and vicino(q) and patto_sincero(q) and not ha_patto(q, "alleanza") and punti[q] > cv:
				cv = punti[q]
				cand = q
		if cand >= 0 and cv > -0.2 and lealta > 0.6 and rng.randf() < 0.35:
			nota("disdico apertamente il patto con %s" % DPMap.POTENZE_BREVI[cand])
			_rompi(cand)
			rel[cand] -= 0.25
			_manda(cand, "nota", {"k": "disdetta"})
	bersaglio = best
	if bersaglio != vecchio and bersaglio >= 0:
		nota("nuovo bersaglio: %s" % DPMap.POTENZE_BREVI[bersaglio])
	# l'alleato: un vicino del bersaglio (o mio) con cui i rapporti sono buoni
	var ba := -1
	var bva := -9.0
	for q in 7:
		if q == io or q == bersaglio or not g().viva(q):
			continue
		var s: float = rel[q] * 1.2 + fid[q] * 0.6 - float(punti[q]) * 0.5
		if ha_patto(q, "alleanza"):
			s += 0.6
		if bersaglio >= 0 and _confinano(q, bersaglio):
			s += 0.5
		if vicino(q):
			s += 0.15
		s += rng.randf() * 0.1
		if s > bva:
			bva = s
			ba = q
	alleato = ba


func _confinano(a: int, b: int) -> bool:
	var st := g().st
	for u in st.unita_di(a):
		for c in DPMap.centri:
			if st.sc[c] == b and DPMap.dist_q[u][c] <= 2:
				return true
	return false


## L'ostilità verso ogni potenza usata dal motore tattico.
func ostilita() -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(7)
	for q in 7:
		var r := rel[q]
		var v := clampf(0.55 - 0.55 * r, 0.03, 1.0)
		if amico(q) and patto_sincero(q):
			v = minf(v, 0.22 if ha_patto(q, "alleanza") else 0.32)
			# la fiducia scarsa tiene alta la guardia anche con gli amici (ma senza attaccarli)
			v = minf(maxf(v, 0.45 - 0.5 * fid[q]), DPTattica.AMICO - 0.02)
		if q == bersaglio:
			v = maxf(v, 0.9)
		if q == pugnala:
			v = 1.0
		if q == minaccia() and q != io:
			v = maxf(v, 0.85)
		o[q] = v
	o[io] = 0.0
	return o


# ------------------------------------------------------------------ messaggi in uscita

func _manda(a: int, tipo: String, d: Dictionary, sincero := true, rif := -1) -> void:
	if a == io or a < 0 or not g().viva(a):
		return
	_inviati += 1
	corte.spedisci({"da": io, "a": a, "tipo": tipo, "d": d, "sincero": sincero, "rif": rif, "v": rng.randi() % 12})


func _rifiutato_di_recente(q: int, tipo: String) -> bool:
	return g().anno - int(rifiuti.get("%d:%s" % [q, tipo], -99)) < 2


## Inizio di una fase di movimento: prima tutti aggiornano la strategia…
func prepara_fase() -> void:
	_inviati = 0
	pugnala = -1
	for q in 7:
		rel[q] *= 0.985
	# le guerre senza scontri da due anni si raffreddano
	for q in 7:
		if rel[q] < -0.3 and g().anno - guerra_da[q] >= 2:
			rel[q] += 0.2
	# i patti invecchiano: le zone sgombre durano due anni
	var vivi := []
	for p in patti:
		if p["tipo"] == "dmz" and g().anno - int(p["anno"]) >= 2:
			continue
		if not g().viva(p["con"]):
			continue
		vivi.append(p)
	patti = vivi
	# chi sta per vincere e chi non merita più fiducia: i patti si disdicono alla luce del sole
	# (i più doppi invece tacciono e si tengono le mani libere)
	var m0 := minaccia()
	for q in 7:
		if q == io or not g().viva(q) or not patto_sincero(q):
			continue
		if (q == m0 and m0 != io) or fid[q] < 0.25:
			if doppiezza < 0.6 or q == m0:
				nota("disdico il patto con %s" % DPMap.POTENZE_BREVI[q])
				_rompi(q)
				_manda(q, "nota", {"k": "disdetta"})
			else:
				for p in patti:
					if p["con"] == q:
						p["sincero"] = false
	# fidarsi ma verificare: un amico con unità a ridosso dei miei centri di casa perde credito
	var st := g().st
	for q in 7:
		if q == io or not amico(q):
			continue
		for u in st.unita_di(q):
			var vicina := false
			for c in DPMap.case_di[io]:
				if st.sc[c] == io and DPMap.tocca(st.ut[u], st.ul[u], c):
					vicina = true
			if vicina:
				fid[q] = maxf(0.2, fid[q] - 0.07)
	aggiorna_strategia()


## … poi partono le proposte.
func proposte() -> void:
	var m := minaccia()
	var primo_anno := g().anno == 1901 and g().fase == DPGame.PRIMAVERA
	# fronte comune contro chi sta per vincere
	if m >= 0 and m != io:
		for q in 7:
			if q != io and q != m and g().viva(q) and not _alleati_contro(q, m) and not _rifiutato_di_recente(q, "alleanza"):
				if rel[q] < 0.0:
					rel[q] = 0.0
				if appello[q] < g().anno:
					appello[q] = g().anno
					_manda(q, "nota", {"k": "coalizione", "x": DPTesti.CON_ARTICOLO[m]})
					_manda(q, "alleanza", {"contro": m}, true)
	# alleanza contro il bersaglio
	if bersaglio >= 0 and alleato >= 0 and not ha_patto(alleato, "alleanza") and not _rifiutato_di_recente(alleato, "alleanza") \
			and _confinano(alleato, bersaglio) and rng.randf() < 0.85:
		_manda(alleato, "alleanza", {"contro": bersaglio}, true)
	# pace con gli altri vicini; con il bersaglio, solo per addormentarlo
	for q in 7:
		if q == io or not g().viva(q) or not vicino(q) or amico(q) or _rifiutato_di_recente(q, "pace") or _bruciato(q):
			continue
		if q == bersaglio:
			if guerra_da[q] == 0 and g().anno - int(rifiuti.get("inganno:%d" % q, -99)) >= 3 and rng.randf() < _malafede(q) * 1.2:
				rifiuti["inganno:%d" % q] = g().anno
				nota("offro pace a %s solo per coprire l'attacco" % DPMap.POTENZE_BREVI[q])
				_manda(q, "pace", {}, false)
		elif rel[q] > -0.3 and rng.randf() < (0.7 if primo_anno else 0.35):
			_manda(q, "pace", {}, true)
		elif rel[q] <= -0.3 and _fronti() >= 2 and rng.randf() < 0.5:
			# due guerre sono troppe: si cerca la tregua con il nemico meno pericoloso
			_manda(q, "pace", {"tregua": true}, true)
	# zone sgombre del 1901
	if primo_anno:
		for q in 7:
			if q == io or q == bersaglio:
				continue
			var k := "%d-%d" % [mini(io, q), maxi(io, q)]
			if ZONE_CALDE.has(k) and rng.randf() < 0.55:
				var pr := []
				for s in ZONE_CALDE[k]:
					pr.append(DPMap.per_sigla[s])
				_manda(q, "dmz", {"prov": pr}, true)
	# chi è in testa semina zizzania
	if capo() == io and g().anno >= 1903 and rng.randf() < doppiezza:
		var vittime := []
		for q in 7:
			if q != io and g().viva(q):
				vittime.append(q)
		if vittime.size() >= 2:
			vittime.shuffle()
			nota("semino zizzania fra %s e %s" % [DPMap.POTENZE_BREVI[vittime[0]], DPMap.POTENZE_BREVI[vittime[1]]])
			_manda(vittime[0], "info", {"su": vittime[1]}, false)


func _alleati_contro(q: int, x: int) -> bool:
	for p in patti:
		if p["con"] == q and p["tipo"] == "alleanza" and int(p["d"].get("contro", -1)) == x:
			return true
	return false


## Quanti nemici ho alle porte.
func _fronti() -> int:
	var n := 0
	for q in 7:
		if q != io and g().viva(q) and rel[q] < -0.3 and vicino(q):
			n += 1
	return n


## Dopo i patti: richieste e offerte di sostegno sugli ordini di questo turno.
func richieste_tattiche() -> void:
	if g().anno == 1901 and g().fase == DPGame.PRIMAVERA:
		return
	var st := g().st
	var ost := ostilita()
	var val: Array = corte.tat.valori(st, io, ost, g().fase == DPGame.AUTUNNO, g().anno)
	var piano: Dictionary = corte.tat.candidato(st, io, val, ost, 0.0, {}, zone_sgombre())
	var chieste := 0
	for u in piano:
		var o: Array = piano[u]
		if int(o[0]) != DPAdj.M or chieste >= 2:
			continue
		var d := DPMap.loc_prov[int(o[1])]
		var occupata := st.up[d] >= 0 and st.up[d] != io
		if not occupata and not (DPMap.centro[d] == 1 and st.sc[d] != io):
			continue
		# c'è già un mio sostegno?
		var mio := false
		for w in piano:
			if int(piano[w][0]) == DPAdj.S and int(piano[w][1]) == u:
				mio = true
		if mio and not occupata:
			continue
		for w in DPMap.adj_tutte[d]:
			var q := st.up[w]
			if q < 0 or q == io or q == st.up[d] or q == st.sc[d]:
				continue
			if not amico(q) or rel[q] < 0.15 or not DPMap.tocca(st.ut[w], st.ul[w], d):
				continue
			_manda(q, "chiedi_sost", {"u": w, "a": u, "b": d}, q != pugnala)
			chieste += 1
			break
	# offerta a un alleato: «attaccate lì, io sostengo»
	if alleato >= 0 and ha_patto(alleato, "alleanza") and bersaglio >= 0 and rng.randf() < 0.7:
		for a in st.unita_di(alleato):
			var fatto := false
			for l in DPMap.destinazioni(st.ut[a], st.ul[a]):
				var d := DPMap.loc_prov[l]
				if not (st.up[d] == bersaglio or (st.sc[d] == bersaglio and DPMap.centro[d] == 1)):
					continue
				for u in st.unita_di(io):
					if int(piano.get(u, [0])[0]) == DPAdj.H and DPMap.tocca(st.ut[u], st.ul[u], d):
						_manda(alleato, "offri_sost", {"u": u, "a": a, "b": d}, true)
						fatto = true
						break
				if fatto:
					break
			if fatto:
				break


# ------------------------------------------------------------------ messaggi in arrivo

func ricevi(m: Dictionary) -> void:
	var q: int = m["da"]
	var tipo: String = m["tipo"]
	var d: Dictionary = m.get("d", {})
	var st := g().st
	match tipo:
		"alleanza":
			var x := int(d["contro"])
			var r := _valuta_alleanza(q, x)
			_rispondi(m, r[0], r[1])
			if r[0]:
				_firma(q, "alleanza", {"contro": x}, r[1])
				_firma(q, "pace", {}, r[1])
				if r[1]:
					rel[q] = minf(1.0, rel[q] + 0.3)
					if not patto_sincero(x) and (bersaglio < 0 or punteggio_bersaglio(x) > punteggio_bersaglio(bersaglio) - 0.3):
						bersaglio = x
					alleato = q if alleato < 0 or rel[q] >= rel[alleato] else alleato
			elif x != io and x >= 0 and patto_sincero(x) and rng.randf() < 0.5 + 0.4 * lealta:
				# si avverte l'amico: è così che si costruisce la fiducia
				_manda(x, "info", {"su": q}, true)
		"pace":
			var r := _valuta_pace(q)
			_rispondi(m, r[0], r[1])
			if r[0]:
				_firma(q, "pace", {}, r[1])
				if r[1]:
					rel[q] = clampf(rel[q] + 0.2, 0.05, 1.0)
		"dmz":
			var r := _valuta_dmz(q, d["prov"])
			_rispondi(m, r[0], r[1])
			if r[0]:
				_firma(q, "dmz", {"prov": d["prov"]}, r[1])
				if r[1]:
					rel[q] = minf(1.0, rel[q] + 0.08)
		"chiedi_sost":
			# q chiede che la mia unità u sostenga la sua unità a verso b
			var u := int(d["u"])
			var a := int(d["a"])
			var b := int(d["b"])
			var r := _valuta_sostegno(q, u, a, b)
			_rispondi(m, r[0], r[1])
			if r[0]:
				promesse_mie.append({"a": q, "u": u, "o": [DPAdj.S, a, b], "sincera": r[1]})
				promesse_loro.append({"da": q, "u": a, "o": [DPAdj.H, -1, -1] if a == b else [DPAdj.M, b, 0]})
		"offri_sost":
			# q offre che la sua u sostenga la mia a verso b
			var u := int(d["u"])
			var a := int(d["a"])
			var b := int(d["b"])
			var ok := st.up[a] == io and q != bersaglio and rel[q] > -0.2
			if ok and a != b:
				# accetto se la mossa non colpisce un amico
				var vitt := st.up[b] if st.up[b] >= 0 else st.sc[b]
				if vitt == io or (vitt >= 0 and amico(vitt) and patto_sincero(vitt) and vitt != pugnala):
					ok = false
			_rispondi(m, ok, ok)
			if ok:
				promesse_loro.append({"da": q, "u": u, "o": [DPAdj.S, a, b]})
				promesse_mie.append({"a": q, "u": a, "o": [DPAdj.H, -1, -1] if a == b else [DPAdj.M, b, 0], "sincera": true})
		"chiedi_mossa":
			var u := int(d["u"])
			var o: Array = d["o"]
			var ok := st.up[u] == io and amico(q) and rel[q] > 0.2 and q != bersaglio
			if ok and int(o[0]) == DPAdj.M:
				var dest := DPMap.loc_prov[int(o[1])]
				var vitt := st.up[dest] if st.up[dest] >= 0 else st.sc[dest]
				if vitt == io or (vitt >= 0 and vitt != q and amico(vitt) and patto_sincero(vitt)):
					ok = false
				if not DPMap.puo_muovere(st.ut[u], st.ul[u], int(o[1])):
					ok = false
			var sinc := ok and q != pugnala
			if not ok and (q == bersaglio or q == pugnala) and rng.randf() < _malafede(q):
				ok = true
				sinc = false
			_rispondi(m, ok, sinc)
			if ok:
				promesse_mie.append({"a": q, "u": u, "o": o, "sincera": sinc})
		"info":
			var x := int(d["su"])
			if x != io and x >= 0:
				rel[x] -= 0.22 * fid[q]
				nota("%s mi dice che %s trama contro di me (ci credo al %d%%)" % [DPMap.POTENZE_BREVI[q], DPMap.POTENZE_BREVI[x], int(fid[q] * 100)])
		"pareggio":
			_rispondi(m, corte.voto_pareggio_ia(io), true)
		"risposta":
			_ricevi_risposta(m)
		"nota":
			var k: String = d.get("k", "")
			if k == "disdetta":
				# il patto è sciolto lealmente: nessun tradimento, ma d'ora in poi ci si guarda
				_rompi(q)
				rel[q] = minf(rel[q], 0.0) - 0.15
			if k == "denuncia" and d.has("chi"):
				var x := int(d["chi"])
				if x != io:
					fid[x] = maxf(0.05, fid[x] - 0.12 * fid[q])
		"libero":
			if corte.umano[q]:
				_manda(q, "nota", {"k": "libero"})


func _rispondi(m: Dictionary, si: bool, sincero: bool) -> void:
	if not si:
		pass
	_manda(m["da"], "risposta", {"si": si}, sincero, int(m.get("id", -1)))


func _ricevi_risposta(m: Dictionary) -> void:
	var q: int = m["da"]
	var orig = corte.messaggio(int(m.get("rif", -1)))
	if orig == null or orig["da"] != io:
		return
	var si: bool = m["d"].get("si", false)
	var tipo: String = orig["tipo"]
	var d: Dictionary = orig.get("d", {})
	var sinc: bool = orig.get("sincero", true)
	if not si:
		rifiuti["%d:%s" % [q, tipo]] = g().anno
		rel[q] -= 0.04
		return
	match tipo:
		"alleanza":
			_firma(q, "alleanza", {"contro": int(d["contro"])}, sinc)
			_firma(q, "pace", {}, sinc)
			if sinc:
				rel[q] = minf(1.0, rel[q] + 0.3)
		"pace":
			_firma(q, "pace", {}, sinc)
			if sinc:
				rel[q] = clampf(rel[q] + 0.2, 0.05, 1.0)
		"dmz":
			_firma(q, "dmz", {"prov": d["prov"]}, sinc)
		"chiedi_sost":
			promesse_loro.append({"da": q, "u": int(d["u"]), "o": [DPAdj.S, int(d["a"]), int(d["b"])]})
			var a := int(d["a"])
			var b := int(d["b"])
			promesse_mie.append({"a": q, "u": a, "o": [DPAdj.H, -1, -1] if a == b else [DPAdj.M, b, 0], "sincera": sinc})
		"offri_sost":
			var a := int(d["a"])
			var b := int(d["b"])
			promesse_mie.append({"a": q, "u": int(d["u"]), "o": [DPAdj.S, a, b], "sincera": sinc})
			promesse_loro.append({"da": q, "u": a, "o": [DPAdj.H, -1, -1] if a == b else [DPAdj.M, b, 0]})


func _valuta_alleanza(q: int, x: int) -> Array:
	if x == io or not g().viva(x):
		return [false, false]
	if _bruciato(q) and x != minaccia():
		return [false, false]
	if q == bersaglio or q == pugnala:
		if rng.randf() < _malafede(q):
			nota("fingo di allearmi con %s" % DPMap.POTENZE_BREVI[q])
			return [true, false]
		return [false, false]
	if x == minaccia():
		return [true, true]
	if patto_sincero(x):
		return [false, false]
	if x == bersaglio:
		return [true, true]
	if rel[q] < -0.25 or fid[q] < 0.2:
		return [false, false]
	var conv := punteggio_bersaglio(x)
	var att := punteggio_bersaglio(bersaglio) if bersaglio >= 0 else -0.3
	if conv > att - 0.45:
		return [true, true]
	return [false, false]


## Probabilità di dare la parola in malafede a q. I giocatori da torneo mentono di rado e solo quando
## conta: a guerra ormai aperta nessuno ci crederebbe, e una reputazione rovinata costa cara.
func _malafede(q: int) -> float:
	if guerra_da[q] > 0 and g().anno - guerra_da[q] < 3:
		return 0.0
	return doppiezza * doppiezza * 0.55


## Chi mi ha tradito da poco non ha più credito (salvo il fronte comune contro chi sta per vincere).
func _bruciato(q: int) -> bool:
	return tradito_da[q] > 0 and g().anno - tradito_da[q] < 3 + int(rancore * 3.0)


func _valuta_pace(q: int) -> Array:
	if _bruciato(q) and not (minaccia() >= 0 and minaccia() != q and minaccia() != io):
		return [false, false]
	if q == bersaglio or q == pugnala:
		# in guerra aperta e in vantaggio non si tratta; altrimenti si può fingere
		if _fronti() >= 2 and corte.aggr[io][q] < 1.0 and rel[q] > -0.7:
			bersaglio = -1
			return [true, true]
		if rng.randf() < _malafede(q):
			nota("accetto la pace di %s senza intenzione di rispettarla" % DPMap.POTENZE_BREVI[q])
			return [true, false]
		return [false, false]
	if rel[q] < -0.55 and corte.aggr[q][io] > 1.0 and _fronti() < 2:
		return [false, false]
	if fid[q] < 0.15:
		return [false, false]
	return [true, true]


func _valuta_dmz(q: int, prov: Array) -> Array:
	for pr in prov:
		if g().st.sc[int(pr)] == io or DPMap.casa[int(pr)] == io and g().st.up[int(pr)] == io:
			return [false, false]
	if q == bersaglio or q == pugnala:
		return [rng.randf() < _malafede(q), false]
	if rel[q] < -0.3:
		return [false, false]
	return [true, true]


func _valuta_sostegno(q: int, u: int, a: int, b: int) -> Array:
	var st := g().st
	if st.up[u] != io or st.up[a] != q or not DPMap.tocca(st.ut[u], st.ul[u], b):
		return [false, false]
	var vitt := st.up[b] if (st.up[b] >= 0 and b != a) else (st.sc[b] if b != a else -1)
	if vitt == io:
		return [false, false]
	if q == bersaglio or q == pugnala:
		# la promessa di un sostegno che non arriverà: il tradimento più crudele
		if rng.randf() < _malafede(q) * 1.3:
			nota("prometto a %s un sostegno che non darò" % DPMap.POTENZE_BREVI[q])
			return [true, false]
		return [false, false]
	if vitt >= 0 and vitt != q and patto_sincero(vitt) and vitt != pugnala and vitt != bersaglio:
		return [false, false]
	if rel[q] < 0.1 or not amico(q):
		return [rel[q] > -0.1 and vitt == bersaglio and vitt >= 0, true]
	# l'unità serve altrove? se il suo posto è un mio centro minacciato resta comunque (sostenere non muove)
	return [true, true]


# ------------------------------------------------------------------ ordini

## Gli ordini di movimento. pool_pubblico: i candidati stimati di ogni potenza.
func decidi_ordini(pool_pubblico: Array) -> Dictionary:
	var st := g().st
	var aut := g().fase == DPGame.AUTUNNO
	if g().anno == 1901 and g().fase == DPGame.PRIMAVERA:
		return _apertura()
	var ost := ostilita()
	var pool := _pool_altri(pool_pubblico)
	var vinc := _vincoli(-1)
	var leale := _cerca(ost, vinc, pool, aut)
	var scelta: Dictionary = leale["ordini"]
	# pugnalata?
	if corte.livello >= 1:
		var migliore := -1
		var mg := 0.0
		for q in 7:
			if q == io or not g().viva(q) or not patto_sincero(q) or not vicino(q):
				continue
			var ost2 := ost.duplicate()
			ost2[q] = 1.0
			var trad := _cerca(ost2, _vincoli(q), pool, aut)
			var gain := _confronta(leale["ordini"], trad["ordini"], pool, aut)
			var soglia := _soglia_pugnalata(q)
			nota("pugnalare %s? guadagno %.1f centri, soglia %.1f" % [DPMap.POTENZE_BREVI[q], gain, soglia])
			if gain >= soglia and gain - soglia > mg:
				mg = gain - soglia
				migliore = q
				scelta = trad["ordini"]
		if migliore >= 0:
			pugnala = migliore
			nota("PUGNALO %s" % DPMap.POTENZE_BREVI[migliore])
	return scelta


func _apertura() -> Dictionary:
	var libro: Array = DPAperture.LIBRO[io]
	var pesi := []
	var tot := 0.0
	var sgombre := zone_sgombre()
	for a in libro:
		var w := float(a["peso"])
		for x in a["contro"]:
			if x == bersaglio:
				w *= 2.6
			elif patto_sincero(x):
				w *= 0.04
			elif rel[x] > 0.1:
				w *= 0.4
		for x in a.get("diffida", []):
			if patto_sincero(x) and fid[x] > 0.55:
				w *= 0.5
		if bersaglio >= 0 and not (a["contro"] as Array).has(bersaglio) and not (a["contro"] as Array).is_empty():
			w *= 0.5
		var ord := DPAperture.ordini(a["o"])
		for pr in DPAperture.entra(ord):
			if sgombre.has(pr):
				w *= 0.03
		pesi.append(w)
		tot += w
	var r := rng.randf() * tot
	var k := 0
	for i in pesi.size():
		r -= pesi[i]
		if r <= 0.0:
			k = i
			break
	apertura = libro[k]["nome"]
	nota("apertura: %s" % apertura)
	return DPAperture.ordini(libro[k]["o"])


## Gli ordini promessi sinceramente (escluse le promesse a chi si sta tradendo).
func _vincoli(tradito: int) -> Dictionary:
	var v := {}
	for p in promesse_mie:
		if p["sincera"] and p["a"] != tradito and not v.has(p["u"]) and g().st.up[p["u"]] == io:
			v[p["u"]] = p["o"]
	return v


## I candidati delle altre potenze come li immagino io: chi mi ha promesso un ordine, se mi fido, lo esegue.
func _pool_altri(pool_pubblico: Array) -> Array:
	var st := g().st
	var pool := pool_pubblico.duplicate()
	for q in 7:
		if q == io or st.n_unita(q) == 0:
			continue
		var vq := {}
		for p in promesse_loro:
			if p["da"] == q and st.up[p["u"]] == q:
				vq[p["u"]] = p["o"]
		var amichevole := amico(q) and fid[q] >= 0.45
		if vq.is_empty() and not amichevole:
			continue
		var oq: PackedFloat32Array = corte.ost_pubblica(q).duplicate()
		if amichevole:
			oq[io] = minf(oq[io], 0.15)
		var valq: Array = corte.tat.valori(st, q, oq, g().fase == DPGame.AUTUNNO, g().anno)
		var mio: Array = corte.tat.candidati(st, q, valq, oq, 4, vq if fid[q] >= 0.35 else {})
		# fidarsi è bene, ma si tiene sempre conto anche dell'ipotesi peggiore
		mio.append_array((pool_pubblico[q] as Array).slice(0, 1 if fid[q] >= 0.8 else (2 if fid[q] >= 0.6 else 3)))
		pool[q] = mio
	return pool


func _cerca(ost: PackedFloat32Array, vinc: Dictionary, pool: Array, aut: bool) -> Dictionary:
	var st := g().st
	var extra := {}
	var val: Array = corte.tat.valori(st, io, ost, aut, g().anno, extra)
	var quanti: int = [6, 16, 28][corte.livello]
	var camp: int = [3, 8, 14][corte.livello]
	var cand: Array = corte.tat.candidati(st, io, val, ost, quanti, vinc, zone_sgombre())
	var p2 := pool.duplicate()
	p2[io] = cand
	var ctx := {"ost": ost, "val": val, "autunno": aut, "capo": minaccia(), "prudenza": 0.12 + 0.3 * (1.0 - audacia)}
	var r: Dictionary = corte.tat.scegli(st, io, p2, ctx, camp)
	return {"ordini": cand[r["indice"]], "valore": r["valore"]}


## Di quanti centri l'insieme di ordini b è meglio di a (misurati con lo stesso metro).
func _confronta(a: Dictionary, b: Dictionary, pool: Array, aut: bool) -> float:
	var st := g().st
	var neutro := PackedFloat32Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	var val: Array = corte.tat.valori(st, io, neutro, aut, g().anno)
	var p2 := pool.duplicate()
	p2[io] = [a, b]
	var ctx := {"ost": neutro, "val": val, "autunno": aut, "capo": -1, "prudenza": 0.3}
	var r: Dictionary = corte.tat.scegli(st, io, p2, ctx, 10)
	return (r["punteggi"][1] - r["punteggi"][0]) / (100.0 if aut else 52.0)


func _soglia_pugnalata(q: int) -> float:
	var nc := g().st.conta_centri()
	var s := 0.95 + 1.0 * lealta - 0.5 * audacia
	if g().anno <= 1902:
		s += 0.5                       # il «blitz» d'apertura è solo per gli audaci
	if _fronti() >= 1:
		s += 0.6                       # mai due guerre insieme
	if bersaglio >= 0 and bersaglio != q and g().viva(bersaglio) and nc[bersaglio] >= 4:
		s += 0.35                      # il nemico comune è ancora forte: l'alleato serve
	if nc[io] >= 11:
		s -= 0.5                       # la corsa finale ai 18 centri
	if q == minaccia():
		s -= 0.8
	if fid[q] < 0.3:
		s -= 0.4                       # meglio colpire per primi chi sta per colpire
	if nc[q] <= 3:
		s -= 0.2
	if bersaglio < 0 and g().anno >= 1903:
		s -= 0.35                      # nessun altro fronte possibile: l'occasione fa l'uomo ladro
	# niente pugnalate da un centro solo, se non per chiudere la partita
	return maxf(s, 0.8 if nc[io] >= 14 else 1.15)


# ------------------------------------------------------------------ dopo la risoluzione

func dopo_risoluzione(voce: Dictionary) -> void:
	if not voce.has("ordini"):
		return
	var prima := DPState.from_dict(voce["prima"])
	var ordini: Dictionary = voce["ordini"]
	# chi mi ha attaccato
	var colpi := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var zone := {}
	for p in patti:
		if p["tipo"] == "dmz":
			for pr in p["d"]["prov"]:
				zone[int(pr)] = p["con"]
	var violate := {}
	for u in ordini:
		var x := prima.up[u]
		if x < 0 or x == io:
			continue
		var o: Array = ordini[u]
		var dest := -1
		if int(o[0]) == DPAdj.M and int(voce["esiti"][u]) != DPGame.E_NULLO:
			dest = DPMap.loc_prov[int(o[1])]
			if zone.get(dest, -1) == x:
				violate[x] = dest
		elif int(o[0]) == DPAdj.S and int(o[1]) != int(o[2]):
			dest = int(o[2])
			if prima.up[int(o[1])] == io:
				dest = -1            # sosteneva una mia mossa
		if dest >= 0 and (prima.up[dest] == io or (prima.up[dest] < 0 and prima.sc[dest] == io and DPMap.centro[dest] == 1)):
			colpi[x] += 1
	# se sono stato io ad attaccare qualcuno, fra noi ogni patto è finito anche per me
	for u in ordini:
		if prima.up[u] != io:
			continue
		var o: Array = ordini[u]
		var dest := -1
		if int(o[0]) == DPAdj.M and int(voce["esiti"][u]) != DPGame.E_NULLO:
			dest = DPMap.loc_prov[int(o[1])]
		elif int(o[0]) == DPAdj.S and int(o[1]) != int(o[2]):
			dest = int(o[2])
		if dest < 0:
			continue
		var vitt := prima.up[dest]
		if vitt < 0 and DPMap.centro[dest] == 1:
			vitt = prima.sc[dest]
		if vitt >= 0 and vitt != io and vitt != pugnala and ha_patto(vitt):
			guerra_da[vitt] = g().anno
			_rompi(vitt)
	for x in 7:
		if x == io:
			continue
		if colpi[x] > 0:
			guerra_da[x] = g().anno
			if amico(x):
				nota("TRADITO da %s (%s)" % [DPMap.POTENZE_BREVI[x], corte.intenzioni.get("%d-%d" % [x, io], "persona")])
				fid[x] = minf(fid[x], 0.12)
				rel[x] = -0.85
				tradito_da[x] = g().anno
				_rompi(x)
				_manda(x, "nota", {"k": "tradimento"})
				var avvisati := 0
				for z in 7:
					if z != io and z != x and g().viva(z) and rel[z] > -0.2 and avvisati < 3:
						avvisati += 1
						_manda(z, "nota", {"k": "denuncia", "x": DPTesti.CON_ARTICOLO[x], "chi": x})
			else:
				if rel[x] > -0.4 and corte.aggr[io][x] < 0.5:
					_manda(x, "nota", {"k": "aggressione"})
				rel[x] = maxf(-1.0, rel[x] - 0.3 - 0.1 * rancore)
				fid[x] = maxf(0.05, fid[x] - 0.08)
		elif violate.has(x):
			nota("%s ha violato la zona sgombra" % DPMap.POTENZE_BREVI[x])
			fid[x] = maxf(0.05, fid[x] - 0.25)
			rel[x] -= 0.2
			var r := []
			for p in patti:
				if not (p["con"] == x and p["tipo"] == "dmz"):
					r.append(p)
			patti = r
	# promesse ricevute
	for p in promesse_loro:
		var x: int = p["da"]
		var u: int = p["u"]
		if prima.up[u] != x or colpi[x] > 0:
			continue
		var fatto = ordini.get(u, null)
		var ok := false
		if fatto != null:
			var o: Array = p["o"]
			if int(o[0]) == int(fatto[0]):
				if int(o[0]) == DPAdj.M:
					ok = DPMap.loc_prov[int(o[1])] == DPMap.loc_prov[int(fatto[1])]
				elif int(o[0]) == DPAdj.S:
					ok = int(o[1]) == int(fatto[1]) and int(o[2]) == int(fatto[2])
				else:
					ok = true
		if ok:
			fid[x] = minf(1.0, fid[x] + 0.1)
			rel[x] = minf(1.0, rel[x] + 0.06)
			if int(p["o"][0]) == DPAdj.S and rng.randf() < 0.5:
				_manda(x, "nota", {"k": "grazie"})
		else:
			fid[x] = maxf(0.05, fid[x] - 0.28)
			rel[x] -= 0.12 + 0.12 * rancore
			_manda(x, "nota", {"k": "promessa_mancata", "x": DPGame.testo_ordine(prima, u, p["o"], true)})
	# ho pugnalato qualcuno?
	if pugnala >= 0:
		var q := pugnala
		rel[q] = -0.9
		bersaglio = q
		guerra_da[q] = g().anno
		_rompi(q)
		if rng.randf() < 0.75:
			_manda(q, "nota", {"k": "spiegazione"})
		pugnala = -1
	else:
		# gli amici che ammassano truppe ai miei confini insospettiscono
		var st := g().st
		for x in 7:
			if x == io or not amico(x) or colpi[x] > 0:
				continue
			var vic := 0
			var dove := -1
			for u in st.unita_di(x):
				for c in DPMap.centri:
					if st.sc[c] == io and st.up[c] != io and DPMap.tocca(st.ut[u], st.ul[u], c):
						vic += 1
						dove = c
						break
			if vic >= 2:
				fid[x] = maxf(0.05, fid[x] - 0.1)
				if rng.randf() < 0.5 and dove >= 0:
					_manda(x, "nota", {"k": "sospetto", "x": DPMap.nome[dove]})
	promesse_mie = []
	promesse_loro = []


# ------------------------------------------------------------------ salvataggio

func to_dict() -> Dictionary:
	return {"car": carattere, "l": lealta, "a": audacia, "d": doppiezza, "r": rancore,
		"rel": Array(rel), "fid": Array(fid), "bers": bersaglio, "all": alleato, "patti": patti,
		"rif": rifiuti, "guerra": Array(guerra_da), "trad": Array(tradito_da), "ap": apertura, "diario": diario,
		"pm": promesse_mie, "pl": promesse_loro, "seme": rng.state}


func from_dict(d: Dictionary) -> void:
	carattere = d.get("car", carattere)
	lealta = float(d.get("l", lealta))
	audacia = float(d.get("a", audacia))
	doppiezza = float(d.get("d", doppiezza))
	rancore = float(d.get("r", rancore))
	for i in 7:
		rel[i] = float(d["rel"][i])
		fid[i] = float(d["fid"][i])
		guerra_da[i] = int(d["guerra"][i])
		tradito_da[i] = int(d.get("trad", [0, 0, 0, 0, 0, 0, 0])[i])
	bersaglio = int(d.get("bers", -1))
	alleato = int(d.get("all", -1))
	patti = DPGame._interi(d.get("patti", []))
	rifiuti = d.get("rif", {})
	apertura = d.get("ap", "")
	diario = d.get("diario", [])
	promesse_mie = DPGame._interi(d.get("pm", []))
	promesse_loro = DPGame._interi(d.get("pl", []))

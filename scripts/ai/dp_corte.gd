class_name DPCorte
extends RefCounted
## Le cancellerie: tiene insieme la partita, i diplomatici dell'IA e la posta diplomatica.
## - smista i dispacci fra potenze (umane e artificiali) e ne conserva l'archivio;
## - osserva chi attacca chi (lo sanno tutti: è sulla mappa) e ne ricava le ostilità «pubbliche»;
## - prepara per ogni potenza gli ordini probabili, su cui i diplomatici ragionano;
## - raccoglie i voti sul pareggio.

const NOMI_LIVELLO := ["Console", "Ambasciatore", "Gran Maestro"]

var g: DPGame
var tat := DPTattica.new()
var umano: Array = [false, false, false, false, false, false, false]
var livello := 2
var dip: Array = [null, null, null, null, null, null, null]
var messaggi: Array = []
var aggr: Array = []            # aggr[x][y]: quanto x ha attaccato y di recente
var rng := RandomNumberGenerator.new()
var ultimo_cambio := 1901       # ultimo anno in cui i centri sono cambiati di mano
var voti := {}                  # voti sul pareggio in corso: potenza -> bool
var intenzioni := {}             # (solo per gli archivi) con che animo x ha attaccato y nell'ultima fase
var centri_anno := {}           # anno -> centri di ogni potenza all'inizio di quell'anno
var su_messaggio := Callable()  # chiamata a ogni dispaccio spedito (interfaccia, rete)
var _id := 0
var _pool_chiave := ""
var _pool: Array = []
var _centri_prec := PackedInt32Array()


func crea(game: DPGame, umani: Array, liv: int, seme: int) -> void:
	g = game
	livello = clampi(liv, 0, 2)
	rng.seed = seme
	tat.rng.seed = seme + 11
	aggr = []
	for x in 7:
		aggr.append(PackedFloat32Array([0, 0, 0, 0, 0, 0, 0]))
		umano[x] = bool(umani[x])
		if not umano[x]:
			var d := DPDiplomatico.new()
			d.crea(x, self, seme * 31 + x * 977 + 5)
			dip[x] = d
	_centri_prec = g.st.sc.duplicate()


func e_ia(p: int) -> bool:
	return dip[p] != null


## Un posto umano passa all'IA (giocatore assente) o viceversa.
func affida_all_ia(p: int, si: bool) -> void:
	umano[p] = not si
	if si and dip[p] == null:
		var d := DPDiplomatico.new()
		d.crea(p, self, rng.randi())
		dip[p] = d
	elif not si:
		dip[p] = null


# ------------------------------------------------------------------ posta

func messaggio(id: int) -> Variant:
	if id < 0:
		return null
	for i in range(messaggi.size() - 1, -1, -1):
		if messaggi[i]["id"] == id:
			return messaggi[i]
	return null


## Spedisce un dispaccio: {da, a, tipo, d, [sincero], [rif], [v]}. Restituisce il messaggio registrato.
func spedisci(m: Dictionary) -> Dictionary:
	# un dispaccio arrivato dal registro online ha già il suo numero (100000 + posizione), uguale per tutti
	if not (m.has("id") and int(m["id"]) >= 100000):
		m["id"] = _id
		_id += 1
	m["anno"] = g.anno
	m["fase"] = g.fase
	if not m.has("d"):
		m["d"] = {}
	if not m.has("rif"):
		m["rif"] = -1
	if not m.has("testo"):
		m["testo"] = _maiuscola(DPTesti.componi(m, g.st))
	messaggi.append(m)
	if m["tipo"] == "risposta":
		var orig = messaggio(int(m["rif"]))
		if orig != null:
			orig["esito"] = "si" if m["d"].get("si", false) else "no"
	if su_messaggio.is_valid():
		su_messaggio.call(m)
	var a: int = m["a"]
	if a >= 0 and a < 7 and dip[a] != null and g.viva(a):
		dip[a].ricevi(m)
	return m


## Registra un dispaccio già spedito altrove (partita online: arriva dal registro delle mosse).
func registra(m: Dictionary) -> void:
	m = DPGame._interi(m)
	_id = maxi(_id, int(m["id"]) + 1)
	messaggi.append(m)
	if m["tipo"] == "risposta":
		var orig = messaggio(int(m["rif"]))
		if orig != null:
			orig["esito"] = "si" if m["d"].get("si", false) else "no"


static func _maiuscola(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


## I dispacci che riguardano la potenza p (ricevuti e spediti), dal più vecchio.
func posta_di(p: int) -> Array:
	var o := []
	for m in messaggi:
		if m["da"] == p or m["a"] == p:
			o.append(m)
	return o


func da_leggere(p: int) -> int:
	var n := 0
	for m in messaggi:
		if m["a"] == p and not m.get("letto", false):
			n += 1
	return n


# ------------------------------------------------------------------ fasi

## All'inizio di una fase di movimento: le IA decidono la strategia e trattano fra loro e con gli umani.
func apri_fase() -> void:
	voti = {}
	if g.fase == DPGame.PRIMAVERA and not centri_anno.has(g.anno):
		centri_anno[g.anno] = Array(g.st.conta_centri())
	if not g.e_movimento() or g.finita:
		return
	_pool_chiave = ""
	for x in 7:
		if dip[x] != null and g.viva(x):
			dip[x].prepara_fase()
	for x in 7:
		if dip[x] != null and g.viva(x):
			dip[x].proposte()
	for x in 7:
		if dip[x] != null and g.viva(x):
			dip[x].richieste_tattiche()
	if g.fase == DPGame.PRIMAVERA and stallo() and g.anno % 2 == 1:
		# in stallo, la potenza artificiale più forte propone alle persone di chiudere in parità
		var nc := g.st.conta_centri()
		var chi := -1
		for x in 7:
			if dip[x] != null and g.viva(x) and (chi < 0 or nc[x] > nc[chi]):
				chi = x
		if chi >= 0:
			for y in 7:
				if umano[y] and g.viva(y):
					spedisci({"da": chi, "a": y, "tipo": "pareggio", "d": {}, "sincero": true, "v": 0})


## Come ogni potenza sembra disposta verso le altre, a giudicare da ciò che si vede sulla mappa.
func ost_pubblica(q: int) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(7)
	for x in 7:
		o[x] = clampf(0.42 + 0.2 * aggr[q][x] + 0.1 * aggr[x][q] + 0.2 * DPDiplomatico.BERSAGLI_NATURALI[q][x], 0.15, 1.0)
	o[q] = 0.0
	return o


## Gli ordini probabili di ogni potenza (il primo è il più verosimile).
func pool_pubblico() -> Array:
	var chiave := "%d-%d-%d" % [g.anno, g.fase, g.storia.size()]
	if chiave == _pool_chiave:
		return _pool
	var aut := g.fase == DPGame.AUTUNNO
	var pool := []
	var vals := []
	var osts := []
	var quanti: int = [4, 6, 7][livello]
	for q in 7:
		var oq := ost_pubblica(q)
		osts.append(oq)
		if g.st.n_unita(q) == 0:
			pool.append([])
			vals.append([])
			continue
		var v := tat.valori(g.st, q, oq, aut, g.anno)
		vals.append(v)
		pool.append(tat.candidati(g.st, q, v, oq, quanti))
	if livello >= 2:
		# un passo di «miglior risposta»: il candidato più forte di ognuno va in testa
		var raff := []
		for q in 7:
			if (pool[q] as Array).size() <= 1:
				raff.append(pool[q])
				continue
			var r := tat.scegli(g.st, q, pool, {"ost": osts[q], "val": vals[q], "autunno": aut}, 4)
			var l: Array = (pool[q] as Array).duplicate()
			var b = l[r["indice"]]
			l.remove_at(r["indice"])
			l.push_front(b)
			raff.append(l)
		pool = raff
	_pool = pool
	_pool_chiave = chiave
	return pool


## Gli ordini dell'IA per la fase corrente.
func ordini_ia(p: int) -> Dictionary:
	var d: DPDiplomatico = dip[p]
	if d == null or not g.deve_ordinare(p):
		return {}
	if g.e_movimento():
		return d.decidi_ordini(pool_pubblico())
	var ost := d.ostilita()
	var val := tat.valori(g.st, p, ost, false, g.anno)
	if g.e_ritirata():
		return tat.ritirate(g, p, val)
	return tat.aggiustamenti(g, p, val, ost)


## Dopo ogni risoluzione: si aggiornano le ostilità osservate e i diplomatici tirano le somme.
func dopo_risoluzione(voce: Dictionary) -> void:
	if voce.has("ordini"):
		var prima := DPState.from_dict(voce["prima"])
		for x in 7:
			for y in 7:
				aggr[x][y] *= 0.72
		for u in voce["ordini"]:
			var x := prima.up[u]
			var o: Array = voce["ordini"][u]
			if x < 0 or int(voce["esiti"][u]) == DPGame.E_NULLO:
				continue
			var dest := -1
			var peso := 1.0
			if int(o[0]) == DPAdj.M:
				dest = DPMap.loc_prov[int(o[1])]
			elif int(o[0]) == DPAdj.S and int(o[1]) != int(o[2]):
				dest = int(o[2])
				peso = 0.5
			if dest < 0:
				continue
			var v := prima.up[dest]
			if v < 0 and DPMap.centro[dest] == 1:
				v = prima.sc[dest]
				peso *= 0.7
			if v >= 0 and v != x:
				aggr[x][v] = minf(4.0, aggr[x][v] + peso)
		# per gli archivi: com'era, dalla parte di chi attacca, il patto con chi è stato attaccato
		intenzioni = {}
		for x in 7:
			if dip[x] != null:
				for y in 7:
					var d: DPDiplomatico = dip[x]
					var come := "nessun patto dalla sua parte"
					if d.pugnala == y:
						come = "pugnalata calcolata"
					elif d.amico(y):
						come = "patto violato" if d.patto_sincero(y) else "patto firmato in malafede"
					intenzioni["%d-%d" % [x, y]] = come
		for x in 7:
			if dip[x] != null:
				dip[x].dopo_risoluzione(voce)
	if g.st.sc != _centri_prec:
		ultimo_cambio = g.anno
		_centri_prec = g.st.sc.duplicate()


# ------------------------------------------------------------------ pareggio

## La partita è in stallo: dal 1909 in poi, nessuna potenza ha guadagnato più di un centro in quattro anni.
func stallo() -> bool:
	if g.anno < 1909 or not centri_anno.has(g.anno - 4):
		return false
	var ora := g.st.conta_centri()
	var allora: Array = centri_anno[g.anno - 4]
	for p in 7:
		if ora[p] - int(allora[p]) >= 2:
			return false
	return true


func voto_pareggio_ia(p: int) -> bool:
	var nc := g.st.conta_centri()
	var d: DPDiplomatico = dip[p]
	if stallo():
		return true
	var m: int = d.minaccia() if d != null else -1
	if m >= 0 and m != p and nc[p] <= nc[m] - 5:
		return true
	if g.anno >= 1914 and nc[p] < 7:
		return true
	return false


## Una potenza propone il pareggio: votano tutte le potenze in vita. Le IA rispondono subito.
func proponi_pareggio(p: int) -> void:
	voti = {p: true}
	for x in 7:
		if x != p and g.viva(x) and dip[x] != null:
			voti[x] = voto_pareggio_ia(x)


func vota_pareggio(p: int, si: bool) -> void:
	voti[p] = si


## 1 approvato, -1 respinto, 0 in attesa dei voti.
func esito_pareggio() -> int:
	if voti.is_empty():
		return 0
	var attesa := false
	for x in 7:
		if not g.viva(x) or g.st.n_centri(x) == 0:
			continue
		if not voti.has(x):
			attesa = true
		elif not voti[x]:
			return -1
	return 0 if attesa else 1


# ------------------------------------------------------------------ salvataggio

func to_dict(tutta_la_posta := true) -> Dictionary:
	var d := []
	for x in 7:
		d.append(dip[x].to_dict() if dip[x] != null else null)
	var a := []
	for x in 7:
		a.append(Array(aggr[x]))
	var posta := messaggi
	if not tutta_la_posta:
		# per i salvataggi in rete: i dispacci che riguardano gli umani e gli ultimi fra le IA
		posta = []
		var n := messaggi.size()
		for i in n:
			var m: Dictionary = messaggi[i]
			if umano[m["da"]] or (m["a"] >= 0 and umano[m["a"]]) or i >= n - 150:
				posta.append(m)
	return {"umano": umano, "livello": livello, "dip": d, "msg": posta, "aggr": a, "id": _id,
		"cambio": ultimo_cambio, "seme": rng.state, "centri": centri_anno}


func from_dict(game: DPGame, d: Dictionary) -> void:
	g = game
	livello = int(d.get("livello", 2))
	_id = int(d.get("id", 0))
	ultimo_cambio = int(d.get("cambio", 1901))
	centri_anno = DPGame._interi(d.get("centri", {}))
	messaggi = DPGame._interi(d.get("msg", []))
	aggr = []
	for x in 7:
		var r := PackedFloat32Array()
		for v in d["aggr"][x]:
			r.append(float(v))
		aggr.append(r)
		umano[x] = bool(d["umano"][x])
		dip[x] = null
		if d["dip"][x] != null:
			var dd := DPDiplomatico.new()
			dd.crea(x, self, int(d.get("seme", 1)) + x)
			dd.from_dict(d["dip"][x])
			dip[x] = dd
	_centri_prec = g.st.sc.duplicate()

class_name DPGame
extends RefCounted
## Una partita: posizione, anno e fase, ordini raccolti, risoluzione e storico.
##
## Fasi di un anno: PRIMAVERA (movimenti) - ritirate - AUTUNNO (movimenti) - ritirate -
## INVERNO (aggiustamenti: costruzioni e scioglimenti). Le fasi senza nulla da fare si saltano.
##
## Ordini per potenza:
##   movimenti     {provincia: [tipo, a, b]}   (vedi DPAdj)
##   ritirate      {provincia: località}        (-1 = l'unità si scioglie)
##   aggiustamenti {"c": [[tipo, località], …], "s": [provincia, …]}

const PRIMAVERA := 0
const RIT_PRIMAVERA := 1
const AUTUNNO := 2
const RIT_AUTUNNO := 3
const INVERNO := 4
const NOMI_FASE := ["Primavera", "Ritirate di primavera", "Autunno", "Ritirate d'autunno", "Inverno"]
const CENTRI_VITTORIA := 18

# esiti degli ordini nello storico
const E_OK := 0
const E_RESPINTA := 1
const E_NULLO := 2
const E_TAGLIATO := 3
const E_SENZA_ROTTA := 4

var st: DPState
var anno := 1901
var fase := PRIMAVERA
var ritirate: Array = []
var ordini: Array = [{}, {}, {}, {}, {}, {}, {}]
var storia: Array = []
var finita := false
var vincitore := -1
var pari: Array = []          # potenze che dividono il pareggio
var ultimo_anno := 0          # 0 = senza limite; altrimenti la partita finisce dopo l'inverno di quell'anno
var adj := DPAdj.new()


func _init() -> void:
	DPMap.ensure()
	st = DPState.iniziale()


func nome_fase() -> String:
	return "%s %d" % [NOMI_FASE[fase], anno]


func e_movimento() -> bool:
	return fase == PRIMAVERA or fase == AUTUNNO


func e_ritirata() -> bool:
	return fase == RIT_PRIMAVERA or fase == RIT_AUTUNNO


func viva(p: int) -> bool:
	return st.n_centri(p) > 0 or st.n_unita(p) > 0


## Ritirate in sospeso di una potenza.
func ritirate_di(p: int) -> Array:
	var o := []
	for r in ritirate:
		if r["p"] == p:
			o.append(r)
	return o


## Costruzioni (positivo) o scioglimenti (negativo) che spettano alla potenza in inverno.
func saldo(p: int) -> int:
	var d := st.n_centri(p) - st.n_unita(p)
	if d > 0:
		d = mini(d, case_libere(p).size())
	return d


## I centri di casa in cui la potenza può costruire (suoi e vuoti).
func case_libere(p: int) -> PackedInt32Array:
	var o := PackedInt32Array()
	for c in DPMap.case_di[p]:
		if st.sc[c] == p and st.up[c] < 0:
			o.append(c)
	return o


## La potenza ha qualcosa da ordinare in questa fase?
func deve_ordinare(p: int) -> bool:
	if finita:
		return false
	if e_movimento():
		return st.n_unita(p) > 0
	if e_ritirata():
		return not ritirate_di(p).is_empty()
	return saldo(p) != 0


func imposta_ordini(p: int, o: Dictionary) -> void:
	ordini[p] = o.duplicate(true)


## Risolve la fase corrente e passa alla successiva che richiede ordini. Restituisce la voce di storico.
func risolvi() -> Dictionary:
	var voce := {"anno": anno, "fase": fase, "prima": st.to_dict()}
	if e_movimento():
		_risolvi_movimenti(voce)
	elif e_ritirata():
		_risolvi_ritirate(voce)
	else:
		_risolvi_inverno(voce)
	storia.append(voce)
	ordini = [{}, {}, {}, {}, {}, {}, {}]
	_avanza()
	voce["dopo"] = st.to_dict()
	return voce


func _risolvi_movimenti(voce: Dictionary) -> void:
	adj.pulisci()
	var tutti := {}
	for p in 7:
		for k in ordini[p]:
			var pr := int(k)
			if st.up[pr] == p:
				adj.carica({pr: ordini[p][k]})
	adj.risolvi(st)
	var esiti := {}
	for i in DPMap.N_PROV:
		if st.up[i] < 0:
			continue
		var o: Array = [adj.ot[i], adj.oa[i], adj.ob[i]]
		var e := E_OK
		if adj.nullo[i] == 1:
			# si conserva l'ordine dato, per mostrarlo come nullo
			var dato = null
			for k in ordini[st.up[i]]:
				if int(k) == i:
					dato = ordini[st.up[i]][k]
			if dato != null:
				o = [int(dato[0]), int(dato[1]) if dato.size() > 1 else -1, int(dato[2]) if dato.size() > 2 else -1]
			e = E_NULLO
		elif adj.ot[i] == DPAdj.M:
			if adj.senza_rotta[i] == 1:
				e = E_SENZA_ROTTA
			elif adj.esito[i] == 0:
				e = E_RESPINTA
			o[2] = adj.via_mare[i]
		elif adj.ot[i] == DPAdj.S and adj.esito[i] == 0:
			e = E_TAGLIATO
		elif adj.ot[i] == DPAdj.C and adj.esito[i] == 0:
			e = E_RESPINTA
		tutti[i] = o
		esiti[i] = e
	var r := adj.applica(st)
	var slog := []
	for x in r["ritirate"]:
		slog.append([x["prov"], adj.sloggiata[x["prov"]], Array(x["opzioni"])])
	voce["ordini"] = tutti
	voce["esiti"] = esiti
	voce["sloggiate"] = slog
	st = r["stato"]
	ritirate = r["ritirate"]


func _risolvi_ritirate(voce: Dictionary) -> void:
	var scelte := {}
	for p in 7:
		for k in ordini[p]:
			scelte[int(k)] = int(ordini[p][k])
	var out := DPAdj.risolvi_ritirate(st, ritirate, scelte)
	var rit := []
	for r in ritirate:
		rit.append([r["prov"], r["p"], r["t"], r["loc"], int(scelte.get(r["prov"], -1)), out[r["prov"]]])
	voce["ritirate"] = rit
	ritirate = []


func _risolvi_inverno(voce: Dictionary) -> void:
	var costruite := []
	var sciolte := []
	for p in 7:
		var d := saldo(p)
		var o: Dictionary = ordini[p]
		if d > 0:
			var fatte := 0
			for c in o.get("c", []):
				if fatte >= d:
					break
				var t := int(c[0])
				var l := int(c[1])
				if l < 0 or l >= DPMap.N_LOC:
					continue
				var pr := DPMap.loc_prov[l]
				if not case_libere(p).has(pr):
					continue
				if t == 0:
					l = pr
				else:
					if DPMap.tipo[pr] != DPMap.COSTA:
						continue
					if not (DPMap.coste_di[pr] as PackedInt32Array).is_empty() and l == pr:
						continue          # serve la costa
				st.metti(p, t, l)
				costruite.append([p, t, l])
				fatte += 1
		elif d < 0:
			var da_sciogliere := -d
			var scelti := []
			for pr in o.get("s", []):
				if scelti.size() < da_sciogliere and st.up[int(pr)] == p and not scelti.has(int(pr)):
					scelti.append(int(pr))
			if scelti.size() < da_sciogliere:
				for pr in _scioglimento_automatico(p):
					if scelti.size() < da_sciogliere and not scelti.has(pr):
						scelti.append(pr)
			for pr in scelti:
				sciolte.append([p, st.ut[pr], st.ul[pr]])
				st.togli(pr)
	voce["costruite"] = costruite
	voce["sciolte"] = sciolte


## Senza ordini si sciolgono le unità più lontane dai centri di casa (prima le flotte).
func _scioglimento_automatico(p: int) -> Array:
	var u := []
	for pr in st.unita_di(p):
		var dmin := 99
		for c in DPMap.case_di[p]:
			dmin = mini(dmin, DPMap.dist_q[pr][c])
		u.append([-dmin, -st.ut[pr], DPMap.sigla[pr], pr])
	u.sort()
	var o := []
	for x in u:
		o.append(x[3])
	return o


func _avanza() -> void:
	while true:
		match fase:
			PRIMAVERA:
				fase = RIT_PRIMAVERA
			RIT_PRIMAVERA:
				fase = AUTUNNO
			AUTUNNO:
				fase = RIT_AUTUNNO
			RIT_AUTUNNO:
				st.aggiorna_centri()
				fase = INVERNO
				_controlla_vittoria()
				if finita:
					return
			INVERNO:
				if ultimo_anno > 0 and anno >= ultimo_anno:
					_fine_per_tempo()
					return
				fase = PRIMAVERA
				anno += 1
		if e_ritirata():
			# le unità senza vie di fuga si sciolgono subito
			var restano := []
			for r in ritirate:
				if not (r["opzioni"] as PackedInt32Array).is_empty():
					restano.append(r)
				else:
					storia[-1]["distrutte"] = storia[-1].get("distrutte", []) + [[r["prov"], r["p"], r["t"]]]
			ritirate = restano
			if not ritirate.is_empty():
				return
		elif fase == INVERNO:
			for p in 7:
				if saldo(p) != 0:
					return
		else:
			return


func _controlla_vittoria() -> void:
	var c := st.conta_centri()
	for p in 7:
		if c[p] >= CENTRI_VITTORIA:
			finita = true
			vincitore = p


func _fine_per_tempo() -> void:
	finita = true
	var c := st.conta_centri()
	var mx := 0
	for p in 7:
		mx = maxi(mx, c[p])
	pari = []
	for p in 7:
		if c[p] == mx:
			pari.append(p)
	if pari.size() == 1:
		vincitore = pari[0]


## Pareggio concordato fra le potenze ancora in vita.
func pareggio() -> void:
	finita = true
	pari = []
	for p in 7:
		if st.n_centri(p) > 0:
			pari.append(p)


# ---------- testo degli ordini ----------

static func sigla_unita(t: int) -> String:
	return "A" if t == 0 else "F"


static func nome_unita(t: int) -> String:
	return "Armata" if t == 0 else "Flotta"


static func sig(l: int) -> String:
	var s: String = DPMap.sigla[l]
	return s.substr(0, 1) + s.substr(1).to_lower()


## «A Par - Bor», «F Nth S A Lon - Bel», «F Eng C A Lon - Bel», «A Rom ferma».
static func testo_ordine(stato: DPState, prov: int, o: Array, lungo := false) -> String:
	var t := stato.ut[prov]
	var qui := (DPMap.nome_loc(stato.ul[prov]) if lungo else sig(stato.ul[prov]))
	var s := "%s %s" % [sigla_unita(t), qui]
	var tipo := int(o[0])
	var a := int(o[1]) if o.size() > 1 else -1
	var b := int(o[2]) if o.size() > 2 else -1
	match tipo:
		DPAdj.H:
			return s + " ferma"
		DPAdj.M:
			if a < 0 or a >= DPMap.N_LOC:
				return s + " - ?"
			return "%s - %s%s" % [s, DPMap.nome_loc(a) if lungo else sig(a), " (via convoglio)" if b == 1 else ""]
		DPAdj.S:
			if a < 0 or a >= DPMap.N_PROV or stato.up[a] < 0:
				return s + " S ?"
			var su := "%s %s" % [sigla_unita(stato.ut[a]), DPMap.nome[a] if lungo else sig(a)]
			if b == a or b < 0:
				return "%s S %s" % [s, su]
			return "%s S %s - %s" % [s, su, DPMap.nome[b] if lungo else sig(b)]
		DPAdj.C:
			if a < 0 or b < 0:
				return s + " C ?"
			return "%s C A %s - %s" % [s, DPMap.nome[a] if lungo else sig(a), DPMap.nome[b] if lungo else sig(b)]
	return s


static func testo_esito(e: int, tipo: int) -> String:
	match e:
		E_RESPINTA:
			return "convoglio interrotto" if tipo == DPAdj.C else "respinta"
		E_NULLO:
			return "ordine nullo"
		E_TAGLIATO:
			return "sostegno tagliato"
		E_SENZA_ROTTA:
			return "convoglio mancato"
	return ""


# ---------- salvataggio ----------

func to_dict() -> Dictionary:
	var rit := []
	for r in ritirate:
		rit.append({"prov": r["prov"], "p": r["p"], "t": r["t"], "loc": r["loc"], "opzioni": Array(r["opzioni"])})
	return {"st": st.to_dict(), "anno": anno, "fase": fase, "rit": rit, "storia": storia,
		"finita": finita, "vincitore": vincitore, "pari": pari, "ultimo_anno": ultimo_anno}


static func from_dict(d: Dictionary) -> DPGame:
	var g := DPGame.new()
	g.st = DPState.from_dict(d["st"])
	g.anno = int(d["anno"])
	g.fase = int(d["fase"])
	g.ritirate = []
	for r in d.get("rit", []):
		var o := PackedInt32Array()
		for v in r["opzioni"]:
			o.append(int(v))
		g.ritirate.append({"prov": int(r["prov"]), "p": int(r["p"]), "t": int(r["t"]), "loc": int(r["loc"]), "opzioni": o})
	g.storia = _interi(d.get("storia", []))
	g.finita = bool(d.get("finita", false))
	g.vincitore = int(d.get("vincitore", -1))
	g.pari = _interi(d.get("pari", []))
	g.ultimo_anno = int(d.get("ultimo_anno", 0))
	return g


## Il JSON restituisce numeri con la virgola e chiavi di testo: si riportano a interi.
static func _interi(v):
	if v is float:
		return int(v) if v == floorf(v) else v
	if v is Array:
		var o := []
		for x in v:
			o.append(_interi(x))
		return o
	if v is Dictionary:
		var o := {}
		for k in v:
			var kk = k
			if k is String and (k as String).is_valid_int():
				kk = int(k)
			o[kk] = _interi(v[k])
		return o
	return v

class_name DPTelefoni
extends Node
## Il ponte fra chi ospita la partita e i telefoni che giocano dalla pagina HTML (web/telefono).
## I telefoni non hanno il gioco: chi ospita pubblica per loro, come testo JSON sotto «labels/tel»,
## lo stato della partita e - per ogni posto - posta, accordi e tutte le scelte possibili (ordini,
## ritirate, costruzioni, proposte). I telefoni rispondono scrivendo le loro azioni numerate sotto
## «plans/<numero>/<posto>»; chi ospita le legge in ordine e le mette nel registro delle mosse, come
## se le avesse fatte un giocatore collegato con il gioco intero.
## (Sono i soli percorsi che le regole comuni del database lasciano scrivere a chi ospita e a un posto.)

const PASSO := 0.8
const MAX_POSTA := 70

var ses: DPSession
var net: Net
var codice := ""
var posti_tel := {}          # posto -> true: chi è entrato dalla pagina per telefono
var visti := {}              # posto -> numero della prossima azione da leggere
var _ultimo := {}            # percorso -> ultimo testo pubblicato
var _giro := 0
var _nomi_scritti := false


func avvia(sessione: DPSession) -> void:
	ses = sessione
	net = ses.net
	codice = ses.codice
	_ciclo()


func _base() -> String:
	return "%s/%s" % [Net.ROOT, codice]


func _ciclo() -> void:
	# chi ospita rientra: riprende il conto delle azioni già lette
	var r := await net.db_get(_base() + "/labels/tel/pub")
	if r["code"] == 200 and r["data"] is String:
		var d = JSON.parse_string(r["data"])
		if d is Dictionary:
			for k in (d.get("visti", {}) as Dictionary):
				visti[int(k)] = int(d["visti"][k])
	while is_instance_valid(ses) and ses.vivo and is_inside_tree():
		if _giro % 6 == 0:
			await _leggi_posti()
		_giro += 1
		if posti_tel.is_empty():
			await get_tree().create_timer(PASSO * 2.0).timeout
			continue
		await _leggi_azioni()
		if not is_instance_valid(ses) or not ses.vivo:
			return
		await _pubblica()
		await get_tree().create_timer(PASSO).timeout


func _leggi_posti() -> void:
	var r := await net.db_get(_base() + "/seats")
	if r["code"] != 200:
		return
	var seats := Net._as_dict(r["data"])
	for k in seats:
		if seats[k] is Dictionary and seats[k].get("tel", false):
			posti_tel[int(k)] = true
			if not visti.has(int(k)):
				visti[int(k)] = 0


## Le azioni dei telefoni, nell'ordine in cui le hanno numerate.
func _leggi_azioni() -> void:
	for s in posti_tel:
		for giro in 6:
			var r := await net.db_get("%s/plans/%d/%d" % [_base(), visti[s], s])
			if r["code"] != 200 or not (r["data"] is Dictionary):
				break
			var a: Dictionary = r["data"]
			visti[s] += 1
			var k := str(a.get("k", ""))
			if k in ["ord", "rit", "msg", "par"] and ses.e_umano(s):
				var v := str(a.get("v", ""))
				if k == "msg":
					# il mittente è il posto, qualunque cosa dica il messaggio
					var m = JSON.parse_string(v)
					if not (m is Dictionary):
						continue
					m["da"] = s
					m.erase("id")
					m.erase("testo")
					v = JSON.stringify(m)
				ses._accoda({"s": s, "k": k, "v": v})


func _scrivi(percorso: String, dati) -> void:
	var t := JSON.stringify(dati)
	if _ultimo.get(percorso, "") == t:
		return
	var r := await net.db_put("%s/labels/tel/%s" % [_base(), percorso], t)
	if r["code"] == 200:
		_ultimo[percorso] = t


func _pubblica() -> void:
	var g := ses.g
	if g == null:
		return
	if not _nomi_scritti:
		_nomi_scritti = true
		var nomi := []
		for i in DPMap.N_PROV:
			nomi.append(DPMap.nome[i])
		await _scrivi("nomi", nomi)
	var vp := {}
	for s in posti_tel:
		var priv := _privato(int(s))
		var t := JSON.stringify(priv)
		vp[str(s)] = t.hash()
		await _scrivi("p%d" % s, priv)
	await _scrivi("pub", _pubblico(vp))


func _nome_unita(st: DPState, u: int) -> String:
	return "%s %s" % [DPGame.nome_unita(st.ut[u]), DPMap.nome_loc(st.ul[u])]


func _con_potenza(st: DPState, u: int) -> String:
	return "%s (%s)" % [_nome_unita(st, u), DPMap.POTENZE_BREVI[st.up[u]]]


func _pubblico(vp: Dictionary) -> Dictionary:
	var g := ses.g
	var st := g.st
	var pot := []
	for p in 7:
		var un := []
		for u in st.unita_di(p):
			un.append("%s %s" % [DPGame.sigla_unita(st.ut[u]), DPMap.nome_loc(st.ul[u])])
		pot.append({"n": DPMap.POTENZE[p], "b": DPMap.POTENZE_BREVI[p], "chi": ses.nome(p) if ses.e_umano(p) else "IA",
			"um": ses.e_umano(p), "c": st.n_centri(p), "viva": g.viva(p), "u": ", ".join(un)})
	var attesa := []
	for p in 7:
		if ses.e_umano(p) and g.deve_ordinare(p) and not ses.consegnati.has(p):
			attesa.append(p)
	var esito := ""
	if g.finita:
		if g.vincitore >= 0 and g.pari.size() <= 1:
			esito = "Vince %s." % DPTesti.CON_ARTICOLO[g.vincitore]
		else:
			var nomi := []
			for p in g.pari:
				nomi.append(DPMap.POTENZE_BREVI[int(p)])
			esito = "Pareggio fra: %s." % ", ".join(nomi)
	var par = null
	if not ses.corte.voti.is_empty() and not g.finita:
		par = {"voti": ses.corte.voti.keys()}
	var vv := {}
	for s in visti:
		vv[str(s)] = visti[s]
	return {"chiave": "%d-%d-%d" % [g.anno, g.fase, g.storia.size()], "anno": g.anno, "fase": g.fase,
		"titolo": "%s %d" % [DPGame.NOMI_FASE[g.fase], g.anno],
		"tipo": "mov" if g.e_movimento() else ("rit" if g.e_ritirata() else "agg"),
		"finita": g.finita, "esito": esito, "calcolo": ses.in_calcolo, "pot": pot, "attesa": attesa,
		"ultima": _ultima_fase(), "par": par, "visti": vv, "vp": vp, "vittoria": DPGame.CENTRI_VITTORIA}


## I risultati dell'ultima fase, già scritti per esteso.
func _ultima_fase():
	var g := ses.g
	if g.storia.is_empty():
		return null
	var voce: Dictionary = g.storia[g.storia.size() - 1]
	var prima := DPState.from_dict(voce["prima"])
	var righe := []            # [potenza o -1, testo, esito]
	if voce.has("ordini"):
		for p in 7:
			for u in voce["ordini"]:
				if prima.up[u] == p:
					righe.append([p, DPGame.testo_ordine(prima, u, voce["ordini"][u], true), DPGame.testo_esito(int(voce["esiti"][u]), int(voce["ordini"][u][0]))])
		for x in voce.get("sloggiate", []):
			righe.append([-1, "%s %s è scacciata." % [DPGame.nome_unita(prima.ut[x[0]]), DPMap.nome[x[0]]], ""])
		for x in voce.get("distrutte", []):
			righe.append([-1, "%s %s (%s) non ha vie di ritirata: è distrutta." % [DPGame.nome_unita(x[2]), DPMap.nome[x[0]], DPMap.POTENZE_BREVI[x[1]]], ""])
	elif voce.has("ritirate"):
		for r in voce["ritirate"]:
			var s := "%s %s " % [DPGame.sigla_unita(r[2]), DPMap.nome_loc(r[3])]
			if r[5] >= 0:
				s += "si ritira in %s." % DPMap.nome_loc(r[5])
			elif r[4] >= 0:
				s += "si scioglie (ritirata contesa)."
			else:
				s += "si scioglie."
			righe.append([int(r[1]), s, ""])
	else:
		for x in voce.get("costruite", []):
			righe.append([int(x[0]), "Costruisce: %s %s." % [DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], ""])
		for x in voce.get("sciolte", []):
			righe.append([int(x[0]), "Scioglie: %s %s." % [DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], ""])
		if righe.is_empty():
			righe.append([-1, "Nessun cambiamento.", ""])
	return {"t": "%s %d" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]], "r": righe}


## Province in cui un'armata può sbarcare per convoglio.
func _sbarchi(st: DPState, u: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if st.up[u] < 0 or st.ut[u] != 0 or DPMap.tipo[u] != DPMap.COSTA:
		return out
	var visto := {}
	var coda := []
	for f in DPMap.adj_fp[u]:
		if DPMap.tipo[f] == DPMap.MARE and st.up[f] >= 0 and st.ut[f] == 1:
			visto[f] = true
			coda.append(f)
	var h := 0
	while h < coda.size():
		var f: int = coda[h]
		h += 1
		for x in DPMap.adj_fp[f]:
			if DPMap.tipo[x] == DPMap.MARE:
				if st.up[x] >= 0 and st.ut[x] == 1 and not visto.has(x):
					visto[x] = true
					coda.append(x)
			elif DPMap.tipo[x] == DPMap.COSTA and x != u and not out.has(x):
				out.append(x)
	return out


## Dove l'unità chi può sostenere l'unità u: la sua provincia (ferma) o una sua destinazione.
func _bersagli(st: DPState, chi: int, u: int) -> Array:
	var o := []
	if u < 0 or st.up[u] < 0 or u == chi:
		return o
	if DPMap.tocca(st.ut[chi], st.ul[chi], u):
		o.append(u)
	var dest := {}
	for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
		dest[DPMap.loc_prov[l]] = true
	for x in _sbarchi(st, u):
		dest[x] = true
	for x in dest:
		if x != chi and DPMap.tocca(st.ut[chi], st.ul[chi], x):
			o.append(x)
	return o


func _mosse(st: DPState, u: int) -> Array:
	var m := []
	if st.ut[u] == 1:
		for l in DPMap.destinazioni(1, st.ul[u]):
			m.append(["muove in %s" % DPMap.nome_loc(l), [DPAdj.M, l, 0]])
	else:
		for x in DPMap.adj_a[u]:
			m.append(["muove in %s" % DPMap.nome[x], [DPAdj.M, x, 0]])
		for x in _sbarchi(st, u):
			m.append(["muove in %s, via convoglio" % DPMap.nome[x], [DPAdj.M, x, 1]])
	return m


func _accordi(io: int, chi: int) -> Array:
	var g := ses.g
	var visti_acc := {}
	for m in ses.corte.posta_di(io):
		if not ((m["da"] == chi and m["a"] == io) or (m["da"] == io and m["a"] == chi)):
			continue
		if m["tipo"] == "nota" and m["d"].get("k", "") == "disdetta":
			visti_acc.clear()
			continue
		if m.get("esito", "") != "si":
			continue
		match m["tipo"]:
			"alleanza":
				if g.viva(int(m["d"]["contro"])):
					visti_acc["alleanza contro %s (%d)" % [DPTesti.CON_ARTICOLO[int(m["d"]["contro"])], m["anno"]]] = true
			"pace":
				visti_acc["non aggressione (%d)" % m["anno"]] = true
			"dmz":
				if g.anno - int(m["anno"]) < 2:
					visti_acc["zona sgombra: %s" % DPTesti.province(m["d"]["prov"])] = true
	return visti_acc.keys()


## Tutto ciò che serve a un telefono per trattare e ordinare: riguarda una sola potenza.
func _privato(io: int) -> Dictionary:
	var g := ses.g
	var st := g.st
	var d := {"io": io, "nome": DPMap.POTENZE[io], "viva": g.viva(io), "nc": st.n_centri(io), "nu": st.n_unita(io)}
	var miei := []
	for c in DPMap.centri:
		if st.sc[c] == io:
			miei.append(DPMap.nome[c])
	miei.sort()
	d["centri"] = ", ".join(miei)
	var deve := not g.finita and g.deve_ordinare(io)
	d["deve"] = deve
	d["consegnato"] = ses.consegnati.has(io)
	d["modifica"] = ses.consegnati.has(io) and not ses.in_calcolo and not ses.tutti_pronti()
	# ---- ordini
	if deve and g.e_movimento():
		var unita := []
		for u in st.unita_di(io):
			var sost := []
			for x in DPMap.N_PROV:
				if st.up[x] >= 0 and x != u:
					var dove := []
					for b in _bersagli(st, u, x):
						dove.append(["che resta ferma" if b == x else "verso %s" % DPMap.nome[b], [DPAdj.S, x, b]])
					if not dove.is_empty():
						sost.append([_con_potenza(st, x), dove])
			var conv := []
			if st.ut[u] == 1 and DPMap.tipo[u] == DPMap.MARE:
				for x in DPMap.N_PROV:
					if st.up[x] >= 0 and st.ut[x] == 0:
						var dove := []
						for b in _sbarchi(st, x):
							dove.append(["verso %s" % DPMap.nome[b], [DPAdj.C, x, b]])
						if not dove.is_empty():
							conv.append([_con_potenza(st, x), dove])
			unita.append({"u": u, "n": _nome_unita(st, u), "m": _mosse(st, u), "s": sost, "c": conv})
		d["unita"] = unita
	elif deve and g.e_ritirata():
		var rit := []
		for r in g.ritirate_di(io):
			var o := []
			for l in r["opzioni"]:
				o.append([int(l), DPTesti.maiuscola(DPMap.nome_loc(l))])
			rit.append({"p": int(r["prov"]), "n": "%s %s" % [DPGame.nome_unita(r["t"]), DPMap.nome_loc(r["loc"])], "o": o})
		d["rit"] = rit
	elif deve:
		var saldo := g.saldo(io)
		d["saldo"] = saldo
		if saldo > 0:
			var case := []
			for pr in g.case_libere(io):
				var o := [["Armata", [0, pr]]]
				if DPMap.tipo[pr] == DPMap.COSTA:
					var cs: PackedInt32Array = DPMap.coste_di[pr]
					if cs.is_empty():
						o.append(["Flotta", [1, pr]])
					else:
						for l in cs:
							o.append(["Flotta (%s)" % DPMap.nome_costa(DPMap.costa_nome[l]), [1, l]])
				case.append({"p": pr, "n": DPMap.nome[pr], "o": o})
			d["case"] = case
		else:
			var scio := []
			for u in st.unita_di(io):
				scio.append([u, _nome_unita(st, u)])
			d["scio"] = scio
	# ---- posta
	var posta := []
	var tutta := ses.corte.posta_di(io)
	for m in tutta.slice(maxi(0, tutta.size() - MAX_POSTA)):
		var mia: bool = m["da"] == io
		var e := {"id": int(m["id"]), "con": int(m["a"]) if mia else int(m["da"]), "mia": mia,
			"h": "%s - %s %d" % ["DA VOI" if mia else str(DPTesti.DA_CANC[m["da"]]).to_upper(), DPGame.NOMI_FASE[m["fase"]], m["anno"]],
			"t": str(m.get("testo", "")), "tp": str(m["tipo"])}
		if DPTesti.e_proposta(m["tipo"]):
			var es: String = m.get("esito", "")
			var attuale: bool = m["anno"] == g.anno and m["fase"] == g.fase
			if es == "si":
				e["s"] = "ok"
			elif es == "no":
				e["s"] = "no"
			elif not mia and (attuale or m["tipo"] in ["alleanza", "pace", "dmz"]) and not g.finita:
				e["s"] = "rispondi"
			elif mia:
				e["s"] = "attesa"
			else:
				e["s"] = "scaduto"
		posta.append(e)
	d["posta"] = posta
	# ---- le altre potenze: accordi e proposte possibili
	var altre := []
	var mov := g.e_movimento() and not g.finita
	for q in 7:
		if q == io:
			altre.append(null)
			continue
		var x := {"acc": _accordi(io, q), "chi": ("Guidata da %s." % ses.nome(q)) if ses.e_umano(q) else ("Guidata dall'IA (%s)." % DPCorte.NOMI_LIVELLO[ses.corte.livello]),
			"canc": "%s (%s)" % [DPTesti.maiuscola(DPTesti.CANCELLERIE[q]), DPMap.POTENZE_BREVI[q]]}
		var terze := []
		for p in 7:
			if p != io and p != q and g.viva(p):
				terze.append([p, DPMap.POTENZE[p]])
		x["terze"] = terze
		if mov and g.viva(q) and g.viva(io):
			var sc := []
			var so := []
			for u in st.unita_di(q):
				for a in st.unita_di(io):
					for b in _bersagli(st, u, a):
						sc.append(["%s sostiene %s %s" % [_nome_unita(st, u), _nome_unita(st, a), "che resta ferma" if b == a else "verso %s" % DPMap.nome[b]], {"u": u, "a": a, "b": b}])
			for u in st.unita_di(io):
				for a in st.unita_di(q):
					for b in _bersagli(st, u, a):
						so.append(["%s sostiene %s %s" % [_nome_unita(st, u), _nome_unita(st, a), "che resta ferma" if b == a else "verso %s" % DPMap.nome[b]], {"u": u, "a": a, "b": b}])
			var mo := []
			for u in st.unita_di(q):
				mo.append(["%s resta ferma" % _nome_unita(st, u), {"u": u, "o": [DPAdj.H, -1, -1]}])
				for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
					mo.append(["%s muove in %s" % [_nome_unita(st, u), DPMap.nome_loc(l)], {"u": u, "o": [DPAdj.M, l, 0]}])
			x["sc"] = sc.slice(0, 60)
			x["so"] = so.slice(0, 60)
			x["mo"] = mo.slice(0, 80)
		altre.append(x)
	d["altre"] = altre
	d["ho_votato"] = ses.corte.voti.has(io)
	return d

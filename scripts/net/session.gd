class_name DPSession
extends Node
## Una partita in corso: tiene il gioco, le cancellerie (IA e posta) e fa avanzare le fasi.
##
## In locale: quando tutte le persone hanno consegnato gli ordini, calcola quelli delle IA e risolve.
## Online: ogni dispositivo applica lo stesso registro di mosse numerate (acts/0, acts/1, …):
##   ord  una persona consegna i suoi ordini          rit  li ritira per cambiarli
##   msg  un dispaccio                                 ris  chi ha creato la stanza pubblica tutti gli
##   par  proposta o voto di pareggio                       ordini della fase: tutti la risolvono
##   aff  un posto passa all'IA                        ia   fotografia delle IA (per chi ospita, se rientra)
## Le IA girano solo sul dispositivo di chi ha creato la stanza.

signal aggiornata
signal risolta(voce: Dictionary)
signal posta(m: Dictionary)
signal avviso(testo: String)
signal pareggio_proposto(da: int)

const FILE_LOCALE := "user://diplomacy_partita.json"

var g: DPGame
var corte: DPCorte
var cfg := {}                 # {posti: ["u"|"ia" x7], nomi: [x7], livello, ultimo_anno, classiche, seme}
var locali: Array = []        # potenze giocate su questo dispositivo
var consegnati := {}          # potenza -> ordini consegnati (persone)
var in_calcolo := false
var codice_salvataggio := ""

# online
var online := false
var net: Net
var codice := ""
var ruolo := ""
var posto := -1
var n := 0
var uscita: Array = []
var recupero := false
var vivo := true


func _exit_tree() -> void:
	vivo = false


func e_umano(p: int) -> bool:
	return cfg["posti"][p] == "u"


func nome(p: int) -> String:
	var s: String = cfg.get("nomi", ["", "", "", "", "", "", ""])[p]
	return s if s != "" else ("IA" if not e_umano(p) else "Giocatore")


# ------------------------------------------------------------------ avvio

func nuova(config: Dictionary) -> void:
	cfg = config
	g = DPGame.new()
	g.ultimo_anno = int(cfg.get("ultimo_anno", 0))
	corte = DPCorte.new()
	var umani := []
	for p in 7:
		umani.append(e_umano(p))
	corte.crea(g, umani, int(cfg.get("livello", 2)), int(cfg.get("seme", 1)))
	corte.su_messaggio = _su_messaggio
	locali = []
	for p in 7:
		if e_umano(p):
			locali.append(p)


func avvia() -> void:
	corte.apri_fase()
	aggiornata.emit()
	_controlla.call_deferred()


func stato() -> Dictionary:
	return {"cfg": cfg, "g": g.to_dict(), "corte": corte.to_dict(false), "v": 1}


func da_stato(d: Dictionary) -> void:
	cfg = d["cfg"]
	g = DPGame.from_dict(d["g"])
	corte = DPCorte.new()
	corte.from_dict(g, d["corte"])
	corte.su_messaggio = _su_messaggio
	locali = []
	for p in 7:
		if e_umano(p):
			locali.append(p)


func salva_locale() -> void:
	if online:
		return
	var f := FileAccess.open(FILE_LOCALE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(stato()))
		f.close()


static func c_e_locale() -> bool:
	return FileAccess.file_exists(FILE_LOCALE)


static func leggi_locale() -> Dictionary:
	if not FileAccess.file_exists(FILE_LOCALE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(FILE_LOCALE))
	return d if d is Dictionary else {}


## Salva la partita su Firebase: restituisce il codice di 6 lettere, o "" se non riesce.
func salva_in_rete(rete: Net) -> String:
	var c := await rete.save_game(stato(), codice_salvataggio)
	if c != "":
		codice_salvataggio = c
	return c


# ------------------------------------------------------------------ ordini

func consegna(p: int, o: Dictionary) -> void:
	if online:
		_accoda({"s": p, "k": "ord", "v": JSON.stringify(o)})
		return
	consegnati[p] = o
	aggiornata.emit()
	_controlla()


func ritira(p: int) -> void:
	if online:
		_accoda({"s": p, "k": "rit", "v": "1"})
		return
	consegnati.erase(p)
	aggiornata.emit()


func tutti_pronti() -> bool:
	for p in 7:
		if e_umano(p) and g.deve_ordinare(p) and not consegnati.has(p):
			return false
	return true


func _controlla() -> void:
	if in_calcolo or g.finita or not vivo:
		return
	if online and ruolo != "host":
		return
	if not tutti_pronti():
		return
	in_calcolo = true
	var tutti := []
	for p in 7:
		var o := {}
		if g.deve_ordinare(p):
			if e_umano(p):
				o = consegnati.get(p, {})
			else:
				avviso.emit("%s delibera…" % DPTesti.maiuscola(DPTesti.CANCELLERIE[p]))
				await get_tree().process_frame
				if not vivo:
					return
				o = corte.ordini_ia(p)
		tutti.append(o)
	avviso.emit("")
	if online:
		_accoda({"s": posto, "k": "ris", "v": JSON.stringify({"o": tutti})})
		return
	_risolvi(tutti)


func _risolvi(tutti: Array) -> void:
	for p in 7:
		g.imposta_ordini(p, DPGame._interi(tutti[p]))
	var voce := g.risolvi()
	if not online or (ruolo == "host" and not recupero):
		corte.dopo_risoluzione(voce)
	consegnati = {}
	if not recupero:
		salva_locale()
		risolta.emit(voce)


## Chiamata dalla vista quando ha finito di mostrare la risoluzione.
func prosegui() -> void:
	in_calcolo = false
	if g.finita:
		aggiornata.emit()
		return
	if not online or ruolo == "host":
		corte.apri_fase()
	if online and ruolo == "host":
		_accoda({"s": posto, "k": "ia", "v": JSON.stringify(_foto_ia())})
	aggiornata.emit()
	_controlla()


# ------------------------------------------------------------------ dispacci

func invia(m: Dictionary) -> void:
	if online:
		_accoda({"s": int(m["da"]), "k": "msg", "v": JSON.stringify(m)})
		return
	corte.spedisci(m)


func _su_messaggio(m: Dictionary) -> void:
	if online and ruolo == "host" and not recupero and corte.e_ia(m["da"]):
		# i dispacci delle IA viaggiano nel registro solo se riguardano una persona
		if m["a"] >= 0 and e_umano(m["a"]):
			var c := m.duplicate(true)
			c.erase("sincero")
			_accoda({"s": int(m["da"]), "k": "msg", "v": JSON.stringify(c)})
	if locali.has(m["a"]) or locali.has(m["da"]):
		posta.emit(m)


# ------------------------------------------------------------------ pareggio

func proponi_pareggio(p: int) -> void:
	if online:
		_accoda({"s": p, "k": "par", "v": "p"})
		return
	corte.proponi_pareggio(p)
	pareggio_proposto.emit(p)
	_esito_pareggio()


func vota_pareggio(p: int, si: bool) -> void:
	if online:
		_accoda({"s": p, "k": "par", "v": "1" if si else "0"})
		return
	corte.vota_pareggio(p, si)
	_esito_pareggio()


func _esito_pareggio() -> void:
	var e := corte.esito_pareggio()
	if e == 1:
		g.pareggio()
		salva_locale()
		avviso.emit("Pareggio concordato.")
		aggiornata.emit()
	elif e == -1:
		var contrari := []
		for x in corte.voti:
			if not corte.voti[x]:
				contrari.append(DPMap.POTENZE_BREVI[x])
		corte.voti = {}
		avviso.emit("Pareggio respinto da: %s." % ", ".join(contrari))
		aggiornata.emit()


# ------------------------------------------------------------------ online

func _foto_ia() -> Dictionary:
	var d := corte.to_dict(false)
	d.erase("msg")
	for x in d["dip"]:
		if x != null:
			x["diario"] = []
	return d


## Entra in una partita online. game: la configurazione scritta nella stanza. acts: mosse già giocate.
func avvia_online(rete: Net, p_codice: String, p_posto: int, p_ruolo: String, game: Dictionary, acts: Array) -> void:
	online = true
	net = rete
	codice = p_codice
	posto = p_posto
	ruolo = p_ruolo
	var posti := []
	for i in 7:
		posti.append("u" if str(game["posti"])[i] == "u" else "ia")
	cfg = {"posti": posti, "nomi": game.get("nomi", ["", "", "", "", "", "", ""]), "livello": int(game.get("livello", 2)),
		"ultimo_anno": int(game.get("ultimo_anno", 0)), "seme": int(game.get("seme", 1)), "classiche": true}
	g = DPGame.new()
	g.ultimo_anno = int(cfg["ultimo_anno"])
	corte = DPCorte.new()
	var umani := []
	for p in 7:
		umani.append(ruolo != "host" or e_umano(p))
	corte.crea(g, umani, int(cfg["livello"]), int(cfg["seme"]))
	corte.su_messaggio = _su_messaggio
	locali = [posto]
	# recupero di una partita già iniziata
	recupero = true
	var foto = null
	for i in acts.size():
		var a: Dictionary = acts[i]
		if a.get("k", "") == "ia":
			foto = a
		_applica(a, i)
	n = acts.size()
	if ruolo == "host" and foto != null:
		var posta_vecchia := corte.messaggi
		var d: Dictionary = JSON.parse_string(str(foto["v"]))
		d["msg"] = []
		corte.from_dict(g, d)
		corte.messaggi = posta_vecchia
		corte.su_messaggio = _su_messaggio
		for p in 7:
			corte.umano[p] = e_umano(p)
	recupero = false
	in_calcolo = false
	if ruolo == "host" and acts.is_empty():
		corte.apri_fase()
		_accoda({"s": posto, "k": "ia", "v": JSON.stringify(_foto_ia())})
	aggiornata.emit()
	_pompa()
	_presenza()
	if ruolo == "host":
		_controlla.call_deferred()


func _accoda(a: Dictionary) -> void:
	uscita.append(a)


## Il ciclo della rete: spedisce le mosse in coda e applica quelle che arrivano, in ordine.
func _pompa() -> void:
	while vivo:
		if not uscita.is_empty():
			if await net.post_act(codice, n, uscita[0]):
				if not vivo:
					return
				var a: Dictionary = uscita.pop_front()
				_applica(a, n)
				n += 1
				continue
		if not vivo:
			return
		var a := await net.get_act(codice, n)
		if not vivo:
			return
		if not a.is_empty() and not a.has("_err"):
			_applica(a, n)
			n += 1
			continue
		if a.has("_err"):
			avviso.emit("Rete non raggiungibile, riprovo…")
		await get_tree().create_timer(1.0 if uscita.is_empty() else 0.3).timeout


func _presenza() -> void:
	while vivo:
		net.heartbeat(codice, posto)
		await get_tree().create_timer(8.0).timeout


func _applica(a: Dictionary, idx: int) -> void:
	var k: String = str(a.get("k", ""))
	var s := int(a.get("s", -1))
	var v: String = str(a.get("v", ""))
	match k:
		"ord":
			consegnati[s] = DPGame._interi(JSON.parse_string(v))
			if not recupero:
				aggiornata.emit()
				_controlla()
		"rit":
			if not in_calcolo:
				consegnati.erase(s)
			if not recupero:
				aggiornata.emit()
		"msg":
			var m: Dictionary = DPGame._interi(JSON.parse_string(v))
			if not m.has("id"):
				m["id"] = 100000 + idx
			if ruolo == "host" and corte.e_ia(m["da"]) and not recupero:
				return                      # già registrato quando l'IA l'ha scritto
			if ruolo == "host" and not recupero:
				m.erase("testo")
				corte.spedisci(m)           # lo consegna anche alle IA, che rispondono
			else:
				corte.registra(m)
				if not recupero and (locali.has(m["a"]) or locali.has(m["da"])):
					posta.emit(m)
		"ris":
			var d: Dictionary = JSON.parse_string(v)
			in_calcolo = true
			_risolvi(d["o"])
			if recupero:
				in_calcolo = false
		"par":
			if v == "p":
				corte.voti = {s: true}
				if ruolo == "host" and not recupero:
					for x in 7:
						if x != s and g.viva(x) and corte.e_ia(x):
							_accoda({"s": x, "k": "par", "v": "1" if corte.voto_pareggio_ia(x) else "0"})
				if not recupero:
					pareggio_proposto.emit(s)
			else:
				corte.voti[s] = v == "1"
			var e := corte.esito_pareggio()
			if e == 1:
				g.pareggio()
				if not recupero:
					avviso.emit("Pareggio concordato.")
			elif e == -1:
				corte.voti = {}
				if not recupero:
					avviso.emit("Pareggio respinto.")
			if not recupero:
				aggiornata.emit()
		"aff":
			cfg["posti"][s] = "ia"
			if ruolo == "host":
				corte.affida_all_ia(s, true)
			if not recupero:
				aggiornata.emit()
				_controlla()


## Chi ospita affida all'IA il posto di un giocatore assente.
func affida_all_ia(p: int) -> void:
	if online and ruolo == "host" and e_umano(p) and p != posto:
		_accoda({"s": p, "k": "aff", "v": "1"})

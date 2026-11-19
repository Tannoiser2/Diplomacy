extends Control
## Menu principale: nuova partita (chi gioca ogni potenza, livello delle IA, durata), partita online
## con gli amici (stanze con codice), ripresa di una partita salvata, regole.

const LIVELLI := ["Console (facile)", "Ambasciatore (medio)", "Gran Maestro (da torneo)"]
const DURATE := [["Fino alla vittoria o al pareggio", 0], ["Fino all'inverno 1908", 1908], ["Fino all'inverno 1910", 1910], ["Fino all'inverno 1914", 1914]]

var main
var posti := ["ia", "ia", "ia", "ia", "u", "ia", "ia"]
var livello := 2
var durata := 0
var classiche := true
var destra: VBoxContainer
var sezione := "nuova"
# online
var on_name: LineEdit
var on_code: LineEdit
var mio_posto := 4
var aperti := [false, false, false, false, false, false, false]
var lobby := {}          # {code, seat, role}
var _lobby_viva := false
var carica_code: LineEdit
var messaggio := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		posti = st.get("posti", posti)
		livello = st.get("livello", livello)
		durata = st.get("durata", durata)
		classiche = st.get("classiche", classiche)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 36)
	add_child(m)
	var hb := UI.hbox(36)
	m.add_child(hb)
	var sx := UI.vbox(12)
	sx.custom_minimum_size.x = 560
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sx)
	var t := UI.title("Diplomacy", 170)
	t.custom_minimum_size.x = 540
	sx.add_child(t)
	var st2 := UI.label("Europa, 1901. Accordi, sotterfugi e tradimenti.", 28, UI.PARCH, UI.font_ital, true, 520)
	sx.add_child(st2)
	sx.add_child(UI.spacer(0, 18))
	for def in [["Nuova partita", "nuova"], ["Gioca online con gli amici", "online"], ["Carica una partita", "carica"]]:
		sx.add_child(UI.button(def[0], _apri.bind(def[1]), 480, 27))
	if DPSession.c_e_locale():
		sx.add_child(UI.primary("Continua l'ultima partita", _continua, 480, 27))
	sx.add_child(UI.button("Regole e consigli", func(): main.show_rules(), 480, 27))
	sx.add_child(UI.spacer(0, 0, true))
	sx.add_child(UI.label("Versione digitale per la ludoteca. Il gioco è di Allan B. Calhamer.", 18, UI.MUTED, UI.font_ital, true, 520))
	var pd := UI.panel(UI.dark_style(10, 0.93))
	pd.custom_minimum_size.x = 760
	pd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(pd)
	destra = UI.vbox(10)
	pd.add_child(destra)
	_apri(sezione)


func _exit_tree() -> void:
	_lobby_viva = false
	main.menu_state = {"posti": posti, "livello": livello, "durata": durata, "classiche": classiche}


func _svuota() -> void:
	for ch in destra.get_children():
		destra.remove_child(ch)
		ch.queue_free()


func _apri(s: String) -> void:
	sezione = s
	_lobby_viva = false
	_svuota()
	match s:
		"nuova":
			_pannello_nuova()
		"online":
			_online_panel()
		"carica":
			_pannello_carica()


func _scelta(testo: String, voci: Array, attuale: int, cb: Callable, largo := 400.0) -> HBoxContainer:
	var r := UI.hbox(12)
	var l := UI.label(testo, 23, UI.PARCH)
	l.custom_minimum_size.x = 250
	r.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(largo, 50)
	for i in voci.size():
		ob.add_item(str(voci[i]), i)
	ob.select(attuale)
	ob.item_selected.connect(cb)
	r.add_child(ob)
	return r


# ================================================================ nuova partita

func _pannello_nuova() -> void:
	destra.add_child(UI.head("Nuova partita", 32))
	destra.add_child(UI.label("Scegliete chi guida ogni potenza. Più persone sullo stesso dispositivo si passano lo schermo per gli ordini segreti.", 20, UI.MUTED, UI.font_ital, true, 700))
	for p in 7:
		var r := UI.hbox(12)
		r.add_child(UI.flag_rect(p, 34))
		var l := UI.head(DPMap.POTENZE[p], 24, DPMap.COLORI_TESTO[p])
		l.custom_minimum_size.x = 250
		r.add_child(l)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(230, 48)
		ob.add_item("IA", 0)
		ob.add_item("Persona", 1)
		ob.select(1 if posti[p] == "u" else 0)
		ob.item_selected.connect(func(i: int): posti[p] = "u" if i == 1 else "ia")
		r.add_child(ob)
		destra.add_child(r)
	var rb := UI.hbox(10)
	rb.add_child(UI.button("Una potenza a caso", _a_caso, 280, 21))
	rb.add_child(UI.button("Solo IA (osservo)", _solo_ia, 260, 21))
	destra.add_child(rb)
	destra.add_child(_scelta("Livello delle IA", LIVELLI, livello, func(i: int): livello = i))
	var nomi := []
	for d in DURATE:
		nomi.append(d[0])
	destra.add_child(_scelta("Durata", nomi, durata, func(i: int): durata = i))
	destra.add_child(_scelta("Pedine", ["Classiche: cannone e corazzata", "Del modulo: carro e nave"], 0 if classiche else 1, func(i: int): classiche = i == 0))
	destra.add_child(_scelta("Mappa", ["Tabellone originale", "Ridisegnata in italiano"], 0 if DPMap.preferenza() else 1, func(i: int): DPMap.salva_preferenza(i == 0)))
	destra.add_child(UI.spacer(0, 0, true))
	destra.add_child(UI.primary("Comincia", _comincia, 0, 28))


func _a_caso() -> void:
	var k := randi() % 7
	for p in 7:
		posti[p] = "u" if p == k else "ia"
	_apri("nuova")


func _solo_ia() -> void:
	for p in 7:
		posti[p] = "ia"
	_apri("nuova")


func _comincia() -> void:
	var ses := DPSession.new()
	var nomi := []
	for p in 7:
		nomi.append("" if posti[p] == "ia" else "Giocatore")
	ses.nuova({"posti": posti.duplicate(), "nomi": nomi, "livello": livello, "ultimo_anno": DURATE[durata][1],
		"classiche": classiche, "seme": randi() % 1000000})
	main.start_game(ses)
	ses.avvia()


func _continua() -> void:
	var d := DPSession.leggi_locale()
	if d.is_empty():
		return
	var ses := DPSession.new()
	ses.da_stato(d)
	main.start_game(ses)
	ses.aggiornata.emit()
	ses._controlla.call_deferred()


# ================================================================ carica

func _pannello_carica() -> void:
	destra.add_child(UI.head("Carica una partita", 32))
	destra.add_child(UI.label("Scrivete il codice di sei lettere ricevuto quando avete salvato la partita in rete (dal Menu, durante il gioco).", 22, UI.MUTED, UI.font_ital, true, 700))
	carica_code = LineEdit.new()
	carica_code.placeholder_text = "CODICE"
	carica_code.max_length = 6
	carica_code.custom_minimum_size = Vector2(300, 60)
	carica_code.add_theme_font_size_override("font_size", 34)
	destra.add_child(carica_code)
	destra.add_child(UI.primary("Carica", _carica, 0, 26))
	if messaggio != "":
		destra.add_child(UI.label(messaggio, 22, UI.CERA_L, null, true, 700))


func _carica() -> void:
	var c := carica_code.text.strip_edges().to_upper()
	if c.length() != 6:
		messaggio = "Il codice ha sei lettere."
		_apri("carica")
		return
	messaggio = "Carico…"
	_apri("carica")
	var net: Net = main.get_net()
	var d := await net.load_game(c)
	if not is_inside_tree():
		return
	if d.is_empty() or not d.has("g"):
		messaggio = "Partita non trovata. %s" % net.last_error
		_apri("carica")
		return
	var ses := DPSession.new()
	ses.da_stato(d)
	ses.codice_salvataggio = c
	main.start_game(ses)
	ses.aggiornata.emit()
	ses._controlla.call_deferred()


# ================================================================ online

func _online_panel() -> void:
	var net: Net = main.get_net()
	var salvati := net.load_session()
	destra.add_child(UI.head("Gioca online con gli amici", 32))
	if not lobby.is_empty():
		_pannello_lobby()
		return
	var rn := UI.hbox(12)
	var ln := UI.label("Il vostro nome", 23, UI.PARCH)
	ln.custom_minimum_size.x = 250
	rn.add_child(ln)
	on_name = LineEdit.new()
	on_name.max_length = 20
	on_name.custom_minimum_size = Vector2(400, 52)
	on_name.text = str(salvati.get("name", ""))
	rn.add_child(on_name)
	destra.add_child(rn)
	destra.add_child(UI.head("Creare una stanza", 25, UI.PARCH))
	destra.add_child(_scelta("La vostra potenza", DPMap.POTENZE, mio_posto, _scegli_posto))
	destra.add_child(UI.label("Posti per gli amici (gli altri li guida l'IA):", 21, UI.MUTED, null, true, 700))
	var griglia := GridContainer.new()
	griglia.columns = 3
	griglia.add_theme_constant_override("h_separation", 16)
	for p in 7:
		if p == mio_posto:
			continue
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = DPMap.POTENZE_BREVI[p]
		cb.custom_minimum_size = Vector2(210, 44)
		cb.button_pressed = aperti[p]
		cb.toggled.connect(func(on: bool): aperti[p] = on)
		griglia.add_child(cb)
	destra.add_child(griglia)
	destra.add_child(_scelta("Livello delle IA", LIVELLI, livello, func(i: int): livello = i))
	var nomi := []
	for d in DURATE:
		nomi.append(d[0])
	destra.add_child(_scelta("Durata", nomi, durata, func(i: int): durata = i))
	destra.add_child(UI.primary("Crea la stanza", _online_create, 0, 25))
	destra.add_child(UI.head("Entrare in una stanza", 25, UI.PARCH))
	var rc := UI.hbox(12)
	on_code = LineEdit.new()
	on_code.placeholder_text = "CODICE"
	on_code.max_length = 4
	on_code.custom_minimum_size = Vector2(220, 56)
	on_code.add_theme_font_size_override("font_size", 32)
	on_code.text = str(salvati.get("room", ""))
	rc.add_child(on_code)
	rc.add_child(UI.button("Entra", _online_join, 220, 25))
	destra.add_child(rc)
	if messaggio != "":
		destra.add_child(UI.label(messaggio, 21, UI.CERA_L, null, true, 700))


func _scegli_posto(i: int) -> void:
	mio_posto = i
	_apri("online")


func _nome() -> String:
	var n := on_name.text.strip_edges() if on_name != null else ""
	return n if n != "" else "Giocatore"


func _online_create() -> void:
	var net: Net = main.get_net()
	var seats := [mio_posto]
	for p in 7:
		if p != mio_posto and aperti[p]:
			seats.append(p)
	messaggio = "Creo la stanza…"
	var nome := _nome()
	_apri("online")
	var code := await net.create_room(nome, seats)
	if not is_inside_tree():
		return
	if code == "":
		messaggio = "Non riesco a creare la stanza. %s" % net.last_error
		_apri("online")
		return
	net._save({"name": nome})
	net.remember_room(code, mio_posto)
	messaggio = ""
	lobby = {"code": code, "seat": mio_posto, "role": "host"}
	_apri("online")


func _online_join() -> void:
	var net: Net = main.get_net()
	var code := on_code.text.strip_edges().to_upper()
	var nome := _nome()
	if code.length() != 4:
		messaggio = "Il codice della stanza ha quattro lettere."
		_apri("online")
		return
	messaggio = "Entro nella stanza…"
	_apri("online")
	var seat := await net.join_room(code, nome)
	if not is_inside_tree():
		return
	if seat < 0:
		messaggio = "La stanza non esiste, è piena o la partita è già cominciata. %s" % net.last_error
		_apri("online")
		return
	net._save({"name": nome})
	net.remember_room(code, seat)
	messaggio = ""
	var room: Dictionary = net.last_room
	lobby = {"code": code, "seat": seat, "role": "host" if room.get("host", "") == net.uid else "guest"}
	if room.get("status", "") == "playing":
		await _entra_in_partita(room)
		return
	_apri("online")


func _pannello_lobby() -> void:
	var cl := UI.head("Stanza %s" % lobby["code"], 60)
	destra.add_child(cl)
	destra.add_child(UI.label("Date questo codice agli amici: lo scrivono in «Entrare in una stanza».", 22, UI.MUTED, UI.font_ital, true, 700))
	var elenco := UI.vbox(6)
	elenco.name = "Elenco"
	destra.add_child(elenco)
	destra.add_child(UI.spacer(0, 0, true))
	if lobby["role"] == "host":
		destra.add_child(UI.primary("Comincia la partita", _online_start, 0, 26))
	else:
		destra.add_child(UI.label("In attesa che chi ha creato la stanza cominci la partita…", 23, UI.PARCH, null, true, 700))
	destra.add_child(UI.button("Lascia la stanza", _lascia, 0, 22))
	_lobby_viva = true
	_ciclo_lobby(elenco)


func _ciclo_lobby(elenco: VBoxContainer) -> void:
	var net: Net = main.get_net()
	while _lobby_viva and is_inside_tree() and is_instance_valid(elenco):
		var room := await net.room(lobby["code"])
		if not _lobby_viva or not is_inside_tree() or not is_instance_valid(elenco):
			return
		if room.is_empty():
			await get_tree().create_timer(1.5).timeout
			continue
		for ch in elenco.get_children():
			elenco.remove_child(ch)
			ch.queue_free()
		var seats := Net._as_dict(room.get("seats", {}))
		var open: Array = room.get("open", [])
		for p in 7:
			var r := UI.hbox(12)
			r.add_child(UI.flag_rect(p, 30))
			var l := UI.head(DPMap.POTENZE[p], 23, DPMap.COLORI_TESTO[p])
			l.custom_minimum_size.x = 250
			r.add_child(l)
			var chi := "IA"
			var col := UI.MUTED
			if seats.has(str(p)):
				chi = str(seats[str(p)].get("name", "Giocatore"))
				col = UI.VERDE
			elif open.has(float(p)) or open.has(p):
				chi = "posto libero (IA se resta vuoto)"
				col = UI.OTTONE_L
			var lc := UI.label(chi, 22, col)
			lc.custom_minimum_size.x = 330
			r.add_child(lc)
			elenco.add_child(r)
		if room.get("status", "") == "playing" and lobby["role"] != "host":
			_lobby_viva = false
			await _entra_in_partita(room)
			return
		await get_tree().create_timer(1.5).timeout


func _online_start() -> void:
	var net: Net = main.get_net()
	_lobby_viva = false
	var room := await net.room(lobby["code"])
	if not is_inside_tree():
		return
	var seats := Net._as_dict(room.get("seats", {}))
	var s := ""
	var nomi := []
	for p in 7:
		s += "u" if seats.has(str(p)) else "i"
		nomi.append(str(seats[str(p)].get("name", "")) if seats.has(str(p)) else "")
	var game := {"seme": randi() % 1000000, "livello": livello, "ultimo_anno": DURATE[durata][1], "posti": s, "nomi": nomi}
	if not await net.start_room(lobby["code"], game):
		messaggio = "Non riesco ad avviare la partita. %s" % net.last_error
		_apri("online")
		return
	var ses := DPSession.new()
	main.add_child(ses)
	ses.avvia_online(net, lobby["code"], lobby["seat"], "host", game, [])
	main.start_game(ses)


func _entra_in_partita(room: Dictionary) -> void:
	var net: Net = main.get_net()
	var game: Dictionary = room.get("game", {})
	var acts := await net.get_acts(lobby["code"])
	if not is_inside_tree():
		return
	var ses := DPSession.new()
	main.add_child(ses)
	ses.avvia_online(net, lobby["code"], lobby["seat"], lobby["role"], game, acts)
	main.start_game(ses)


func _lascia() -> void:
	_lobby_viva = false
	main.get_net().remember_room("")
	lobby = {}
	_apri("online")

extends Control
## Il gioco dal telefono: si entra nella stanza inquadrando il codice QR mostrato dal tabellone e da qui si
## fa tutta la parte segreta - diplomazia (dispacci, proposte, risposte) e ordini alle proprie unità.
## Niente mappa: quella sta sullo schermo grande. Solo testo, in verticale, con i pulsanti a misura di dito.

const BASE := Vector2i(480, 854)
const COLONNA := 580.0

var main
var codice := ""
## Per le prove: una sessione già pronta (si salta l'ingresso nella stanza).
var sessione_pronta: DPSession

var net: Net
var ses: DPSession
var g: DPGame
var io := -1
var posto := -1
var passo := "entra"            # entra | attesa | gioco
var scheda := "dispacci"
var con_chi := -1
var PANNELLO_W := 480.0         # la larghezza utile: la legge anche la scheda dei dispacci
var dispacci_ui
var ordini := {}
var rit_scelte := {}
var costruzioni := {}
var scioglimenti := {}
var _chiave_turno := ""
var _viva := true
var _popup: Control
var _nome := ""
var _avviso := ""

var margine: MarginContainer
var testa: VBoxContainer
var schede: HBoxContainer
var schede_btn := {}
var corpo: VBoxContainer
var piede: Label
var strato: Control
var nome_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var velo := ColorRect.new()
	velo.color = Color(0.05, 0.035, 0.025, 0.72)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(velo)
	margine = MarginContainer.new()
	margine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margine)
	var col := UI.vbox(8)
	margine.add_child(col)
	var pt := UI.panel(UI.dark_style(8, 0.96))
	col.add_child(pt)
	testa = UI.vbox(2)
	pt.add_child(testa)
	schede = UI.hbox(6)
	schede.visible = false
	col.add_child(schede)
	for def in [["dispacci", "Diplomazia"], ["ordini", "Ordini"], ["situazione", "Situazione"]]:
		var b := UI.button(def[1], _apri_scheda.bind(def[0]), 0, 17)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.35 if def[0] == "dispacci" else 1.0
		b.add_theme_stylebox_override("normal", UI.panel_style(UI.PANEL_L, UI.OTTONE, 2, 6, 4))
		b.add_theme_stylebox_override("pressed", UI.panel_style(Color("#5a241c"), UI.OTTONE_L, 2, 6, 4))
		b.add_theme_stylebox_override("hover", UI.panel_style(UI.PANEL_L, UI.OTTONE, 2, 6, 4))
		b.custom_minimum_size = Vector2(80, 54)
		b.clip_text = true
		schede.add_child(b)
		schede_btn[def[0]] = b
	var pc := UI.panel(UI.dark_style(8, 0.93))
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(pc)
	corpo = UI.vbox(8)
	pc.add_child(corpo)
	piede = UI.label("", 17, UI.MUTED, UI.font_ital, true, 300)
	piede.custom_minimum_size.y = 24
	col.add_child(piede)
	strato = Control.new()
	strato.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strato.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strato)
	dispacci_ui = preload("res://scripts/ui/dispacci_ui.gd").new()
	dispacci_ui.vista = self
	dispacci_ui.stretta = true
	get_window().size_changed.connect(_adatta)
	_adatta()
	if sessione_pronta != null:
		_entra_in_gioco(sessione_pronta)
	else:
		net = main.get_net()
		_nome = str(net.load_session().get("name", ""))
		_cerca_stanza()


func _exit_tree() -> void:
	_viva = false
	var w := get_window()
	if w != null:
		if w.size_changed.is_connected(_adatta):
			w.size_changed.disconnect(_adatta)
		w.content_scale_size = Vector2i(1920, 1080)


## Lo schermo del telefono è piccolo e di solito verticale: si disegna su una base stretta, così i
## caratteri restano leggibili; in orizzontale la colonna resta al centro.
func _adatta() -> void:
	var w := get_window()
	var verticale := w.size.y >= w.size.x
	var base := BASE if verticale else Vector2i(BASE.y, BASE.x)
	if w.content_scale_size != base:
		w.content_scale_size = base
	var largo := maxf(float(base.x), float(w.size.x) * float(base.y) / maxf(1.0, float(w.size.y))) if not verticale else float(base.x)
	PANNELLO_W = minf(largo, COLONNA)
	var lato := int(maxf(8.0, (largo - PANNELLO_W) * 0.5 + 8.0))
	margine.add_theme_constant_override("margin_left", lato)
	margine.add_theme_constant_override("margin_right", lato)
	margine.add_theme_constant_override("margin_top", 8)
	margine.add_theme_constant_override("margin_bottom", 8)


func _w() -> float:
	return PANNELLO_W - 78.0


func _svuota(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


func _testata(titolo: String, sotto: String, bandiera := -1) -> void:
	_svuota(testa)
	var hb := UI.hbox(10)
	if bandiera >= 0:
		var f := UI.flag_rect(bandiera, 40)
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(f)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.head(titolo, 26)
	t.clip_text = true
	t.custom_minimum_size.x = 200
	v.add_child(t)
	v.add_child(UI.label(sotto, 17, UI.MUTED, UI.font_ital, true, _w() - 40))
	hb.add_child(v)
	testa.add_child(hb)


func _grande(testo: String, cb: Callable, primario := false, size := 22) -> Button:
	var b: Button = UI.primary(testo, cb, 0, size) if primario else UI.button(testo, cb, 0, size)
	b.custom_minimum_size = Vector2(_w(), 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return b


# ================================================================ entrare nella stanza

func _cerca_stanza() -> void:
	passo = "entra"
	schede.visible = false
	_testata("Diplomacy", "Stanza %s" % codice)
	_svuota(corpo)
	corpo.add_child(UI.label("Cerco la stanza...", 22, UI.PARCH, null, true, _w()))
	if not await net.sign_in():
		if _viva:
			_errore("Non riesco a collegarmi. %s" % net.last_error)
		return
	var room := await net.room(codice)
	if not _viva:
		return
	if room.is_empty():
		_errore("La stanza %s non esiste più, o la rete non risponde." % codice)
		return
	var seats := Net._as_dict(room.get("seats", {}))
	for k in seats:
		if seats[k] is Dictionary and seats[k].get("uid", "") == net.uid:
			posto = int(k)
			_dopo_ingresso(room)
			return
	_svuota(corpo)
	corpo.add_child(UI.head("Entrate nella partita", 24))
	corpo.add_child(UI.label("Il vostro nome", 19, UI.MUTED))
	nome_edit = LineEdit.new()
	nome_edit.max_length = 20
	nome_edit.custom_minimum_size = Vector2(_w(), 58)
	nome_edit.add_theme_font_size_override("font_size", 24)
	nome_edit.text = _nome
	nome_edit.placeholder_text = "Giocatore"
	corpo.add_child(nome_edit)
	if room.get("status", "") != "lobby":
		corpo.add_child(UI.label("La partita è già cominciata. Se avevate un posto, scrivete lo stesso nome di prima per riprenderlo.", 20, UI.PARCH, null, true, _w()))
		corpo.add_child(_grande("Rientra", _prendi.bind(-1), true))
		return
	corpo.add_child(UI.label("Scegliete la vostra potenza", 19, UI.MUTED))
	var lista := UI.vbox(6)
	corpo.add_child(UI.scroll(lista))
	var liberi := 0
	for idx in room.get("open", []):
		var p := int(idx)
		if seats.has(str(p)):
			continue
		liberi += 1
		var b := _grande(DPMap.POTENZE[p], _prendi.bind(p))
		b.icon = UI.bandiera(p)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 54)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lista.add_child(b)
	if liberi == 0:
		lista.add_child(UI.label("Tutti i posti sono già occupati.", 21, UI.CERA_L, null, true, _w()))
		lista.add_child(_grande("Riprova", _cerca_stanza))


func _errore(t: String) -> void:
	_svuota(corpo)
	corpo.add_child(UI.label(t, 22, UI.CERA_L, null, true, _w()))
	corpo.add_child(_grande("Riprova", _cerca_stanza, true))


func _prendi(p: int) -> void:
	_nome = nome_edit.text.strip_edges() if nome_edit != null and is_instance_valid(nome_edit) else _nome
	if _nome == "":
		_nome = "Giocatore"
	_svuota(corpo)
	corpo.add_child(UI.label("Entro nella stanza...", 22, UI.PARCH, null, true, _w()))
	var s := await net.join_room(codice, _nome, p)
	if not _viva:
		return
	if s < 0:
		_errore("Non c'è posto: la partita è già cominciata, oppure qualcuno ha preso quella potenza un attimo prima.")
		return
	posto = s
	net._save({"name": _nome})
	net.remember_room(codice, s)
	_dopo_ingresso(net.last_room)


func _dopo_ingresso(room: Dictionary) -> void:
	if room.get("status", "") == "playing":
		_avvia(room)
		return
	passo = "attesa"
	_testata(DPMap.POTENZE[posto], "Stanza %s - in attesa degli altri" % codice, posto)
	_ciclo_attesa()


func _ciclo_attesa() -> void:
	while _viva and passo == "attesa":
		var room := await net.room(codice)
		if not _viva or passo != "attesa":
			return
		if not room.is_empty():
			if room.get("status", "") == "playing":
				_avvia(room)
				return
			_svuota(corpo)
			corpo.add_child(UI.head("Siete dentro", 24))
			corpo.add_child(UI.label("La partita comincia quando chi ha creato la stanza dà il via dal tabellone. Tenete aperta questa pagina.", 20, UI.PARCH, null, true, _w()))
			var seats := Net._as_dict(room.get("seats", {}))
			var open: Array = room.get("open", [])
			for p in 7:
				var r := UI.hbox(8)
				r.add_child(UI.flag_rect(p, 26))
				var chi := "IA"
				var col := UI.MUTED
				if seats.has(str(p)):
					chi = str(seats[str(p)].get("name", "Giocatore"))
					col = UI.VERDE
				elif open.has(float(p)) or open.has(p):
					chi = "posto libero"
					col = UI.OTTONE_L
				var l := UI.label("%s: %s" % [DPMap.POTENZE_BREVI[p], chi], 20, col)
				l.clip_text = true
				l.custom_minimum_size.x = _w() - 60
				r.add_child(l)
				corpo.add_child(r)
		await get_tree().create_timer(1.5).timeout


func _avvia(room: Dictionary) -> void:
	passo = "carica"
	_svuota(corpo)
	corpo.add_child(UI.label("Apro la partita...", 22, UI.PARCH, null, true, _w()))
	var game: Dictionary = room.get("game", {})
	var acts := await net.get_acts(codice)
	if not _viva:
		return
	var s := DPSession.new()
	main.add_child(s)
	main.sessione = s
	s.avvia_online(net, codice, posto, "guest", game, acts)
	_entra_in_gioco(s)


# ================================================================ la partita

func _entra_in_gioco(s: DPSession) -> void:
	ses = s
	g = ses.g
	passo = "gioco"
	schede.visible = true
	ses.aggiornata.connect(_su_aggiornata)
	ses.risolta.connect(_su_risolta)
	ses.posta.connect(_su_posta)
	ses.avviso.connect(_su_avviso)
	ses.pareggio_proposto.connect(_su_pareggio)
	_su_aggiornata()


func _su_aggiornata() -> void:
	var nuovo: int = ses.locali[0] if not ses.locali.is_empty() else -1
	var chiave := "%d-%d-%d-%d" % [g.anno, g.fase, nuovo, g.storia.size()]
	if chiave != _chiave_turno:
		_chiave_turno = chiave
		io = nuovo
		_prepara_ordini()
	_aggiorna_tutto()


func _prepara_ordini() -> void:
	ordini = {}
	rit_scelte = {}
	costruzioni = {}
	scioglimenti = {}
	if io < 0:
		return
	if g.e_movimento():
		for u in g.st.unita_di(io):
			ordini[u] = [DPAdj.H, -1, -1]
	elif g.e_ritirata():
		for r in g.ritirate_di(io):
			rit_scelte[r["prov"]] = -1


func ho_consegnato() -> bool:
	return io >= 0 and ses.consegnati.has(io)


func posso_ordinare() -> bool:
	return io >= 0 and not g.finita and g.deve_ordinare(io) and not ho_consegnato() and not ses.in_calcolo


func _da_leggere() -> int:
	var n := 0
	if io >= 0:
		for m in ses.corte.posta_di(io):
			if m["a"] == io and not m.get("letto", false):
				n += 1
	return n


func _aggiorna_tutto() -> void:
	if passo != "gioco":
		return
	var sotto := "%s %d" % [DPGame.NOMI_FASE[g.fase], g.anno]
	if g.finita:
		sotto = "Partita conclusa"
	elif io >= 0:
		sotto += " - %d centri, %d unità" % [g.st.n_centri(io), g.st.n_unita(io)]
	_testata(DPMap.POTENZE[io] if io >= 0 else "Diplomacy", sotto, io)
	_aggiorna_pannello()


func _aggiorna_pannello() -> void:
	if passo != "gioco":
		return
	var nl := _da_leggere()
	schede_btn["dispacci"].text = "Diplomazia (%d)" % nl if nl > 0 else "Diplomazia"
	var da_fare := posso_ordinare()
	schede_btn["ordini"].text = "Ordini (!)" if da_fare else "Ordini"
	for k in schede_btn:
		schede_btn[k].set_pressed_no_signal(k == scheda)
	_svuota(corpo)
	match scheda:
		"dispacci":
			dispacci_ui.costruisci(corpo)
		"ordini":
			_scheda_ordini()
		"situazione":
			_scheda_situazione()
	if _avviso == "":
		piede.text = _riga_attesa()
	else:
		piede.text = _avviso


func _apri_scheda(k: String) -> void:
	scheda = k
	_chiudi_popup()
	_aggiorna_pannello()


## Apre la corrispondenza con una potenza (-1: il quadro diplomatico).
func _apri_conversazione(p: int) -> void:
	if p == io:
		return
	con_chi = p
	scheda = "dispacci"
	_aggiorna_pannello()


func _riga_attesa() -> String:
	if g.finita:
		return "La partita è conclusa."
	var manca := []
	for p in 7:
		if ses.e_umano(p) and g.deve_ordinare(p) and not ses.consegnati.has(p):
			manca.append(DPMap.POTENZE_BREVI[p])
	if not manca.is_empty():
		return "In attesa degli ordini di: %s." % ", ".join(manca)
	return "Le cancellerie deliberano: guardate il tabellone."


# ---------------------------------------------------------------- ordini

func _testo(t: String, col: Color = UI.TEXT, size := 20) -> Label:
	return UI.label(t, size, col, null, true, _w())


## L'ordine scritto per esteso: sul telefono non c'è la mappa ad aiutare.
func _testo_ordine(u: int, o: Array) -> String:
	var chi := _nome_unita(u)
	match int(o[0]):
		DPAdj.M:
			return "%s: muove in %s%s" % [chi, DPMap.nome_loc(int(o[1])), ", via convoglio" if int(o[2]) == 1 else ""]
		DPAdj.S:
			if int(o[2]) == int(o[1]):
				return "%s: sostiene %s, che resta ferma" % [chi, _unita_con_potenza(int(o[1]))]
			return "%s: sostiene %s verso %s" % [chi, _unita_con_potenza(int(o[1])), DPMap.nome[int(o[2])]]
		DPAdj.C:
			return "%s: convoglia %s verso %s" % [chi, _unita_con_potenza(int(o[1])), DPMap.nome[int(o[2])]]
	return "%s: resta ferma" % chi


func _nome_unita(u: int) -> String:
	return "%s %s" % [DPGame.nome_unita(g.st.ut[u]), DPMap.nome_loc(g.st.ul[u])]


func _scheda_ordini() -> void:
	if io < 0:
		corpo.add_child(_testo("Da qui non si guida nessuna potenza.", UI.MUTED))
		return
	if g.finita:
		corpo.add_child(_testo("La partita è conclusa. Il risultato è nella scheda Situazione.", UI.PARCH))
		return
	if not g.deve_ordinare(io):
		corpo.add_child(_testo("Nessun ordine da dare in questa fase.", UI.PARCH))
		return
	if ho_consegnato():
		corpo.add_child(_testo("Ordini consegnati. Restano segreti fino alla risoluzione.", UI.VERDE, 22))
		var lista0 := UI.vbox(2)
		corpo.add_child(UI.scroll(lista0))
		if g.e_movimento():
			var miei: Dictionary = ses.consegnati[io]
			for u in miei:
				if g.st.up[int(u)] == io:
					lista0.add_child(_testo(_testo_ordine(int(u), miei[u]), UI.TEXT, 19))
		if not ses.in_calcolo and not ses.tutti_pronti():
			corpo.add_child(_grande("Modifica gli ordini", _ritira))
		return
	var lista := UI.vbox(6)
	corpo.add_child(UI.scroll(lista))
	if g.e_movimento():
		lista.add_child(_testo("Toccate un'unità per cambiarle l'ordine. Senza ordini resta ferma.", UI.MUTED, 18))
		for u in g.st.unita_di(io):
			var o: Array = ordini.get(u, [DPAdj.H, -1, -1])
			var b := _grande(_testo_ordine(u, o), _scegli_ordine.bind(u, "", -1), false, 21)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if int(o[0]) != DPAdj.H:
				b.add_theme_color_override("font_color", Color.WHITE)
			lista.add_child(b)
		corpo.add_child(_grande("Consegna gli ordini", _consegna, true, 24))
	elif g.e_ritirata():
		lista.add_child(_testo("Scegliete dove si ritira ogni unità scacciata. Due unità che si ritirano nella stessa provincia si sciolgono entrambe.", UI.MUTED, 18))
		for r in g.ritirate_di(io):
			var pr := int(r["prov"])
			var dove: int = rit_scelte.get(pr, -1)
			var t := "%s %s: %s" % [DPGame.nome_unita(r["t"]), DPMap.nome_loc(r["loc"]), ("si ritira in %s" % DPMap.nome_loc(dove)) if dove >= 0 else "si scioglie"]
			var b := _grande(t, _scegli_ritirata.bind(r), false, 21)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			lista.add_child(b)
		corpo.add_child(_grande("Consegna le ritirate", _consegna, true, 24))
	else:
		var d := g.saldo(io)
		if d > 0:
			lista.add_child(_testo("Potete costruire %d unità nei vostri centri di casa liberi." % d, UI.PARCH))
			for pr in g.case_libere(io):
				var t := "%s: nessuna costruzione" % DPMap.nome[pr]
				if costruzioni.has(pr):
					var c: Array = costruzioni[pr]
					t = "%s: %s" % [DPMap.nome[pr], DPGame.nome_unita(int(c[0]))]
					if int(c[1]) >= DPMap.N_PROV:
						t = "%s: flotta (%s)" % [DPMap.nome[pr], DPMap.nome_costa(DPMap.costa_nome[int(c[1])])]
				var b := _grande(t, _scegli_costruzione.bind(pr), false, 21)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				lista.add_child(b)
			corpo.add_child(_grande("Consegna le costruzioni", _consegna, true, 24))
		else:
			lista.add_child(_testo("Avete più unità che centri: scegliete %d unità da sciogliere." % -d, UI.CERA_L))
			for u in g.st.unita_di(io):
				var b := _grande("%s: %s" % [_nome_unita(u), "SI SCIOGLIE" if scioglimenti.has(u) else "resta"], _alterna_scioglimento.bind(u), false, 21)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				if scioglimenti.has(u):
					b.add_theme_color_override("font_color", UI.CERA_L)
				lista.add_child(b)
			corpo.add_child(_grande("Consegna gli scioglimenti", _consegna, true, 24))


func _ritira() -> void:
	ses.ritira(io)


## Province in cui un'armata può sbarcare per convoglio: quelle raggiungibili con una catena di flotte in mare.
func _sbarchi(u: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var st := g.st
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
func _bersagli_sostegno(chi: int, u: int) -> Array:
	var st := g.st
	var o := []
	if u < 0 or st.up[u] < 0 or u == chi:
		return o
	if DPMap.tocca(st.ut[chi], st.ul[chi], u):
		o.append(u)
	var dest := {}
	for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
		dest[DPMap.loc_prov[l]] = true
	for x in _sbarchi(u):
		dest[x] = true
	for x in dest:
		if x != chi and DPMap.tocca(st.ut[chi], st.ul[chi], x):
			o.append(x)
	return o


func _unita_con_potenza(u: int) -> String:
	return "%s (%s)" % [_nome_unita(u), DPMap.POTENZE_BREVI[g.st.up[u]]]


## La scelta dell'ordine, un passo alla volta: che cosa fa, poi dove o chi.
func _scegli_ordine(u: int, fase: String, altra: int) -> void:
	if not posso_ordinare():
		return
	var st := g.st
	var v := _finestra()
	v.add_child(UI.head(_nome_unita(u), 25))
	var voci := []                      # [testo, callable]
	match fase:
		"":
			v.add_child(_testo("Che cosa deve fare?", UI.MUTED, 19))
			voci.append(["Resta ferma", _ordina.bind(u, [DPAdj.H, -1, -1])])
			voci.append(["Muove...", _scegli_ordine.bind(u, "muovi", -1)])
			var sost := false
			for x in DPMap.N_PROV:
				if st.up[x] >= 0 and x != u and not _bersagli_sostegno(u, x).is_empty():
					sost = true
					break
			if sost:
				voci.append(["Sostiene un'altra unità...", _scegli_ordine.bind(u, "sost1", -1)])
			if st.ut[u] == 1 and DPMap.tipo[u] == DPMap.MARE:
				var conv := false
				for x in DPMap.N_PROV:
					if st.up[x] >= 0 and st.ut[x] == 0 and not _sbarchi(x).is_empty():
						conv = true
						break
				if conv:
					voci.append(["Convoglia un'armata...", _scegli_ordine.bind(u, "conv1", -1)])
		"muovi":
			v.add_child(_testo("Dove muove?", UI.MUTED, 19))
			if st.ut[u] == 1:
				for l in DPMap.destinazioni(1, st.ul[u]):
					voci.append([DPTesti.maiuscola(DPMap.nome_loc(l)), _ordina.bind(u, [DPAdj.M, l, 0])])
			else:
				for x in DPMap.adj_a[u]:
					voci.append([DPMap.nome[x], _ordina.bind(u, [DPAdj.M, x, 0])])
				for x in _sbarchi(u):
					voci.append(["%s, via convoglio" % DPMap.nome[x], _ordina.bind(u, [DPAdj.M, x, 1])])
		"sost1":
			v.add_child(_testo("Quale unità sostiene?", UI.MUTED, 19))
			for x in DPMap.N_PROV:
				if st.up[x] >= 0 and x != u and not _bersagli_sostegno(u, x).is_empty():
					voci.append([_unita_con_potenza(x), _scegli_ordine.bind(u, "sost2", x)])
		"sost2":
			v.add_child(_testo("Sostiene %s:" % _unita_con_potenza(altra), UI.MUTED, 19))
			for x in _bersagli_sostegno(u, altra):
				var t := "perché resti ferma" if x == altra else "nella mossa verso %s" % DPMap.nome[x]
				voci.append([t, _ordina.bind(u, [DPAdj.S, altra, x])])
		"conv1":
			v.add_child(_testo("Quale armata convoglia?", UI.MUTED, 19))
			for x in DPMap.N_PROV:
				if st.up[x] >= 0 and st.ut[x] == 0 and not _sbarchi(x).is_empty():
					voci.append([_unita_con_potenza(x), _scegli_ordine.bind(u, "conv2", x)])
		"conv2":
			v.add_child(_testo("Convoglia %s verso:" % _unita_con_potenza(altra), UI.MUTED, 19))
			for x in _sbarchi(altra):
				voci.append([DPMap.nome[x], _ordina.bind(u, [DPAdj.C, altra, x])])
	if voci.is_empty():
		v.add_child(_testo("Nessuna scelta possibile.", UI.CERA_L))
	for x in voci:
		var b := _grande(x[0], x[1], false, 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	if fase != "":
		v.add_child(_grande("Indietro", _scegli_ordine.bind(u, "", -1)))
	v.add_child(_grande("Annulla", _chiudi_popup))


func _ordina(u: int, o: Array) -> void:
	ordini[u] = o
	_chiudi_popup()
	_aggiorna_pannello()


func _scegli_ritirata(r: Dictionary) -> void:
	var v := _finestra()
	v.add_child(UI.head("%s %s" % [DPGame.nome_unita(r["t"]), DPMap.nome_loc(r["loc"])], 25))
	v.add_child(_testo("Dove si ritira?", UI.MUTED, 19))
	for l in r["opzioni"]:
		v.add_child(_grande(DPTesti.maiuscola(DPMap.nome_loc(l)), _ritirata.bind(int(r["prov"]), int(l))))
	v.add_child(_grande("Si scioglie", _ritirata.bind(int(r["prov"]), -1)))
	v.add_child(_grande("Annulla", _chiudi_popup))


func _ritirata(prov: int, dove: int) -> void:
	rit_scelte[prov] = dove
	_chiudi_popup()
	_aggiorna_pannello()


func _scegli_costruzione(pr: int) -> void:
	var v := _finestra()
	v.add_child(UI.head(DPMap.nome[pr], 25))
	v.add_child(_testo("Che cosa costruite qui?", UI.MUTED, 19))
	v.add_child(_grande("Armata", _costruisci_qui.bind(pr, [0, pr])))
	if DPMap.tipo[pr] == DPMap.COSTA:
		var cs: PackedInt32Array = DPMap.coste_di[pr]
		if cs.is_empty():
			v.add_child(_grande("Flotta", _costruisci_qui.bind(pr, [1, pr])))
		else:
			for l in cs:
				v.add_child(_grande("Flotta (%s)" % DPMap.nome_costa(DPMap.costa_nome[l]), _costruisci_qui.bind(pr, [1, l])))
	v.add_child(_grande("Nessuna costruzione", _costruisci_qui.bind(pr, [])))
	v.add_child(_grande("Annulla", _chiudi_popup))


func _costruisci_qui(pr: int, c: Array) -> void:
	if c.is_empty():
		costruzioni.erase(pr)
	else:
		costruzioni[pr] = c
	_chiudi_popup()
	_aggiorna_pannello()


func _alterna_scioglimento(u: int) -> void:
	if scioglimenti.has(u):
		scioglimenti.erase(u)
	else:
		scioglimenti[u] = true
	_aggiorna_pannello()


func _consegna() -> void:
	if not posso_ordinare():
		return
	var o := {}
	if g.e_movimento():
		o = ordini.duplicate(true)
	elif g.e_ritirata():
		o = rit_scelte.duplicate()
	else:
		var d := g.saldo(io)
		if d > 0:
			if costruzioni.size() > d:
				_avviso_popup("Potete costruire al massimo %d unità." % d)
				return
			o = {"c": costruzioni.values()}
		else:
			if scioglimenti.size() != -d:
				_avviso_popup("Dovete scegliere esattamente %d unità da sciogliere." % -d)
				return
			o = {"s": scioglimenti.keys()}
	ses.consegna(io, o)


# ---------------------------------------------------------------- situazione

func _scheda_situazione() -> void:
	var w := _w() - 10
	var box := UI.vbox(3)
	corpo.add_child(UI.scroll(box))
	if g.finita:
		box.add_child(UI.head("Partita conclusa", 23))
		if g.vincitore >= 0 and g.pari.size() <= 1:
			box.add_child(UI.label("Vince %s." % DPTesti.CON_ARTICOLO[g.vincitore], 21, UI.PARCH, null, true, w))
		else:
			var nomi := []
			for p in g.pari:
				nomi.append(DPMap.POTENZE_BREVI[int(p)])
			box.add_child(UI.label("Pareggio fra: %s." % ", ".join(nomi), 21, UI.PARCH, null, true, w))
	box.add_child(UI.head("Le potenze", 22))
	for p in 7:
		var r := UI.hbox(8)
		var f := UI.flag_rect(p, 24)
		f.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		r.add_child(f)
		var col := UI.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chi := ses.nome(p) if ses.e_umano(p) else "IA"
		var t := UI.head("%s (%s) - %d centri" % [DPMap.POTENZE_BREVI[p], chi, g.st.n_centri(p)], 19, DPMap.COLORI_TESTO[p])
		t.clip_text = true
		t.custom_minimum_size.x = w - 50
		col.add_child(t)
		var un := []
		for u in g.st.unita_di(p):
			un.append("%s %s" % [DPGame.sigla_unita(g.st.ut[u]), DPMap.nome_loc(g.st.ul[u])])
		col.add_child(UI.label(", ".join(un) if not un.is_empty() else ("Eliminata." if not g.viva(p) else "Nessuna unità."), 17, UI.MUTED if p != io else UI.TEXT, null, true, w - 50))
		r.add_child(col)
		box.add_child(r)
	if io >= 0:
		var miei := []
		for c in DPMap.centri:
			if g.st.sc[c] == io:
				miei.append(DPMap.nome[c])
		miei.sort()
		box.add_child(UI.head("I vostri centri", 22))
		box.add_child(UI.label(", ".join(miei) + ".", 18, UI.TEXT, null, true, w))
	if not g.storia.is_empty():
		var voce: Dictionary = g.storia[g.storia.size() - 1]
		box.add_child(UI.head("Ultima fase: %s %d" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]], 22))
		_righe_voce(box, voce, w)
	if io >= 0 and not g.finita:
		box.add_child(UI.spacer(0, 8))
		box.add_child(_grande("Proponi il pareggio", _proponi_pareggio))
	if ses.online:
		box.add_child(UI.label("Stanza %s. Se chiudete la pagina, riaprite lo stesso indirizzo per rientrare." % ses.codice, 16, UI.MUTED, UI.font_ital, true, w))


func _righe_voce(box: VBoxContainer, voce: Dictionary, w: float) -> void:
	var prima := DPState.from_dict(voce["prima"])
	if voce.has("ordini"):
		for p in 7:
			var righe := []
			for u in voce["ordini"]:
				if prima.up[u] == p:
					righe.append([DPGame.testo_ordine(prima, u, voce["ordini"][u], true), DPGame.testo_esito(int(voce["esiti"][u]), int(voce["ordini"][u][0]))])
			if righe.is_empty():
				continue
			box.add_child(UI.head(DPMap.POTENZE[p], 18, DPMap.COLORI_TESTO[p]))
			for r in righe:
				box.add_child(UI.label(r[0] + ("  (%s)" % r[1] if r[1] != "" else ""), 17, UI.CERA_L if r[1] != "" else UI.TEXT, null, true, w))
		for x in voce.get("sloggiate", []):
			box.add_child(UI.label("%s %s è scacciata." % [DPGame.nome_unita(prima.ut[x[0]]), DPMap.nome[x[0]]], 17, UI.OTTONE_L, null, true, w))
		for x in voce.get("distrutte", []):
			box.add_child(UI.label("%s %s (%s) non ha vie di ritirata: è distrutta." % [DPGame.nome_unita(x[2]), DPMap.nome[x[0]], DPMap.POTENZE_BREVI[x[1]]], 17, UI.CERA_L, null, true, w))
	elif voce.has("ritirate"):
		for r in voce["ritirate"]:
			var s := "%s: %s %s " % [DPMap.POTENZE_BREVI[r[1]], DPGame.sigla_unita(r[2]), DPMap.nome_loc(r[3])]
			if r[5] >= 0:
				s += "si ritira in %s." % DPMap.nome_loc(r[5])
			elif r[4] >= 0:
				s += "si scioglie (ritirata contesa)."
			else:
				s += "si scioglie."
			box.add_child(UI.label(s, 17, UI.TEXT, null, true, w))
	else:
		for x in voce.get("costruite", []):
			box.add_child(UI.label("%s costruisce: %s %s." % [DPMap.POTENZE_BREVI[x[0]], DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], 17, UI.TEXT, null, true, w))
		for x in voce.get("sciolte", []):
			box.add_child(UI.label("%s scioglie: %s %s." % [DPMap.POTENZE_BREVI[x[0]], DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], 17, UI.TEXT, null, true, w))
		if voce.get("costruite", []).is_empty() and voce.get("sciolte", []).is_empty():
			box.add_child(UI.label("Nessun cambiamento.", 17, UI.MUTED, null, true, w))


func _proponi_pareggio() -> void:
	ses.proponi_pareggio(io)
	_su_avviso("Proposta di pareggio inviata.")


# ---------------------------------------------------------------- finestre

func _chiudi_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


## Una scheda a tutto schermo che scorre: sul telefono le finestre piccole non servono.
func _finestra(_larghezza := 0.0) -> VBoxContainer:
	_chiudi_popup()
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.6)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strato.add_child(velo)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lato: int = margine.get_theme_constant("margin_left") + 6
	m.add_theme_constant_override("margin_left", lato)
	m.add_theme_constant_override("margin_right", lato)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 24)
	velo.add_child(m)
	var p := UI.panel(UI.dark_style(10, 0.99))
	m.add_child(p)
	var v := UI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UI.scroll(v)
	p.add_child(sc)
	_popup = velo
	return v


func _avviso_popup(t: String) -> void:
	var v := _finestra()
	v.add_child(UI.label(t, 22, UI.PARCH, null, true, _w()))
	v.add_child(_grande("Va bene", _chiudi_popup, true))


# ---------------------------------------------------------------- segnali della partita

func _su_avviso(t: String) -> void:
	_avviso = t
	piede.text = t if t != "" else _riga_attesa()
	if t == "":
		return
	await get_tree().create_timer(5.0).timeout
	if _viva and _avviso == t:
		_avviso = ""
		piede.text = _riga_attesa()


func _su_posta(m: Dictionary) -> void:
	if m["a"] == io:
		Input.vibrate_handheld(80)
		if scheda != "dispacci" or con_chi != int(m["da"]):
			_su_avviso("Nuovo dispaccio %s." % DPTesti.DA_CANC[m["da"]])
	if _popup == null or not is_instance_valid(_popup):
		_aggiorna_pannello()
	else:
		var nl := _da_leggere()
		schede_btn["dispacci"].text = "Diplomazia (%d)" % nl if nl > 0 else "Diplomazia"


func _su_risolta(voce: Dictionary) -> void:
	_chiudi_popup()
	Input.vibrate_handheld(120)
	scheda = "situazione"
	_chiave_turno = ""
	ses.prosegui()
	_su_avviso("%s %d risolta: guardate il tabellone." % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]])


func _su_pareggio(da: int) -> void:
	if io < 0 or da == io or not g.viva(io) or ses.corte.voti.has(io):
		return
	var v := _finestra()
	v.add_child(UI.head("Proposta di pareggio", 25))
	v.add_child(UI.label("%s propone di chiudere la partita con un pareggio fra le potenze superstiti. Accettate?" % DPTesti.maiuscola(DPTesti.CON_ARTICOLO[da]), 21, UI.PARCH, null, true, _w()))
	v.add_child(_grande("Accetto", _voto.bind(true), true))
	v.add_child(_grande("Rifiuto", _voto.bind(false)))


func _voto(si: bool) -> void:
	_chiudi_popup()
	ses.vota_pareggio(io, si)

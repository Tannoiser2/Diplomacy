extends Control
## La partita: mappa 3D a tutto schermo, barra delle potenze in alto, pannello a destra con ordini,
## dispacci e storico, barra degli ordini in basso quando si seleziona un'unità.
##
## Dare un ordine: si tocca una propria unità e poi la destinazione (mossa); con i pulsanti in basso
## si passa a Sostieni (si tocca l'unità da sostenere, poi dove), Convoglia (l'armata, poi lo sbarco)
## o Ferma. Gli ordini restano modificabili finché non si consegnano.

const PANNELLO_W := 452.0
const C_MOSSA := Color(1.0, 0.86, 0.3, 0.75)
const C_MARE := Color(0.35, 0.75, 1.0, 0.75)
const C_SOST := Color(0.55, 1.0, 0.5, 0.75)

var main
var config := {}
var ses: DPSession
var g: DPGame
var board
var io := -1
var ordini := {}
var rit_scelte := {}
var costruzioni := {}       # provincia di casa -> [tipo, loc]
var scioglimenti := {}      # provincia -> true
var sel := -1
var modo := ""
var sost_unita := -1
var conv_armata := -1
var scheda := "ordini"
var con_chi := -1            # potenza della conversazione aperta
var storico_idx := -1
var in_replay := false
var coda_voci: Array = []
var _chiave_turno := ""
var _attesa_continua := false

var barra: HBoxContainer
var titolo_fase: Label
var sotto_fase: Label
var chip: Array = []
var pannello: PanelContainer
var corpo: VBoxContainer
var schede_btn := {}
var attrezzi: PanelContainer
var attrezzi_box: HBoxContainer
var suggerimento: Label
var strato: Control
var stato_lbl: Label
var dispacci_ui
var _popup: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ses = config["sessione"]
	g = ses.g
	DPMap.usa(DPMap.preferenza())
	board = preload("res://scripts/ui/board_3d.gd").new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	board.classiche = bool(ses.cfg.get("classiche", true))
	board.margine_destro = PANNELLO_W
	board.margine_alto = 74.0
	board.margine_basso = 70.0
	board.setup()
	board.tocco.connect(_su_tocco)
	_costruisci()
	dispacci_ui = preload("res://scripts/ui/dispacci_ui.gd").new()
	dispacci_ui.vista = self
	ses.aggiornata.connect(_su_aggiornata)
	ses.risolta.connect(_su_risolta)
	ses.posta.connect(_su_posta)
	ses.avviso.connect(_su_avviso)
	_benvenuto()
	ses.pareggio_proposto.connect(_su_pareggio)
	_su_aggiornata()


# ================================================================ struttura

func _costruisci() -> void:
	# barra in alto
	var top := UI.panel(UI.panel_style(Color(UI.PANEL, 0.94), Color(UI.OTTONE, 0.6), 2, 0, 8))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 74
	add_child(top)
	barra = UI.hbox(10)
	top.add_child(barra)
	barra.add_child(UI.button("Menu", _menu, 110, 22))
	var tf := UI.vbox(0)
	tf.custom_minimum_size.x = 330
	titolo_fase = UI.head("", 28)
	sotto_fase = UI.label("", 18, UI.MUTED, UI.font_ital)
	tf.add_child(titolo_fase)
	tf.add_child(sotto_fase)
	barra.add_child(tf)
	barra.add_child(UI.button("Centra", func(): board.reset_view(), 104, 19))
	barra.add_child(UI.button("Dall'alto", _vista_alto, 118, 19))
	barra.add_child(UI.spacer(0, 0, true))
	for p in 7:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(118, 56)
		b.tooltip_text = DPMap.POTENZE[p]
		var hb := UI.hbox(6)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(UI.flag_rect(p, 30))
		var l := UI.head("3", 24, Color.WHITE)
		l.custom_minimum_size.x = 34
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		b.add_child(hb)
		b.pressed.connect(_apri_conversazione.bind(p))
		barra.add_child(b)
		chip.append({"b": b, "l": l})
	# pannello a destra
	pannello = UI.panel(UI.panel_style(UI.PANEL, Color(UI.OTTONE, 0.6), 2, 0, 10))
	pannello.anchor_left = 1.0
	pannello.anchor_right = 1.0
	pannello.anchor_bottom = 1.0
	pannello.offset_left = -PANNELLO_W
	pannello.offset_top = 74
	add_child(pannello)
	var pv := UI.vbox(8)
	pannello.add_child(pv)
	var tabs := UI.hbox(6)
	pv.add_child(tabs)
	for k in [["ordini", "Ordini"], ["dispacci", "Diplomazia"], ["storico", "Storico"]]:
		var b := UI.button(k[1], _apri_scheda.bind(k[0]), 0, 21)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 120
		tabs.add_child(b)
		schede_btn[k[0]] = b
	corpo = UI.vbox(8)
	corpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(corpo)
	# barra degli ordini (in basso a sinistra)
	attrezzi = UI.panel(UI.dark_style(8, 0.96))
	attrezzi.anchor_top = 1.0
	attrezzi.anchor_bottom = 1.0
	attrezzi.anchor_right = 1.0
	attrezzi.offset_left = 14
	attrezzi.offset_right = -PANNELLO_W - 14
	attrezzi.offset_top = -66
	attrezzi.offset_bottom = -12
	add_child(attrezzi)
	var av := UI.vbox(6)
	attrezzi.add_child(av)
	suggerimento = UI.label("", 22, UI.PARCH, null)
	suggerimento.clip_text = true
	suggerimento.custom_minimum_size.x = 300
	av.add_child(suggerimento)
	attrezzi_box = UI.hbox(8)
	av.add_child(attrezzi_box)
	# messaggio di stato (in alto a sinistra, sotto la barra)
	stato_lbl = UI.label("", 22, UI.OTTONE_L, UI.font_ital)
	stato_lbl.position = Vector2(18, 84)
	stato_lbl.custom_minimum_size.x = 600
	stato_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	stato_lbl.add_theme_constant_override("shadow_offset_x", 2)
	stato_lbl.add_theme_constant_override("shadow_offset_y", 2)
	stato_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stato_lbl)
	strato = Control.new()
	strato.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strato.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strato)


func _vista_alto() -> void:
	board.pitch = 1.5 if board.pitch < 1.4 else 1.02
	board.yaw = 0.0
	board._cam()


func _apri_scheda(k: String) -> void:
	if in_replay:
		return
	scheda = k
	if k != "storico" and storico_idx >= 0:
		storico_idx = -1
		_mostra_presente()
	_aggiorna_pannello()


## La prima volta, a inizio partita, ricorda che prima degli ordini si tratta: è il cuore del gioco.
func _benvenuto() -> void:
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree() or io < 0 or not g.storia.is_empty() or g.finita or _popup != null:
		return
	var c := ConfigFile.new()
	c.load(DPMap.FILE_OPZIONI)
	if bool(c.get_value("aiuto", "diplomazia", false)):
		return
	c.set_value("aiuto", "diplomazia", true)
	c.save(DPMap.FILE_OPZIONI)
	var v := _finestra(660)
	v.add_child(UI.head("Prima si tratta, poi si ordina", 28))
	v.add_child(UI.label("Le altre potenze vi scrivono e aspettano le vostre proposte: alleanze contro un nemico comune, patti di non aggressione, zone sgombre, sostegni per una mossa precisa.", 21, UI.TEXT, null, true, 620))
	v.add_child(UI.label("Nella scheda Diplomazia trovate il quadro dei rapporti con ogni potenza; toccatene una (o la sua bandiera in alto) per leggere i dispacci, rispondere e proporre. Le IA ricordano chi mantiene la parola e chi no - e a volte mentono anche loro.", 21, UI.TEXT, null, true, 620))
	var hb := UI.hbox(10)
	var apri := UI.primary("Apri la Diplomazia", _benvenuto_apri, 0, 24)
	apri.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var no := UI.button("Ho capito", _chiudi_popup, 0, 24)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(apri)
	hb.add_child(no)
	v.add_child(hb)


func _benvenuto_apri() -> void:
	_chiudi_popup()
	con_chi = -1
	_apri_scheda("dispacci")


## Apre la corrispondenza con una potenza (-1: il quadro diplomatico con tutte).
func _apri_conversazione(p: int) -> void:
	if p == io or in_replay or io < 0:
		return
	con_chi = p
	scheda = "dispacci"
	_aggiorna_pannello()


# ================================================================ turno

func locale_di_turno() -> int:
	# la persona, fra quelle a questo dispositivo, che deve ancora consegnare
	for p in ses.locali:
		if g.deve_ordinare(p) and not ses.consegnati.has(p):
			return p
	if io >= 0 and ses.locali.has(io):
		return io
	for p in ses.locali:
		if g.viva(p):
			return p
	return ses.locali[0] if not ses.locali.is_empty() else -1


func _su_aggiornata() -> void:
	if in_replay:
		return
	var nuovo := locale_di_turno()
	var chiave := "%d-%d-%d-%d" % [g.anno, g.fase, nuovo, g.storia.size()]
	if chiave != _chiave_turno:
		var cambio_persona := nuovo != io and io >= 0 and ses.locali.size() > 1 and not g.finita
		_chiave_turno = chiave
		io = nuovo
		_prepara_ordini()
		if cambio_persona and g.deve_ordinare(io):
			_passa_dispositivo()
	_mostra_presente()
	_aggiorna_tutto()
	if g.finita:
		_fine.call_deferred()


func _prepara_ordini() -> void:
	ordini = {}
	rit_scelte = {}
	costruzioni = {}
	scioglimenti = {}
	sel = -1
	modo = ""
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
	return io >= 0 and not g.finita and not in_replay and storico_idx < 0 and g.deve_ordinare(io) and not ho_consegnato() and not ses.in_calcolo


func _mostra_presente() -> void:
	if in_replay or storico_idx >= 0:
		return
	board.mostra(g.st, g.ritirate)
	_ridisegna_ordini()


func _ridisegna_ordini() -> void:
	if in_replay or storico_idx >= 0:
		return
	var lista := []
	if g.e_movimento() and io >= 0:
		var miei: Dictionary = ses.consegnati.get(io, ordini) if ho_consegnato() else ordini
		for u in miei:
			if g.st.up[int(u)] == io:
				lista.append({"prov": int(u), "o": miei[u], "p": io, "esito": 0})
	board.disegna_ordini(g.st, lista)
	_evidenzia()


func _aggiorna_tutto() -> void:
	var nc := g.st.conta_centri()
	for p in 7:
		var c: Dictionary = chip[p]
		(c["l"] as Label).text = str(nc[p])
		var b: Button = c["b"]
		b.modulate = Color(1, 1, 1, 1) if g.viva(p) else Color(1, 1, 1, 0.3)
		var st := UI.panel_style(UI.PANEL_L if p != io else Color("#5a4326"), UI.OTTONE_L if p == io else Color(UI.OTTONE, 0.5), 3 if p == io else 1, 6, 4)
		if ses.e_umano(p) and ses.consegnati.has(p):
			st.border_color = UI.VERDE
			st.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		b.tooltip_text = "%s - %s (%d centri)" % [DPMap.POTENZE[p], ses.nome(p), nc[p]]
	titolo_fase.text = g.nome_fase() if not g.finita else "Partita conclusa"
	var sotto := ""
	if g.finita:
		sotto = ""
	elif g.e_movimento():
		sotto = "Diplomazia e ordini"
	elif g.e_ritirata():
		sotto = "Le unità scacciate si ritirano"
	else:
		sotto = "Costruzioni e scioglimenti"
	if io >= 0 and not g.finita:
		sotto += " - giocate %s" % DPTesti.CON_ARTICOLO[io]
	sotto_fase.text = sotto
	_aggiorna_pannello()
	_aggiorna_attrezzi()


# ================================================================ pannello a destra

func _svuota(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


func _aggiorna_pannello() -> void:
	for k in schede_btn:
		var b: Button = schede_btn[k]
		b.add_theme_color_override("font_color", Color.WHITE if k == scheda else UI.OTTONE_L)
		var testo: String = {"ordini": "Ordini", "dispacci": "Diplomazia", "storico": "Storico"}[k]
		if k == "dispacci" and io >= 0:
			var nl := ses.corte.da_leggere(io)
			if nl > 0:
				testo += " (%d)" % nl
		b.text = testo
		var st := UI.panel_style(Color("#5a4326") if k == scheda else UI.PANEL_L, UI.OTTONE_L if k == scheda else Color(UI.OTTONE, 0.5), 2, 6, 8)
		b.add_theme_stylebox_override("normal", st)
	_svuota(corpo)
	match scheda:
		"ordini":
			_scheda_ordini()
		"dispacci":
			dispacci_ui.costruisci(corpo)
		"storico":
			_scheda_storico()


func _riga_testo(t: String, col: Color = UI.TEXT, size := 21) -> Label:
	return UI.label(t, size, col, null, true, PANNELLO_W - 60)


func _scheda_ordini() -> void:
	if io < 0 and ses.online:
		corpo.add_child(UI.head("Il tabellone", 24))
		corpo.add_child(_riga_testo("Questo schermo mostra la mappa a tutti. Ognuno tratta e dà gli ordini in segreto dal proprio telefono.", UI.PARCH, 20))
		if g.finita:
			corpo.add_child(UI.button("Risultato finale", _fine, 0, 22))
		else:
			_riga_attesa()
		corpo.add_child(UI.button("Codice QR della stanza", _mostra_qr, 0, 22))
		return
	if io < 0:
		corpo.add_child(_riga_testo("State osservando una partita fra sole IA. Con i pulsanti in alto potete leggere centri e potenze; lo Storico conserva ogni fase.", UI.MUTED))
		return
	if g.finita:
		corpo.add_child(_riga_testo("La partita è conclusa.", UI.MUTED))
		corpo.add_child(UI.button("Risultato finale", _fine, 0, 22))
		return
	var hb := UI.hbox(8)
	hb.add_child(UI.flag_rect(io, 30))
	hb.add_child(UI.head("%s" % DPMap.POTENZE[io], 24))
	corpo.add_child(hb)
	var nc := g.st.n_centri(io)
	corpo.add_child(UI.label("%d centri, %d unità. Ne servono %d per vincere." % [nc, g.st.n_unita(io), DPGame.CENTRI_VITTORIA], 19, UI.MUTED))
	if not g.deve_ordinare(io):
		corpo.add_child(_riga_testo("Nessun ordine da dare in questa fase.", UI.PARCH))
		_riga_attesa()
		return
	if ho_consegnato():
		corpo.add_child(_riga_testo("Ordini consegnati. Restano segreti fino alla risoluzione.", UI.VERDE))
		_riga_attesa()
		if not ses.in_calcolo and not ses.tutti_pronti():
			corpo.add_child(UI.button("Modifica gli ordini", func(): ses.ritira(io), 0, 22))
		return
	var lista := UI.vbox(4)
	corpo.add_child(UI.scroll(lista))
	if g.e_movimento():
		for u in g.st.unita_di(io):
			var o: Array = ordini.get(u, [DPAdj.H, -1, -1])
			var b := UI.button(DPGame.testo_ordine(g.st, u, o, true), _seleziona.bind(u), 0, 20)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.custom_minimum_size = Vector2(PANNELLO_W - 60, 46)
			if u == sel:
				b.add_theme_color_override("font_color", Color.WHITE)
			lista.add_child(b)
		corpo.add_child(UI.primary("Consegna gli ordini", _consegna, 0, 24))
	elif g.e_ritirata():
		lista.add_child(_riga_testo("Scegliete dove si ritira ogni unità scacciata. Due unità che si ritirano nella stessa provincia si sciolgono entrambe.", UI.MUTED, 19))
		for r in g.ritirate_di(io):
			lista.add_child(UI.head("%s %s" % [DPGame.nome_unita(r["t"]), DPMap.nome_loc(r["loc"])], 21, UI.PARCH))
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size = Vector2(PANNELLO_W - 60, 50)
			ob.add_item("Si scioglie", 0)
			var k := 1
			for l in r["opzioni"]:
				ob.add_item("Si ritira in %s" % DPMap.nome_loc(l), k)
				ob.set_item_metadata(k, l)
				if rit_scelte.get(r["prov"], -1) == l:
					ob.select(k)
				k += 1
			ob.item_selected.connect(_scelta_ritirata.bind(ob, int(r["prov"])))
			lista.add_child(ob)
		corpo.add_child(UI.primary("Consegna le ritirate", _consegna, 0, 24))
	else:
		var d := g.saldo(io)
		if d > 0:
			lista.add_child(_riga_testo("Potete costruire %d unità nei vostri centri di casa liberi." % d, UI.PARCH, 20))
			for pr in g.case_libere(io):
				lista.add_child(UI.head(DPMap.nome[pr], 21, UI.PARCH))
				var ob := OptionButton.new()
				ob.focus_mode = Control.FOCUS_NONE
				ob.custom_minimum_size = Vector2(PANNELLO_W - 60, 50)
				ob.add_item("Nessuna costruzione", 0)
				ob.add_item("Armata", 1)
				ob.set_item_metadata(1, [0, pr])
				var k := 2
				if DPMap.tipo[pr] == DPMap.COSTA:
					var cs: PackedInt32Array = DPMap.coste_di[pr]
					if cs.is_empty():
						ob.add_item("Flotta", k)
						ob.set_item_metadata(k, [1, pr])
					else:
						for l in cs:
							ob.add_item("Flotta (%s)" % DPMap.nome_costa(DPMap.costa_nome[l]), k)
							ob.set_item_metadata(k, [1, l])
							k += 1
				if costruzioni.has(pr):
					for i in ob.item_count:
						if ob.get_item_metadata(i) == costruzioni[pr]:
							ob.select(i)
				ob.item_selected.connect(_scelta_costruzione.bind(ob, pr))
				lista.add_child(ob)
			corpo.add_child(UI.primary("Consegna le costruzioni", _consegna, 0, 24))
		else:
			lista.add_child(_riga_testo("Avete più unità che centri: dovete scioglierne %d." % -d, UI.CERA_L, 20))
			for u in g.st.unita_di(io):
				var cb := CheckBox.new()
				cb.focus_mode = Control.FOCUS_NONE
				cb.text = "%s %s" % [DPGame.nome_unita(g.st.ut[u]), DPMap.nome_loc(g.st.ul[u])]
				cb.custom_minimum_size = Vector2(PANNELLO_W - 60, 46)
				cb.button_pressed = scioglimenti.has(u)
				cb.toggled.connect(_scelta_scioglimento.bind(u))
				lista.add_child(cb)
			corpo.add_child(UI.primary("Consegna gli scioglimenti", _consegna, 0, 24))


func _scelta_ritirata(i: int, ob: OptionButton, prov: int) -> void:
	rit_scelte[prov] = int(ob.get_item_metadata(i)) if i > 0 else -1
	_evidenzia()


func _scelta_costruzione(i: int, ob: OptionButton, pr: int) -> void:
	if i == 0:
		costruzioni.erase(pr)
	else:
		costruzioni[pr] = ob.get_item_metadata(i)


func _scelta_scioglimento(on: bool, u: int) -> void:
	if on:
		scioglimenti[u] = true
	else:
		scioglimenti.erase(u)


func _riga_attesa() -> void:
	var manca := []
	for p in 7:
		if ses.e_umano(p) and g.deve_ordinare(p) and not ses.consegnati.has(p):
			manca.append(DPMap.POTENZE_BREVI[p])
	if not manca.is_empty():
		corpo.add_child(_riga_testo("In attesa di: %s." % ", ".join(manca), UI.MUTED, 19))
	elif ses.in_calcolo:
		corpo.add_child(_riga_testo("Le cancellerie stanno deliberando…", UI.MUTED, 19))


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
			var c := []
			for pr in costruzioni:
				if c.size() < d:
					c.append(costruzioni[pr])
			if costruzioni.size() > d:
				_avviso_popup("Potete costruire al massimo %d unità." % d)
				return
			o = {"c": c}
		else:
			if scioglimenti.size() != -d:
				_avviso_popup("Dovete scegliere esattamente %d unità da sciogliere." % -d)
				return
			o = {"s": scioglimenti.keys()}
	sel = -1
	modo = ""
	ses.consegna(io, o)


# ================================================================ storico

func _scheda_storico() -> void:
	if g.storia.is_empty():
		corpo.add_child(_riga_testo("Lo storico si riempirà dopo la prima risoluzione.", UI.MUTED))
		return
	if storico_idx >= 0:
		corpo.add_child(UI.primary("Torna al presente", _torna_presente, 0, 22))
		var voce: Dictionary = g.storia[storico_idx]
		var nav := UI.hbox(6)
		var bp := UI.button("Precedente", func(): _apri_storico(maxi(0, storico_idx - 1)), 0, 20)
		bp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bs := UI.button("Successiva", func(): _apri_storico(mini(g.storia.size() - 1, storico_idx + 1)), 0, 20)
		bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(bp)
		nav.add_child(bs)
		corpo.add_child(nav)
		corpo.add_child(UI.head("%s %d" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]], 23))
		var testo := UI.vbox(2)
		corpo.add_child(UI.scroll(testo))
		_righe_voce(testo, voce)
		return
	var lista := UI.vbox(4)
	corpo.add_child(UI.scroll(lista))
	for i in range(g.storia.size() - 1, -1, -1):
		var voce: Dictionary = g.storia[i]
		var b := UI.button("%s %d" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]], _apri_storico.bind(i), 0, 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(PANNELLO_W - 60, 44)
		lista.add_child(b)


func _torna_presente() -> void:
	storico_idx = -1
	_mostra_presente()
	_aggiorna_tutto()


func _apri_storico(i: int) -> void:
	if in_replay:
		return
	storico_idx = i
	scheda = "storico"
	var voce: Dictionary = g.storia[i]
	var prima := DPState.from_dict(voce["prima"])
	board.mostra(prima)
	board.evidenzia({})
	if voce.has("ordini"):
		var l := []
		for u in voce["ordini"]:
			l.append({"prov": u, "o": voce["ordini"][u], "p": prima.up[u], "esito": voce["esiti"][u]})
		board.disegna_ordini(prima, l)
	else:
		board.pulisci_frecce()
		board.mostra(DPState.from_dict(voce["dopo"]))
	_aggiorna_tutto()


## Le righe di testo di una fase risolta, per potenza.
func _righe_voce(box: VBoxContainer, voce: Dictionary) -> void:
	var prima := DPState.from_dict(voce["prima"])
	var w := PANNELLO_W - 70
	if voce.has("ordini"):
		for p in 7:
			var righe := []
			for u in voce["ordini"]:
				if prima.up[u] == p:
					var s := DPGame.testo_ordine(prima, u, voce["ordini"][u])
					var e := DPGame.testo_esito(int(voce["esiti"][u]), int(voce["ordini"][u][0]))
					righe.append([s, e])
			if righe.is_empty():
				continue
			box.add_child(UI.head(DPMap.POTENZE[p], 20, DPMap.COLORI_TESTO[p]))
			for r in righe:
				var l := UI.label(r[0] + ("  (%s)" % r[1] if r[1] != "" else ""), 19, UI.CERA_L if r[1] != "" else UI.TEXT, null, true, w)
				box.add_child(l)
		for x in voce.get("sloggiate", []):
			box.add_child(UI.label("%s %s è scacciata." % [DPGame.nome_unita(prima.ut[x[0]]), DPMap.nome[x[0]]], 19, UI.OTTONE_L, null, true, w))
		for x in voce.get("distrutte", []):
			box.add_child(UI.label("%s %s (%s) non ha vie di ritirata: è distrutta." % [DPGame.nome_unita(x[2]), DPMap.nome[x[0]], DPMap.POTENZE_BREVI[x[1]]], 19, UI.CERA_L, null, true, w))
	elif voce.has("ritirate"):
		for r in voce["ritirate"]:
			var s := "%s: %s %s " % [DPMap.POTENZE_BREVI[r[1]], DPGame.sigla_unita(r[2]), DPMap.nome_loc(r[3])]
			if r[5] >= 0:
				s += "si ritira in %s." % DPMap.nome_loc(r[5])
			elif r[4] >= 0:
				s += "si scioglie (ritirata contesa)."
			else:
				s += "si scioglie."
			box.add_child(UI.label(s, 19, UI.TEXT, null, true, w))
	else:
		for x in voce.get("costruite", []):
			box.add_child(UI.label("%s costruisce: %s %s." % [DPMap.POTENZE_BREVI[x[0]], DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], 19, UI.TEXT, null, true, w))
		for x in voce.get("sciolte", []):
			box.add_child(UI.label("%s scioglie: %s %s." % [DPMap.POTENZE_BREVI[x[0]], DPGame.nome_unita(x[1]), DPMap.nome_loc(x[2])], 19, UI.TEXT, null, true, w))
		if voce.get("costruite", []).is_empty() and voce.get("sciolte", []).is_empty():
			box.add_child(UI.label("Nessun cambiamento.", 19, UI.MUTED, null, true, w))


# ================================================================ dare gli ordini sulla mappa

func _seleziona(u: int) -> void:
	if not posso_ordinare() or not g.e_movimento():
		return
	sel = u if u != sel else -1
	modo = "muovi" if sel >= 0 else ""
	sost_unita = -1
	conv_armata = -1
	board.seleziona(sel)
	_evidenzia()
	_aggiorna_pannello()
	_aggiorna_attrezzi()


## Province in cui un'armata può sbarcare per convoglio: quelle raggiungibili con una catena di flotte in mare.
func sbarchi(u: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var st := g.st
	if st.ut[u] != 0 or DPMap.tipo[u] != DPMap.COSTA:
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


func _evidenzia() -> void:
	var d := {}
	if in_replay or storico_idx >= 0:
		board.evidenzia(d)
		return
	if posso_ordinare() and g.e_movimento() and sel >= 0:
		var st := g.st
		match modo:
			"muovi":
				for l in DPMap.destinazioni(st.ut[sel], st.ul[sel]):
					d[DPMap.loc_prov[l]] = C_MOSSA
				for x in sbarchi(sel):
					if not d.has(x):
						d[x] = C_MARE
			"sost1":
				for u in _sostenibili():
					d[u] = C_SOST
			"sost2":
				for x in _bersagli_sostegno(sost_unita):
					d[x] = C_SOST
			"conv1":
				for u in DPMap.N_PROV:
					if st.up[u] >= 0 and st.ut[u] == 0 and DPMap.tipo[u] == DPMap.COSTA and not sbarchi(u).is_empty():
						d[u] = C_MARE
			"conv2":
				for x in sbarchi(conv_armata):
					d[x] = C_MARE
	elif posso_ordinare() and g.e_ritirata():
		for r in g.ritirate_di(io):
			for l in r["opzioni"]:
				d[DPMap.loc_prov[l]] = C_MOSSA if rit_scelte.get(r["prov"], -1) != l else C_SOST
	elif posso_ordinare() and g.fase == DPGame.INVERNO and g.saldo(io) > 0:
		for pr in g.case_libere(io):
			d[pr] = C_MOSSA
	board.evidenzia(d)


## Le unità (di chiunque) che l'unità selezionata può sostenere.
func _sostenibili() -> Array:
	var o := []
	for u in DPMap.N_PROV:
		if g.st.up[u] >= 0 and u != sel and not _bersagli_sostegno(u).is_empty():
			o.append(u)
	return o


## Dove l'unità selezionata può sostenere l'unità u: la sua provincia (ferma) o una sua destinazione.
func _bersagli_sostegno(u: int) -> Array:
	var st := g.st
	var o := []
	if u < 0 or st.up[u] < 0:
		return o
	if DPMap.tocca(st.ut[sel], st.ul[sel], u):
		o.append(u)
	var dest := {}
	for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
		dest[DPMap.loc_prov[l]] = true
	for x in sbarchi(u):
		dest[x] = true
	for x in dest:
		if x != sel and DPMap.tocca(st.ut[sel], st.ul[sel], x):
			o.append(x)
	return o


func _su_tocco(prov: int, su_unita: bool) -> void:
	_chiudi_popup()
	if not posso_ordinare():
		return
	var st := g.st
	if not g.e_movimento():
		return
	if sel < 0:
		if st.up[prov] == io:
			_seleziona(prov)
		return
	match modo:
		"muovi":
			if prov == sel:
				_seleziona(sel)
				return
			var dest := DPMap.approdi(st.ul[sel], prov) if st.ut[sel] == 1 else PackedInt32Array()
			var terra := st.ut[sel] == 0 and (DPMap.adj_a[sel] as PackedInt32Array).has(prov)
			var mare := st.ut[sel] == 0 and sbarchi(sel).has(prov)
			if st.ut[sel] == 1 and not dest.is_empty():
				if dest.size() == 1:
					_ordina(sel, [DPAdj.M, dest[0], 0])
				else:
					var scelte := []
					for l in dest:
						scelte.append([DPTesti.maiuscola(DPMap.nome_costa(DPMap.costa_nome[l])), [DPAdj.M, l, 0]])
					_scegli("Su quale costa di %s?" % DPMap.nome[prov], scelte)
			elif terra and mare:
				_scegli("Come raggiunge %s?" % DPMap.nome[prov], [["Via terra", [DPAdj.M, prov, 0]], ["Via convoglio", [DPAdj.M, prov, 1]]])
			elif terra:
				_ordina(sel, [DPAdj.M, prov, 0])
			elif mare:
				_ordina(sel, [DPAdj.M, prov, 1])
			elif st.up[prov] == io:
				_seleziona(prov)
		"sost1":
			if st.up[prov] >= 0 and prov != sel and not _bersagli_sostegno(prov).is_empty():
				sost_unita = prov
				modo = "sost2"
				_evidenzia()
				_aggiorna_attrezzi()
			elif st.up[prov] == io and prov != sel:
				_seleziona(prov)
		"sost2":
			if _bersagli_sostegno(sost_unita).has(prov):
				_ordina(sel, [DPAdj.S, sost_unita, prov])
			elif st.up[prov] >= 0 and prov != sel and not _bersagli_sostegno(prov).is_empty():
				sost_unita = prov
				_evidenzia()
				_aggiorna_attrezzi()
		"conv1":
			if st.up[prov] >= 0 and st.ut[prov] == 0 and not sbarchi(prov).is_empty():
				conv_armata = prov
				modo = "conv2"
				_evidenzia()
				_aggiorna_attrezzi()
		"conv2":
			if sbarchi(conv_armata).has(prov):
				_ordina(sel, [DPAdj.C, conv_armata, prov])


func _ordina(u: int, o: Array) -> void:
	ordini[u] = o
	_chiudi_popup()
	sel = -1
	modo = ""
	board.seleziona(-1)
	_ridisegna_ordini()
	_aggiorna_pannello()
	_aggiorna_attrezzi()



func _aggiorna_attrezzi() -> void:
	_svuota(attrezzi_box)
	attrezzi.offset_top = -130 if (sel >= 0 and posso_ordinare() and g.e_movimento()) else -66
	attrezzi_box.visible = sel >= 0
	if not posso_ordinare() or not g.e_movimento():
		attrezzi.visible = posso_ordinare()
		if posso_ordinare() and g.e_ritirata():
			suggerimento.text = "Ritirate: scegliete nel pannello a destra dove va ogni unità scacciata."
		elif posso_ordinare():
			suggerimento.text = "Inverno: scegliete nel pannello a destra costruzioni o scioglimenti."
		return
	attrezzi.visible = true
	if sel < 0:
		suggerimento.text = "Toccate una vostra unità per darle un ordine. Per alleanze e patti: scheda Diplomazia, o la bandiera di una potenza."
		return
	var st := g.st
	var nome := "%s %s" % [DPGame.nome_unita(st.ut[sel]), DPMap.nome_loc(st.ul[sel])]
	match modo:
		"muovi":
			suggerimento.text = "%s: toccate la destinazione (giallo), oppure scegliete un altro ordine." % nome
		"sost1":
			suggerimento.text = "%s sostiene: toccate l'unità da sostenere (verde)." % nome
		"sost2":
			suggerimento.text = "%s sostiene %s: toccate dove (la sua provincia = resta ferma)." % [nome, DPTesti.unita(st, sost_unita)]
		"conv1":
			suggerimento.text = "%s convoglia: toccate l'armata da trasportare (azzurro)." % nome
		"conv2":
			suggerimento.text = "%s convoglia %s: toccate la provincia di sbarco." % [nome, DPTesti.unita(st, conv_armata)]
	var defs := [["Muovi", "muovi"], ["Sostieni", "sost1"]]
	if st.ut[sel] == 1 and DPMap.tipo[sel] == DPMap.MARE:
		defs.append(["Convoglia", "conv1"])
	for d in defs:
		var b := UI.button(d[0], _modo.bind(d[1]), 150, 22)
		if modo.begins_with(str(d[1]).substr(0, 4)):
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_stylebox_override("normal", UI.panel_style(Color("#5a4326"), UI.OTTONE_L, 2, 6, 10))
		attrezzi_box.add_child(b)
	attrezzi_box.add_child(UI.button("Ferma", func(): _ordina(sel, [DPAdj.H, -1, -1]), 130, 22))
	attrezzi_box.add_child(UI.button("Annulla", func(): _seleziona(sel), 130, 22))


func _modo(m: String) -> void:
	modo = m
	sost_unita = -1
	conv_armata = -1
	_evidenzia()
	_aggiorna_attrezzi()


# ================================================================ finestrelle

func _chiudi_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _finestra(larghezza := 620.0) -> VBoxContainer:
	_chiudi_popup()
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.5)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strato.add_child(velo)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.add_child(c)
	var p := UI.panel(UI.dark_style(10, 0.98))
	p.custom_minimum_size.x = larghezza
	c.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	_popup = velo
	return v


func _scegli(domanda: String, scelte: Array) -> void:
	var v := _finestra(520)
	v.add_child(UI.head(domanda, 26))
	for s in scelte:
		v.add_child(UI.button(s[0], _ordina.bind(sel, s[1]), 0, 24))
	v.add_child(UI.button("Annulla", _chiudi_popup, 0, 22))


func _avviso_popup(testo: String) -> void:
	var v := _finestra(560)
	v.add_child(UI.label(testo, 24, UI.PARCH, null, true, 500))
	v.add_child(UI.primary("Va bene", _chiudi_popup, 0, 24))


func _passa_dispositivo() -> void:
	var v := _finestra(640)
	var hb := UI.hbox(14)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(UI.flag_rect(io, 60))
	hb.add_child(UI.head(DPMap.POTENZE[io], 36))
	v.add_child(hb)
	v.add_child(UI.label("Passate il dispositivo a chi guida %s. Gli ordini degli altri restano segreti." % DPTesti.CON_ARTICOLO[io], 24, UI.PARCH, null, true, 560))
	v.add_child(UI.primary("Eccomi", _chiudi_popup, 0, 26))
	# la mappa non mostra gli ordini di nessuno finché non si conferma
	(_popup as ColorRect).color = Color(0.03, 0.05, 0.04, 0.97)


func _menu() -> void:
	var v := _finestra(560)
	v.add_child(UI.head("Diplomacy", 30))
	if not ses.online and not g.finita:
		v.add_child(UI.button("Salva la partita in rete", _salva_rete, 0, 24))
	if io >= 0 and not g.finita:
		v.add_child(UI.button("Proponi il pareggio", _menu_pareggio, 0, 24))
	v.add_child(UI.button("Mappa: %s" % ("tabellone originale" if DPMap.reale else "ridisegnata in italiano"), _menu_mappa, 0, 22))
	v.add_child(UI.button("Pedine: %s" % ("classiche (cannone e corazzata)" if board.classiche else "del modulo (carro e nave)"), _menu_pedine, 0, 22))
	v.add_child(UI.button("Animazioni: %s" % ("veloci" if board.velocita > 1.5 else "normali"), _menu_velocita, 0, 22))
	if ses.online and ses.ruolo == "host":
		for p in 7:
			if ses.e_umano(p) and p != ses.posto and g.viva(p):
				v.add_child(UI.button("Affida %s all'IA (giocatore assente)" % DPTesti.CON_ARTICOLO[p], _menu_affida.bind(p), 0, 21))
	if ses.online:
		v.add_child(UI.button("Stanza %s: codice QR per i telefoni" % ses.codice, _mostra_qr, 0, 22))
	v.add_child(UI.button("Regole e consigli", func(): _regole(), 0, 24))
	v.add_child(UI.button("Torna al menu principale", func(): main.show_menu(), 0, 24))
	v.add_child(UI.primary("Riprendi", _chiudi_popup, 0, 24))


## Il codice QR della stanza: chi lo inquadra con il telefono rientra (o entra) nella partita.
func _mostra_qr() -> void:
	var v := _finestra(520)
	v.add_child(UI.head("Stanza %s" % ses.codice, 34))
	var qr := TextureRect.new()
	qr.texture = DPQr.texture(main.indirizzo_stanza(ses.codice), 8)
	qr.custom_minimum_size = Vector2(380, 380)
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(qr)
	v.add_child(UI.label("Inquadratelo con il telefono: si apre la pagina con diplomazia e ordini, senza mappa. Chi aveva già un posto lo ritrova.", 21, UI.PARCH, null, true, 480))
	v.add_child(UI.primary("Chiudi", _chiudi_popup, 0, 24))


func _menu_pareggio() -> void:
	_chiudi_popup()
	ses.proponi_pareggio(io)


func _menu_pedine() -> void:
	board.classiche = not board.classiche
	ses.cfg["classiche"] = board.classiche
	board.mostra(board.st, g.ritirate if storico_idx < 0 else [])
	_ridisegna_ordini()
	_menu()


## Cambia carta: il tabellone originale o la mappa ridisegnata. La vista si ricostruisce.
func _menu_mappa() -> void:
	DPMap.salva_preferenza(not DPMap.reale)
	main.start_game(ses)


func _menu_velocita() -> void:
	board.velocita = 1.0 if board.velocita > 1.5 else 2.5
	_menu()


func _menu_affida(p: int) -> void:
	ses.affida_all_ia(p)
	_chiudi_popup()


func _voto(p: int, si: bool) -> void:
	_chiudi_popup()
	ses.vota_pareggio(p, si)


func _regole() -> void:
	_chiudi_popup()
	var velo := ColorRect.new()
	velo.color = Color(0.03, 0.05, 0.04, 0.96)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strato.add_child(velo)
	_popup = velo
	var r = preload("res://scripts/ui/rules_view.gd").new()
	r.chiudi = _chiudi_popup
	velo.add_child(r)


func _salva_rete() -> void:
	var v := _finestra(600)
	v.add_child(UI.label("Salvataggio in corso…", 24, UI.PARCH, null, true, 540))
	var c := await ses.salva_in_rete(main.get_net())
	if not is_inside_tree():
		return
	v = _finestra(600)
	if c == "":
		v.add_child(UI.label("Non sono riuscito a salvare in rete (%s). La partita resta comunque salvata su questo dispositivo." % main.get_net().last_error, 23, UI.CERA_L, null, true, 540))
	else:
		v.add_child(UI.label("Partita salvata. Per riprenderla da un altro dispositivo scegliete «Carica una partita» e scrivete questo codice:", 23, UI.PARCH, null, true, 540))
		var l := UI.head(c, 56)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	v.add_child(UI.primary("Va bene", _chiudi_popup, 0, 24))


func _su_avviso(t: String) -> void:
	stato_lbl.text = t
	if t != "" and not t.ends_with("…"):
		var mio := t
		await get_tree().create_timer(5.0).timeout
		if is_inside_tree() and stato_lbl.text == mio:
			stato_lbl.text = ""


func _su_posta(m: Dictionary) -> void:
	if m["a"] == io and scheda != "dispacci":
		_su_avviso("Nuovo dispaccio %s." % DPTesti.DA_CANC[m["da"]])
	if not in_replay:
		_aggiorna_pannello()


func _su_pareggio(da: int) -> void:
	# le persone a questo dispositivo votano una dopo l'altra
	for p in ses.locali:
		if p != da and g.viva(p) and not ses.corte.voti.has(p):
			var v := _finestra(620)
			v.add_child(UI.head("Proposta di pareggio", 28))
			v.add_child(UI.label("%s propone di chiudere la partita con un pareggio fra le potenze superstiti. %s, accettate?" % [DPTesti.maiuscola(DPTesti.CON_ARTICOLO[da]), DPMap.POTENZE[p]], 23, UI.PARCH, null, true, 560))
			var hb := UI.hbox(10)
			var si := UI.primary("Accetto", _voto.bind(p, true), 0, 24)
			si.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var no := UI.button("Rifiuto", _voto.bind(p, false), 0, 24)
			no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(si)
			hb.add_child(no)
			v.add_child(hb)
			return


# ================================================================ risoluzione

func _su_risolta(voce: Dictionary) -> void:
	coda_voci.append(voce)
	if not in_replay:
		_riproduci()


func _riproduci() -> void:
	in_replay = true
	_chiudi_popup()
	attrezzi.visible = false
	board.seleziona(-1)
	board.evidenzia({})
	while not coda_voci.is_empty():
		var voce: Dictionary = coda_voci.pop_front()
		titolo_fase.text = "%s %d" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]]
		sotto_fase.text = "Risoluzione"
		if voce.has("ordini"):
			await board.anima_movimenti(voce)
			if not is_inside_tree():
				return
			await _riepilogo(voce)
		else:
			board.pulisci_frecce()
			board.mostra(DPState.from_dict(voce["dopo"]))
			await _riepilogo(voce, 2.6)
		if not is_inside_tree():
			return
	in_replay = false
	_chiave_turno = ""
	ses.prosegui()


## Mostra il riepilogo della fase nel pannello e aspetta «Continua» (o qualche secondo se nessuno guarda).
func _riepilogo(voce: Dictionary, auto := 0.0) -> void:
	_svuota(corpo)
	corpo.add_child(UI.head("%s %d: risultati" % [DPGame.NOMI_FASE[voce["fase"]], voce["anno"]], 23))
	var testo := UI.vbox(2)
	corpo.add_child(UI.scroll(testo))
	_righe_voce(testo, voce)
	_attesa_continua = true
	var b := UI.primary("Continua", func(): _attesa_continua = false, 0, 24)
	corpo.add_child(b)
	var t := 0.0
	var limite := auto if auto > 0.0 else (2.5 if ses.locali.is_empty() else 0.0)
	if ses.online and ses.locali.is_empty() and limite > 0.0:
		limite = maxf(limite, 7.0)       # tabellone: il tempo di leggere i risultati tutti insieme
	if config.get("auto", false):
		limite = 0.3
	while _attesa_continua and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
		if limite > 0.0 and t >= limite:
			_attesa_continua = false


func _fine() -> void:
	if _popup != null and is_instance_valid(_popup) and _popup.has_meta("fine"):
		return
	_chiudi_popup()
	var f = preload("res://scripts/ui/fine_ui.gd").new()
	f.vista = self
	f.set_meta("fine", true)
	strato.add_child(f)
	_popup = f

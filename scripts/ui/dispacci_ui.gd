extends RefCounted
## La scheda «Diplomazia»: il quadro dei rapporti con le altre potenze, le conversazioni come telegrammi
## su carta, le risposte alle proposte e la scrittura di un nuovo dispaccio (alleanze, patti, sostegni…).

const TIPI := [
	["alleanza", "Alleanza contro una potenza"],
	["pace", "Patto di non aggressione"],
	["dmz", "Zona sgombra (nessuno ci entra)"],
	["chiedi_sost", "Chiedere un sostegno"],
	["offri_sost", "Offrire un sostegno"],
	["chiedi_mossa", "Chiedere un ordine"],
	["info", "Informazione riservata"],
	["libero", "Messaggio libero"],
	["disdetta", "Disdire gli accordi presi"],
]

var vista
var tipo := 0
var par := {}


func costruisci(corpo: VBoxContainer) -> void:
	var ses: DPSession = vista.ses
	var g: DPGame = vista.g
	var io: int = vista.io
	var w: float = vista.PANNELLO_W - 60
	if io < 0:
		corpo.add_child(UI.label("I dispacci si scambiano fra le potenze in gioco.", 21, UI.MUTED, null, true, w))
		return
	if vista.con_chi == io:
		vista.con_chi = -1
	var chi: int = vista.con_chi
	if chi < 0:
		_quadro(corpo, w)
		return
	var torna := UI.button("Quadro diplomatico", vista._apri_conversazione.bind(-1), 0, 20)
	torna.custom_minimum_size.x = 200
	corpo.add_child(torna)
	var intest := "%s (%s)" % [DPTesti.maiuscola(DPTesti.CANCELLERIE[chi]), DPMap.POTENZE_BREVI[chi]]
	corpo.add_child(UI.head(intest, 22))
	var chi_e := "Guidata da %s." % ses.nome(chi) if ses.e_umano(chi) else "Guidata dall'IA (%s)." % DPCorte.NOMI_LIVELLO[ses.corte.livello]
	corpo.add_child(UI.label(chi_e + " " + _accordi(io, chi), 18, UI.MUTED, UI.font_ital, true, w))
	var lista := UI.vbox(8)
	var sc := UI.scroll(lista)
	corpo.add_child(sc)
	var conv := []
	for m in ses.corte.posta_di(io):
		if (m["da"] == chi and m["a"] == io) or (m["da"] == io and m["a"] == chi):
			conv.append(m)
	if conv.is_empty():
		lista.add_child(UI.label("Nessun dispaccio scambiato con %s." % DPTesti.CON_ARTICOLO[chi], 20, UI.MUTED, null, true, w))
	for m in conv.slice(maxi(0, conv.size() - 40)):
		lista.add_child(_foglio(m, io, w))
		if m["a"] == io:
			m["letto"] = true
	_in_fondo.call_deferred(sc)
	if g.viva(chi) and not g.finita:
		# le proposte più usate a portata di dito; tutto il resto in «Altro dispaccio»
		var sost: bool = g.e_movimento() and g.st.n_unita(chi) > 0 and g.st.n_unita(io) > 0
		var gr := GridContainer.new()
		gr.columns = 2
		gr.add_theme_constant_override("h_separation", 6)
		gr.add_theme_constant_override("v_separation", 6)
		corpo.add_child(gr)
		for x in [["Proponi alleanza", 0, true], ["Proponi pace", 1, true], ["Chiedi sostegno", 3, sost], ["Altro dispaccio", -1, true]]:
			var b: Button = UI.primary(x[0], componi_tipo.bind(x[1]), 0, 20) if x[1] >= 0 else UI.button(x[0], componi, 0, 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(180, 50)
			b.disabled = not x[2]
			gr.add_child(b)


## Il quadro diplomatico: una riga per potenza con accordi in vigore, ultimo scambio e posta da leggere.
func _quadro(corpo: VBoxContainer, w: float) -> void:
	var ses: DPSession = vista.ses
	var g: DPGame = vista.g
	var io: int = vista.io
	corpo.add_child(UI.head("Quadro diplomatico", 23))
	corpo.add_child(UI.label("Toccate una potenza per trattare: alleanze, patti, sostegni. Nessuno è obbligato a mantenere la parola.", 17, UI.MUTED, UI.font_ital, true, w))
	var lista := UI.vbox(6)
	var sc := UI.scroll(lista)
	corpo.add_child(sc)
	for p in 7:
		if p == io:
			continue
		var nl := 0
		var scambi := 0
		for m in ses.corte.posta_di(io):
			if m["da"] == p and m["a"] == io:
				scambi += 1
				if not m.get("letto", false):
					nl += 1
			elif m["da"] == io and m["a"] == p:
				scambi += 1
		var acc := _elenco_accordi(io, p)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(w, 86)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bordo: Color = UI.CERA_L if nl > 0 else (Color("#5fae5f") if not acc.is_empty() else Color(UI.OTTONE, 0.5))
		var stile := UI.panel_style(UI.PANEL_L, bordo, 3 if (nl > 0 or not acc.is_empty()) else 1, 6, 6)
		b.add_theme_stylebox_override("normal", stile)
		b.add_theme_stylebox_override("hover", stile)
		b.add_theme_stylebox_override("pressed", stile)
		var hb := UI.hbox(10)
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8
		hb.offset_right = -8
		hb.offset_top = 6
		hb.offset_bottom = -6
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fr := UI.flag_rect(p, 34)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(fr)
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var titolo := "%s - %d centri" % [DPMap.POTENZE[p], g.st.n_centri(p)]
		var tl := UI.head(titolo, 19, Color.WHITE)
		tl.clip_text = true
		tl.custom_minimum_size.x = w - 80
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tl)
		var stato := ""
		var col: Color = UI.MUTED
		if not g.viva(p):
			stato = "Eliminata."
		elif not acc.is_empty():
			stato = DPCorte._maiuscola("; ".join(acc)) + "."
			col = Color("#8fd08f")
		elif scambi == 0:
			stato = "Nessun contatto finora."
		else:
			stato = "Nessun accordo in vigore."
		if nl > 0:
			stato = "%s da leggere. %s" % ["1 dispaccio" if nl == 1 else "%d dispacci" % nl, stato]
			col = UI.CERA_L if acc.is_empty() else col
		var sl := UI.label(stato, 16, col, null, true, w - 80)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.max_lines_visible = 2
		v.add_child(sl)
		hb.add_child(v)
		b.add_child(hb)
		b.modulate = Color(1, 1, 1, 1) if g.viva(p) else Color(1, 1, 1, 0.4)
		b.pressed.connect(vista._apri_conversazione.bind(p))
		lista.add_child(b)


func _in_fondo(sc: ScrollContainer) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = 1000000


## Gli accordi accettati fra due potenze e ancora in vigore: una disdetta cancella quelli presi prima.
func _elenco_accordi(io: int, chi: int) -> Array:
	var ses: DPSession = vista.ses
	var visti := {}
	for m in ses.corte.posta_di(io):
		if not ((m["da"] == chi and m["a"] == io) or (m["da"] == io and m["a"] == chi)):
			continue
		if m["tipo"] == "nota" and m["d"].get("k", "") == "disdetta":
			visti.clear()
			continue
		if m.get("esito", "") != "si":
			continue
		match m["tipo"]:
			"alleanza":
				if vista.g.viva(int(m["d"]["contro"])):
					visti["alleanza contro %s (%d)" % [DPTesti.CON_ARTICOLO[int(m["d"]["contro"])], m["anno"]]] = true
			"pace":
				visti["non aggressione (%d)" % m["anno"]] = true
			"dmz":
				if vista.g.anno - int(m["anno"]) < 2:
					visti["zona sgombra: %s" % DPTesti.province(m["d"]["prov"])] = true
	return visti.keys()


func _accordi(io: int, chi: int) -> String:
	var acc := _elenco_accordi(io, chi)
	if acc.is_empty():
		return "Nessun accordo in vigore."
	return "Accordi: " + "; ".join(acc) + "."


func _foglio(m: Dictionary, io: int, w: float) -> Control:
	var mio: bool = m["da"] == io
	var p := UI.panel(UI.parch_style())
	var v := UI.vbox(4)
	p.add_child(v)
	var da: String = "Da voi" if mio else str(DPTesti.DA_CANC[m["da"]])
	var data := "%s %d" % [DPGame.NOMI_FASE[m["fase"]], m["anno"]]
	var t := UI.label("%s - %s" % [da.to_upper(), data], 15, UI.INK_L, UI.font_head)
	t.clip_text = true
	t.custom_minimum_size.x = w - 40
	v.add_child(t)
	var corpo_t := UI.label(str(m["testo"]), 19, UI.INK, UI.font_tele, true, w - 40)
	v.add_child(corpo_t)
	if DPTesti.e_proposta(m["tipo"]):
		var es: String = m.get("esito", "")
		var attuale: bool = m["anno"] == vista.g.anno and m["fase"] == vista.g.fase
		if es == "si":
			v.add_child(UI.label("ACCETTATO", 16, Color("#2c6a2c"), UI.font_head))
		elif es == "no":
			v.add_child(UI.label("RIFIUTATO", 16, UI.CERA, UI.font_head))
		elif not mio and (attuale or m["tipo"] in ["alleanza", "pace", "dmz"]) and not vista.g.finita:
			var hb := UI.hbox(8)
			var si := UI.primary("Accetta", rispondi.bind(m, true), 0, 20)
			si.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			si.custom_minimum_size.x = 120
			var no := UI.button("Rifiuta", rispondi.bind(m, false), 0, 20)
			no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			no.custom_minimum_size.x = 120
			hb.add_child(si)
			hb.add_child(no)
			v.add_child(hb)
		elif mio:
			v.add_child(UI.label("IN ATTESA DI RISPOSTA", 15, UI.INK_L, UI.font_head))
		else:
			v.add_child(UI.label("SCADUTO", 15, UI.INK_L, UI.font_head))
	return p


func rispondi(m: Dictionary, si: bool) -> void:
	vista.ses.invia({"da": vista.io, "a": m["da"], "tipo": "risposta", "d": {"si": si}, "rif": m["id"], "v": randi() % 12})
	if m["tipo"] == "pareggio" and si:
		# accettare la proposta apre il voto formale fra tutte le potenze
		vista.ses.proponi_pareggio(vista.io)
	vista._aggiorna_pannello()


# ================================================================ nuovo dispaccio

func componi() -> void:
	par = {}
	_finestra_componi()


## Apre la scrittura già sul tipo di proposta scelto (0 alleanza, 1 pace, 3 chiedere un sostegno…).
func componi_tipo(i: int) -> void:
	par = {"tipo": i}
	_finestra_componi()


## Sceglie come predefinita la prima coppia di unità per cui il sostegno è possibile.
func _coppia_valida(sostenitrici: Array, sostenute: Array) -> void:
	if par.has("u") and par.has("a") and not _dove(int(par["a"]), int(par["u"])).is_empty():
		return
	if par.has("u") and par.has("a") and par.get("_toccato", false):
		return
	for u in sostenitrici:
		for a in sostenute:
			if not _dove(a, u).is_empty():
				par["u"] = u
				par["a"] = a
				par.erase("b")
				return


func _unita_di(p: int) -> Array:
	return Array(vista.g.st.unita_di(p))


func _opzione(testo: String, voci: Array, chiave: String, v: VBoxContainer) -> void:
	# voci: [[etichetta, valore], …]
	v.add_child(UI.label(testo, 20, UI.MUTED))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(560, 50)
	for i in voci.size():
		ob.add_item(str(voci[i][0]), i)
		ob.set_item_metadata(i, voci[i][1])
		if par.has(chiave) and par[chiave] == voci[i][1]:
			ob.select(i)
	if not voci.is_empty() and not par.has(chiave):
		par[chiave] = voci[0][1]
	elif not voci.is_empty():
		var ok := false
		for x in voci:
			if x[1] == par[chiave]:
				ok = true
		if not ok:
			par[chiave] = voci[0][1]
			ob.select(0)
	ob.item_selected.connect(_cambia.bind(ob, chiave))
	v.add_child(ob)


func _cambia(i: int, ob: OptionButton, chiave: String) -> void:
	par[chiave] = ob.get_item_metadata(i)
	if chiave == "tipo":
		par = {"tipo": par["tipo"]}
	elif chiave in ["u", "a"]:
		par["_toccato"] = true
		par.erase("b")
	_finestra_componi()


func _finestra_componi() -> void:
	var g: DPGame = vista.g
	var st := g.st
	var io: int = vista.io
	var chi: int = vista.con_chi
	var v: VBoxContainer = vista._finestra(640)
	v.add_child(UI.head("Dispaccio per %s" % DPTesti.CANCELLERIE[chi], 26))
	var tipi := []
	for i in TIPI.size():
		var k: String = TIPI[i][0]
		if k in ["chiedi_sost", "offri_sost", "chiedi_mossa"] and (not g.e_movimento() or st.n_unita(chi) == 0 or st.n_unita(io) == 0):
			continue
		if k == "disdetta" and _elenco_accordi(io, chi).is_empty():
			continue
		tipi.append([TIPI[i][1], i])
	_opzione("Che cosa proponete", tipi, "tipo", v)
	tipo = int(par["tipo"])
	var k: String = TIPI[tipo][0]
	var d := {}
	var valido := true
	match k:
		"alleanza":
			var pot := []
			for p in 7:
				if p != io and p != chi and g.viva(p):
					pot.append([DPMap.POTENZE[p], p])
			_opzione("Contro chi", pot, "contro", v)
			valido = not pot.is_empty()
			d = {"contro": par.get("contro", -1)}
		"dmz":
			var prov := []
			var nomi := []
			for i in DPMap.N_PROV:
				if DPMap.tipo[i] != DPMap.MARE or true:
					nomi.append([DPMap.nome[i], i])
			nomi.sort()
			_opzione("Quale provincia resta sgombra", nomi, "p1", v)
			var altre := [["(nessun'altra)", -1]]
			altre.append_array(nomi)
			_opzione("E anche", altre, "p2", v)
			prov.append(int(par["p1"]))
			if int(par.get("p2", -1)) >= 0 and int(par["p2"]) != int(par["p1"]):
				prov.append(int(par["p2"]))
			d = {"prov": prov}
		"chiedi_sost":
			_coppia_valida(_unita_di(chi), _unita_di(io))
			var loro := []
			for u in _unita_di(chi):
				loro.append([DPTesti.unita(st, u), u])
			_opzione("La loro unità che deve sostenere", loro, "u", v)
			var mie := []
			for u in _unita_di(io):
				mie.append([DPTesti.unita(st, u), u])
			_opzione("La vostra unità da sostenere", mie, "a", v)
			var dove := _dove(int(par["a"]), int(par["u"]))
			_opzione("Dove", dove, "b", v)
			valido = not dove.is_empty()
			d = {"u": par["u"], "a": par["a"], "b": par.get("b", par["a"])}
		"offri_sost":
			_coppia_valida(_unita_di(io), _unita_di(chi))
			var mie := []
			for u in _unita_di(io):
				mie.append([DPTesti.unita(st, u), u])
			_opzione("La vostra unità che sosterrà", mie, "u", v)
			var loro := []
			for u in _unita_di(chi):
				loro.append([DPTesti.unita(st, u), u])
			_opzione("La loro unità da sostenere", loro, "a", v)
			var dove := _dove(int(par["a"]), int(par["u"]))
			_opzione("Dove", dove, "b", v)
			valido = not dove.is_empty()
			d = {"u": par["u"], "a": par["a"], "b": par.get("b", par["a"])}
		"chiedi_mossa":
			var loro := []
			for u in _unita_di(chi):
				loro.append([DPTesti.unita(st, u), u])
			_opzione("La loro unità", loro, "u", v)
			var u := int(par["u"])
			var ord := [["resta ferma", [DPAdj.H, -1, -1]]]
			for l in DPMap.destinazioni(st.ut[u], st.ul[u]):
				ord.append(["muove in %s" % DPMap.nome_loc(l), [DPAdj.M, l, 0]])
			_opzione("Che cosa deve fare", ord, "o", v)
			d = {"u": u, "o": par["o"]}
		"info":
			var pot := []
			for p in 7:
				if p != io and p != chi and g.viva(p):
					pot.append([DPMap.POTENZE[p], p])
			_opzione("Chi trama contro di loro", pot, "su", v)
			valido = not pot.is_empty()
			d = {"su": par.get("su", -1)}
		"libero":
			v.add_child(UI.label("Il vostro messaggio (le IA rispondono solo alle proposte precise)", 20, UI.MUTED, null, true, 560))
			var le := LineEdit.new()
			le.custom_minimum_size = Vector2(560, 54)
			le.max_length = 240
			le.text = str(par.get("testo", ""))
			le.text_changed.connect(func(t: String): par["testo"] = t)
			v.add_child(le)
			d = {"testo": ""}
	var m := {"da": io, "a": chi, "tipo": "nota" if k == "disdetta" else k, "d": d, "v": int(par.get("v", 0))}
	if k != "libero" and valido:
		var foglio := UI.panel(UI.parch_style())
		foglio.add_child(UI.label(DPCorte._maiuscola(DPTesti.componi(m, st)), 20, UI.INK, UI.font_tele, true, 540))
		v.add_child(foglio)
	elif not valido:
		v.add_child(UI.label("Non ci sono scelte possibili per questa proposta.", 20, UI.CERA_L, null, true, 560))
	var hb := UI.hbox(10)
	var ok := UI.primary("Spedisci", _spedisci.bind(m), 0, 24)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.disabled = not valido
	var no := UI.button("Annulla", vista._chiudi_popup, 0, 24)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ok)
	hb.add_child(no)
	v.add_child(hb)


## Dove l'unità a può andare (o restare) con il sostegno dell'unità u: [[etichetta, provincia], …].
func _dove(a: int, u: int) -> Array:
	var st: DPState = vista.g.st
	var o := []
	if a == u or st.up[a] < 0 or st.up[u] < 0:
		return o
	if DPMap.tocca(st.ut[u], st.ul[u], a):
		o.append(["resta ferma in %s" % DPMap.nome[a], a])
	var visti := {}
	for l in DPMap.destinazioni(st.ut[a], st.ul[a]):
		var p := DPMap.loc_prov[l]
		if p != u and not visti.has(p) and DPMap.tocca(st.ut[u], st.ul[u], p):
			visti[p] = true
			o.append(["muove in %s" % DPMap.nome[p], p])
	return o


func _spedisci(m: Dictionary) -> void:
	if m["tipo"] == "libero":
		var t := str(par.get("testo", "")).strip_edges()
		if t == "":
			return
		m["d"] = {"testo": t}
	m["v"] = randi() % 12
	vista._chiudi_popup()
	vista.ses.invia(m)
	vista._aggiorna_pannello()

extends ColorRect
## La schermata di fine partita: vincitore o pareggio, classifica, andamento dei centri anno per anno
## e gli «archivi segreti» con i diari delle IA e i dispacci scambiati fra le potenze.

var vista
var corpo: VBoxContainer


func _ready() -> void:
	color = Color(0.03, 0.05, 0.04, 0.93)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := UI.panel(UI.dark_style(10, 0.98))
	p.custom_minimum_size = Vector2(1180, 860)
	c.add_child(p)
	corpo = UI.vbox(10)
	p.add_child(corpo)
	_riepilogo()


func _svuota() -> void:
	for ch in corpo.get_children():
		corpo.remove_child(ch)
		ch.queue_free()


func _riepilogo() -> void:
	_svuota()
	var g: DPGame = vista.g
	var ses: DPSession = vista.ses
	var nc := g.st.conta_centri()
	var t := "Vittoria" if g.vincitore >= 0 else "Pareggio"
	var tl := UI.title(t, 96)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	corpo.add_child(tl)
	var sotto := ""
	if g.vincitore >= 0:
		sotto = "%s domina l'Europa con %d centri (%d)." % [DPTesti.maiuscola(DPTesti.CON_ARTICOLO[g.vincitore]), nc[g.vincitore], g.anno]
	else:
		var n := []
		for p in g.pari:
			n.append(DPMap.POTENZE_BREVI[p])
		sotto = "Nessuno ha conquistato l'Europa. Dividono il pareggio: %s." % ", ".join(n)
	var sl := UI.label(sotto, 26, UI.PARCH, UI.font_ital)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	corpo.add_child(sl)
	var hb := UI.hbox(20)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corpo.add_child(hb)
	# classifica
	var cl := UI.vbox(6)
	cl.custom_minimum_size.x = 520
	hb.add_child(cl)
	var ordine := [0, 1, 2, 3, 4, 5, 6]
	ordine.sort_custom(func(a, b): return nc[a] > nc[b])
	for p in ordine:
		var r := UI.hbox(10)
		r.add_child(UI.flag_rect(p, 30))
		var n := UI.head(DPMap.POTENZE[p], 22, DPMap.COLORI_TESTO[p])
		n.custom_minimum_size.x = 210
		r.add_child(n)
		var c := UI.head("%d" % nc[p], 24, Color.WHITE)
		c.custom_minimum_size.x = 40
		r.add_child(c)
		var chi := ses.nome(p)
		if ses.corte.dip[p] != null:
			chi = "IA «%s»" % ses.corte.dip[p].carattere
		var cc := UI.label(chi, 19, UI.MUTED)
		cc.clip_text = true
		cc.custom_minimum_size.x = 190
		r.add_child(cc)
		cl.add_child(r)
	# grafico
	var gr := Grafico.new()
	gr.g = g
	gr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gr.custom_minimum_size = Vector2(560, 380)
	hb.add_child(gr)
	var bt := UI.hbox(12)
	bt.alignment = BoxContainer.ALIGNMENT_CENTER
	corpo.add_child(bt)
	var ha_ia := false
	for p in 7:
		if ses.corte.dip[p] != null:
			ha_ia = true
	if ha_ia:
		bt.add_child(UI.primary("Archivi segreti", _archivi, 260, 24))
	bt.add_child(UI.button("Rivedi la mappa", _chiudi, 240, 24))
	bt.add_child(UI.button("Menu principale", func(): vista.main.show_menu(), 260, 24))


func _chiudi() -> void:
	vista._popup = null
	vista.scheda = "storico"
	vista._aggiorna_pannello()
	queue_free()


## Diari delle IA e dispacci, con le intese prese in malafede.
func _archivi() -> void:
	_svuota()
	var ses: DPSession = vista.ses
	corpo.add_child(UI.head("Archivi segreti delle cancellerie", 32))
	corpo.add_child(UI.label("Ora che la partita è finita si possono aprire i diari delle IA e leggere tutti i dispacci, compresi quelli scritti in malafede.", 21, UI.MUTED, UI.font_ital, true, 1100))
	var lista := UI.vbox(6)
	corpo.add_child(UI.scroll(lista, 560))
	for p in 7:
		var d: DPDiplomatico = ses.corte.dip[p]
		if d == null:
			continue
		var r := UI.hbox(10)
		r.add_child(UI.flag_rect(p, 28))
		r.add_child(UI.head("%s - carattere «%s», apertura: %s" % [DPMap.POTENZE[p], d.carattere, d.apertura if d.apertura != "" else "libera"], 22, DPMap.COLORI_TESTO[p]))
		lista.add_child(r)
		for riga in d.diario:
			lista.add_child(UI.label(str(riga), 19, UI.TEXT, null, true, 1080))
	lista.add_child(UI.head("Dispacci", 24))
	var n := 0
	for i in range(ses.corte.messaggi.size() - 1, -1, -1):
		var m: Dictionary = ses.corte.messaggi[i]
		if m["tipo"] == "risposta" or n > 400:
			continue
		n += 1
		var testa := "%s %d - %s a %s" % [DPGame.NOMI_FASE[m["fase"]], m["anno"], DPMap.POTENZE_BREVI[m["da"]], DPMap.POTENZE_BREVI[m["a"]]]
		var coda := ""
		if m.get("esito", "") == "si":
			coda = "  [accettato]"
		elif m.get("esito", "") == "no":
			coda = "  [rifiutato]"
		if m.has("sincero") and not m["sincero"]:
			coda += "  [in malafede]"
		lista.add_child(UI.label(testa + coda, 17, UI.OTTONE_L if not coda.contains("malafede") else UI.CERA_L, UI.font_head, true, 1080))
		lista.add_child(UI.label(str(m["testo"]), 18, UI.PARCH, UI.font_tele, true, 1080))
	corpo.add_child(UI.button("Indietro", _riepilogo, 240, 24))


## L'andamento dei centri di ogni potenza, anno per anno.
class Grafico extends Control:
	var g: DPGame

	func _draw() -> void:
		var serie := []
		var anni := []
		for voce in g.storia:
			if int(voce["fase"]) == DPGame.PRIMAVERA:
				var s := DPState.from_dict(voce["prima"])
				serie.append(s.conta_centri())
				anni.append(int(voce["anno"]))
		serie.append(g.st.conta_centri())
		anni.append(g.anno if g.fase == DPGame.PRIMAVERA or anni.is_empty() else g.anno + 1)
		var r := Rect2(Vector2(46, 14), size - Vector2(60, 50))
		draw_rect(r, Color(0, 0, 0, 0.25))
		var f := UI.font_body
		for y in [0, 6, 12, 18]:
			var py: float = r.position.y + r.size.y * (1.0 - float(y) / 20.0)
			draw_line(Vector2(r.position.x, py), Vector2(r.end.x, py), Color(UI.OTTONE, 0.6 if y == 18 else 0.2), 2.0 if y == 18 else 1.0)
			draw_string(f, Vector2(8, py + 6), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.MUTED)
		var n := serie.size()
		if n < 2:
			return
		var passo := maxi(1, int(ceil(n / 8.0)))
		for i in range(0, n, passo):
			var px: float = r.position.x + r.size.x * float(i) / float(n - 1)
			draw_string(f, Vector2(px - 20, r.end.y + 24), str(anni[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UI.MUTED)
		for p in 7:
			var pts := PackedVector2Array()
			for i in n:
				pts.append(Vector2(r.position.x + r.size.x * float(i) / float(n - 1), r.position.y + r.size.y * (1.0 - float(serie[i][p]) / 20.0)))
			draw_polyline(pts, Color(0, 0, 0, 0.7), 6.0, true)
			draw_polyline(pts, DPMap.COLORI[p].lightened(0.15), 3.5, true)

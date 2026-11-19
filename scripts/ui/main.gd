extends Control
## Radice dell'applicazione: alterna menu, partita e regole.

var current: Control
## Collegamento a Firebase (resta vivo fra menu e partita).
var net: Net
## Ultime scelte del menu (si ritrovano tornando al menu).
var menu_state := {}
var sessione: DPSession


func get_net() -> Net:
	if net == null:
		net = Net.new()
		add_child(net)
	return net


func _ready() -> void:
	DPMap.ensure()
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.Backdrop.new())
	var stanza := stanza_richiesta()
	if stanza != "":
		show_telefono(stanza)
	else:
		show_menu()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _clear() -> void:
	if current != null:
		current.queue_free()
		current = null
	if sessione != null:
		sessione.vivo = false
		sessione.queue_free()
		sessione = null


func show_menu() -> void:
	_clear()
	var m := preload("res://scripts/ui/menu.gd").new()
	m.main = self
	add_child(m)
	current = m


## Avvia la vista di gioco su una sessione già preparata (nuova, caricata oppure online).
func start_game(ses: DPSession, extra := {}) -> void:
	if current != null:
		current.queue_free()
		current = null
	sessione = ses
	if ses.get_parent() == null:
		add_child(ses)
	var gv := preload("res://scripts/ui/game_view.gd").new()
	gv.main = self
	var c := {"sessione": ses}
	c.merge(extra)
	gv.config = c
	add_child(gv)
	current = gv


func show_rules() -> void:
	_clear()
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.chiudi = show_menu
	add_child(t)
	current = t


## Il codice di stanza scritto nell'indirizzo (…/?stanza=ABCD): è il telefono che ha inquadrato il QR.
func stanza_richiesta() -> String:
	var c := OS.get_environment("DP_TELEFONO")
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('stanza') || ''", true)
		if r != null:
			c = str(r)
	c = c.strip_edges().to_upper()
	if c.length() != 4:
		return ""
	for i in 4:
		if c.unicode_at(i) < 65 or c.unicode_at(i) > 90:
			return ""
	return c


## L'indirizzo che il QR porta al telefono per entrare nella stanza.
static func indirizzo_stanza(codice: String) -> String:
	var base := "https://tannoiser2.github.io/Diplomacy/"
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
		if r != null and str(r).begins_with("http"):
			base = str(r)
	return base + "?stanza=" + codice


## La vista per il telefono: diplomazia e ordini, senza mappa.
func show_telefono(codice: String, ses: DPSession = null) -> void:
	_clear()
	var t := preload("res://scripts/ui/telefono_view.gd").new()
	t.main = self
	t.codice = codice
	if ses != null:
		sessione = ses
		if ses.get_parent() == null:
			add_child(ses)
		t.sessione_pronta = ses
	add_child(t)
	current = t

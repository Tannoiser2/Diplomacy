extends SceneTree
## La vista per il telefono, fotografata e provata su una partita locale (Italia in mano a una persona):
## quadro diplomatico, proposta, risposta, ordini passo per passo, consegna, risultati.
## Uso: xvfb-run -s "-screen 0 480x854x24" godot --path . -s tests/telefono.gd -- <cartella> [larghezza] [altezza]

var out := "/tmp/shots_tel"
var main
var errori := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var w := int(args[1]) if args.size() > 1 else 480
	var h := int(args[2]) if args.size() > 2 else 854
	DirAccess.make_dir_recursive_absolute(out)
	_run(w, h)


func _snap(nome: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, nome])
	print("foto ", nome)


func _aspetta(s: float) -> void:
	await create_timer(s).timeout


func _vero(c: bool, che: String) -> void:
	if not c:
		errori += 1
		print("ERRORE: ", che)


func _run(w: int, h: int) -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _aspetta(0.4)
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	seed(12)
	var ses := DPSession.new()
	ses.nuova({"posti": ["ia", "ia", "ia", "ia", "u", "ia", "ia"], "nomi": ["", "", "", "", "Stefano", "", ""], "livello": 1,
		"ultimo_anno": 0, "classiche": true, "seme": 4242})
	main.show_telefono("PROV", ses)
	ses.avvia()
	await _aspetta(1.0)
	var v = main.current
	_vero(v.io == 4, "la potenza del telefono è l'Italia")
	await _snap("01_quadro")
	v._apri_conversazione(5)
	await _aspetta(0.3)
	await _snap("02_conversazione")
	v.dispacci_ui.componi_tipo(0)
	await _aspetta(0.3)
	await _snap("03_proposta_alleanza")
	v.dispacci_ui.par = {"tipo": 3}
	v.dispacci_ui._finestra_componi()
	await _aspetta(0.3)
	await _snap("04_chiedi_sostegno")
	v._chiudi_popup()
	var prima := ses.corte.posta_di(4).size()
	for m in ses.corte.posta_di(4):
		if m["a"] == 4 and DPTesti.e_proposta(m["tipo"]) and m.get("esito", "") == "":
			v.dispacci_ui.rispondi(m, true)
			break
	_vero(ses.corte.posta_di(4).size() > prima, "la risposta alla proposta è partita")
	v._apri_conversazione(-1)
	await _aspetta(0.3)
	await _snap("05_quadro_dopo_accordo")
	v._apri_scheda("ordini")
	await _aspetta(0.2)
	await _snap("06_ordini")
	var ven: int = DPMap.per_sigla["VEN"]
	var rom: int = DPMap.per_sigla["ROM"]
	var nap: int = DPMap.per_sigla["NAP"]
	v._scegli_ordine(ven, "", -1)
	await _aspetta(0.2)
	await _snap("07_che_cosa_fa")
	v._scegli_ordine(ven, "muovi", -1)
	await _aspetta(0.2)
	await _snap("08_dove_muove")
	v._ordina(ven, [DPAdj.M, DPMap.per_sigla["TRI"], 0])
	v._scegli_ordine(rom, "sost1", -1)
	await _aspetta(0.2)
	await _snap("09_chi_sostiene")
	v._scegli_ordine(rom, "sost2", ven)
	await _aspetta(0.2)
	await _snap("10_sostegno_dove")
	v._ordina(rom, [DPAdj.S, ven, ven])
	v._scegli_ordine(nap, "muovi", -1)
	await _aspetta(0.2)
	await _snap("11_flotta_dove")
	v._ordina(nap, [DPAdj.M, DPMap.per_sigla["ION"], 0])
	await _aspetta(0.2)
	await _snap("12_ordini_dati")
	_vero(int(v.ordini[ven][0]) == DPAdj.M and int(v.ordini[rom][0]) == DPAdj.S, "gli ordini scelti sono registrati")
	v._consegna()
	await _aspetta(4.0)
	_vero(ses.g.storia.size() >= 1, "la fase è stata risolta")
	_vero(v.scheda == "situazione", "dopo la risoluzione si apre la situazione")
	await _snap("13_situazione")
	# avanti fino a ritirate o inverno, per fotografare anche quelle schede
	var visto_inverno := false
	for giro in 14:
		if ses.g.finita or visto_inverno:
			break
		await _aspetta(0.5)
		if v.posso_ordinare():
			v._apri_scheda("ordini")
			await _aspetta(0.2)
			if ses.g.e_ritirata():
				await _snap("14_ritirate")
			elif not ses.g.e_movimento():
				visto_inverno = true
				await _snap("15_inverno")
				if ses.g.saldo(4) > 0 and ses.g.case_libere(4).size() > 0:
					v._scegli_costruzione(ses.g.case_libere(4)[0])
					await _aspetta(0.2)
					await _snap("16_costruzione")
					v._chiudi_popup()
			if ses.g.e_movimento():
				# puntata verso i centri neutrali, per avere qualcosa da costruire
				var st := ses.g.st
				for u in st.unita_di(4):
					if st.ut[u] == 1 and DPMap.destinazioni(1, st.ul[u]).has(DPMap.per_sigla["TUN"]):
						v.ordini[u] = [DPAdj.M, DPMap.per_sigla["TUN"], 0]
			if not ses.g.e_movimento() and ses.g.saldo(4) < 0:
				for u in ses.g.st.unita_di(4):
					if v.scioglimenti.size() < -ses.g.saldo(4):
						v.scioglimenti[u] = true
			v._consegna()
			await _aspetta(3.0)
	v._apri_scheda("situazione")
	await _aspetta(0.2)
	await _snap("17_situazione_dopo")
	print("TELEFONO OK" if errori == 0 else "TELEFONO: %d ERRORI" % errori)
	quit(0 if errori == 0 else 1)

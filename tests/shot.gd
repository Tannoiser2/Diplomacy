extends SceneTree
## Fotografie dell'interfaccia (serve un display, anche virtuale: xvfb-run).
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- <cartella> [larghezza] [altezza]
## Gioca qualche fase come Italia e fotografa menu, regole, ordini, dispacci, risoluzione, storico e fine.

var out := "/tmp/shots"
var main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var w := int(args[1]) if args.size() > 1 else 1920
	var h := int(args[2]) if args.size() > 2 else 1080
	DirAccess.make_dir_recursive_absolute(out)
	_run(w, h)


func _snap(nome: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nome])
	print("foto ", nome)


func _aspetta(s: float) -> void:
	await create_timer(s).timeout


func _run(w: int, h: int) -> void:
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _aspetta(1.0)
	await _snap("01_menu")
	main.current._apri("online")
	await _aspetta(0.3)
	await _snap("02_menu_online")
	main.current._apri("carica")
	await _snap("03_menu_carica")
	main.show_rules()
	await _aspetta(0.4)
	await _snap("04_regole")
	main.current._apri(4)
	await _snap("05_regole_scontri")
	main.current._apri(11)
	await _snap("06_regole_aperture")
	# partita: Italia in mano a una persona
	seed(12)
	var ses := DPSession.new()
	ses.nuova({"posti": ["ia", "ia", "ia", "ia", "u", "ia", "ia"], "nomi": ["", "", "", "", "Stefano", "", ""], "livello": 1,
		"ultimo_anno": 0, "classiche": true, "seme": 4242})
	main.start_game(ses)
	ses.avvia()
	await _aspetta(1.5)
	var v = main.current
	await _snap("10_partita")
	var ven: int = DPMap.per_sigla["VEN"]
	var rom: int = DPMap.per_sigla["ROM"]
	var nap: int = DPMap.per_sigla["NAP"]
	v._seleziona(ven)
	await _snap("11_unita_selezionata")
	v._modo("sost1")
	await _snap("12_sostieni")
	v._seleziona(ven)
	v._apri_scheda("dispacci")
	await _aspetta(0.3)
	await _snap("13_dispacci")
	v.dispacci_ui.componi()
	await _aspetta(0.3)
	await _snap("14_nuovo_dispaccio")
	v.con_chi = 0
	v.dispacci_ui.par = {"tipo": 3}
	v.dispacci_ui._finestra_componi()
	await _snap("15_dispaccio_sostegno")
	v._chiudi_popup()
	# accetto la prima proposta ricevuta, se c'è
	for m in ses.corte.posta_di(4):
		if m["a"] == 4 and DPTesti.e_proposta(m["tipo"]) and m.get("esito", "") == "":
			v.dispacci_ui.rispondi(m, true)
			break
	await _snap("16_dispacci_risposta")
	v._menu()
	await _snap("17_menu_partita")
	v._chiudi_popup()
	v._apri_scheda("ordini")
	v.ordini[ven] = [DPAdj.H, -1, -1]
	v.ordini[rom] = [DPAdj.M, DPMap.per_sigla["APU"], 0]
	v.ordini[nap] = [DPAdj.M, DPMap.per_sigla["ION"], 0]
	v._ridisegna_ordini()
	v._aggiorna_tutto()
	await _snap("18_ordini_dati")
	v._consegna()
	await _aspetta(2.6)
	await _snap("20_risoluzione")
	while not v._attesa_continua:
		await process_frame
	await _snap("21_riepilogo")
	# si va avanti con ordini semplici fino all'inverno 1901 e oltre
	var foto_inverno := false
	var foto_rit := false
	var giri := 0
	while giri < 14 and ses.g.anno <= 1903:
		await process_frame
		if v._attesa_continua:
			v._attesa_continua = false
			continue
		if v.in_replay or ses.in_calcolo:
			continue
		if v.posso_ordinare():
			var g: DPGame = ses.g
			if g.fase == DPGame.INVERNO and not foto_inverno:
				foto_inverno = true
				await _snap("22_inverno")
			if g.e_ritirata() and not foto_rit:
				foto_rit = true
				await _snap("23_ritirate")
			if g.e_movimento():
				# ordini di buon senso presi dal motore tattico
				var ost := PackedFloat32Array([0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6])
				var val: Array = ses.corte.tat.valori(g.st, 4, ost, g.fase == DPGame.AUTUNNO, g.anno)
				v.ordini = ses.corte.tat.candidato(g.st, 4, val, ost, 0.0)
			elif g.e_ritirata():
				for r in g.ritirate_di(4):
					v.rit_scelte[r["prov"]] = r["opzioni"][0] if r["opzioni"].size() > 0 else -1
			elif g.saldo(4) > 0:
				for pr in g.case_libere(4):
					if v.costruzioni.size() < g.saldo(4):
						v.costruzioni[pr] = [0, pr]
			else:
				var u := g.st.unita_di(4)
				for k in -g.saldo(4):
					v.scioglimenti[u[k]] = true
			v._consegna()
			giri += 1
			await _aspetta(0.3)
	v._apri_scheda("storico")
	await _snap("24_storico")
	v._apri_storico(0)
	await _aspetta(0.3)
	await _snap("25_storico_fase")
	v._torna_presente()
	v.board.pitch = 0.7
	v.board.dist = 4.0
	v.board.yaw = 0.4
	v.board.target = v.board.to3(DPMap.pos_pedina[DPMap.per_sigla["VIE"]])
	v.board._cam()
	v._apri_scheda("ordini")
	await _snap("26_vista_ravvicinata")
	v._menu_pedine()
	v._chiudi_popup()
	await _snap("27_pedine_modulo")
	v._menu_pedine()
	v._chiudi_popup()
	v.board.reset_view()
	ses.g.finita = true
	ses.g.vincitore = 4
	v._fine()
	await _aspetta(0.3)
	await _snap("30_fine")
	v._popup._archivi()
	await _snap("31_archivi")
	quit()

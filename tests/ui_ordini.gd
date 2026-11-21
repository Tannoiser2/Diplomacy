extends SceneTree
## Prova dell'interfaccia degli ordini senza schermo: tocchi sulla mappa (proiezione e riconoscimento
## delle province), mosse, sostegni, convogli, scelta della costa, passaggio del dispositivo fra due persone.

var main
var errori := 0


func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run()


func _verifica(cond: bool, cosa: String) -> void:
	if not cond:
		errori += 1
		print("ERRORE: ", cosa)


func P(s: String) -> int:
	return DPMap.per_sigla[s]


func _run() -> void:
	await create_timer(0.3).timeout
	root.size = Vector2i(1920, 1080)
	var ses := DPSession.new()
	ses.nuova({"posti": ["ia", "u", "u", "ia", "ia", "ia", "ia"], "nomi": ["", "Anna", "Bruno", "", "", "", ""], "livello": 0,
		"ultimo_anno": 0, "classiche": true, "seme": 5})
	# una posizione costruita apposta: flotta francese in Medio Atlantico, armata inglese a Londra con flotta nel Mare del Nord
	var st := DPState.new()
	st.metti(1, 0, P("LON"))
	st.metti(1, 1, P("NTH"))
	st.metti(1, 0, P("YOR"))
	st.metti(2, 1, P("MAO"))
	st.metti(2, 0, P("PAR"))
	st.metti(2, 0, P("BUR"))
	st.metti(3, 0, P("MUN"))
	st.metti(3, 0, P("RUH"))
	st.metti(6, 0, P("SMY"))
	st.metti(6, 1, P("AEG"))
	for c in DPMap.centri:
		st.sc[c] = DPMap.casa_centro[c]
	ses.g.st = st
	main.start_game(ses, {"auto": true})
	ses.avvia()
	await create_timer(0.5).timeout
	var v = main.current
	v.size = Vector2(1920, 1080)
	v.board.size = Vector2(1920, 1080)
	v.board.vp.size = Vector2i(1920, 1080)
	v.board.reset_view()
	await process_frame
	_verifica(v.io == 1, "tocca all'Inghilterra per prima (io=%d)" % v.io)
	# 1. il tocco sullo schermo trova la provincia giusta, per tutte le province
	var sbagli := 0
	for i in DPMap.N_PROV:
		var s: Vector2 = v.board.schermo_loc(i)
		var m: Vector2 = v.board.punto_mappa(s)
		var p: int = v.board.provincia_in(m)
		if p != i:
			sbagli += 1
			print("  tocco su ", DPMap.sigla[i], " -> ", DPMap.sigla[p] if p >= 0 else "?")
	_verifica(sbagli == 0, "%d province non riconosciute al tocco" % sbagli)
	# 2. mossa per convoglio: Londra - Belgio (non confinano: solo via mare)
	v._su_tocco(P("LON"), true)
	_verifica(v.sel == P("LON") and v.modo == "muovi", "selezione di Londra")
	_verifica(v.sbarchi(P("LON")).has(P("BEL")), "il Belgio è fra gli sbarchi possibili")
	v._su_tocco(P("BEL"), false)
	_verifica(v.ordini[P("LON")] == [DPAdj.M, P("BEL"), 1], "A Lon - Bel via convoglio: %s" % str(v.ordini[P("LON")]))
	# 2b. una flotta convoglia solo armate raggiungibili con una catena di flotte che la comprende
	_verifica(not v.sbarchi(P("SMY")).is_empty(), "Smirne è convogliabile dalla flotta nell'Egeo")
	_verifica(v.sbarchi(P("SMY"), P("NTH")).is_empty(), "il Mare del Nord non può convogliare l'armata di Smirne")
	_verifica(v.sbarchi(P("LON"), P("MAO")).is_empty(), "il Medio Atlantico non può convogliare l'armata di Londra")
	_verifica(v.sbarchi(P("LON"), P("NTH")).has(P("BEL")), "il Mare del Nord convoglia Londra in Belgio")
	# 3. convoglio: F Nth C A Lon - Bel
	v._su_tocco(P("NTH"), true)
	v._modo("conv1")
	v._su_tocco(P("SMY"), true)
	_verifica(v.modo == "conv1", "l'armata di Smirne non si può scegliere per il convoglio del Mare del Nord")
	v._su_tocco(P("LON"), true)
	_verifica(v.modo == "conv2", "scelta dell'armata da convogliare")
	v._su_tocco(P("BEL"), false)
	_verifica(v.ordini[P("NTH")] == [DPAdj.C, P("LON"), P("BEL")], "F Nth C A Lon - Bel: %s" % str(v.ordini[P("NTH")]))
	# 4. mossa con doppia via (Yorkshire - Londra è anche convogliabile? no: Londra è occupata ma confinante) e sostegno
	v._su_tocco(P("YOR"), true)
	v._modo("sost1")
	v._su_tocco(P("LON"), true)
	_verifica(v.modo == "sost2", "scelta dell'unità da sostenere")
	v._su_tocco(P("LON"), false)
	_verifica(v.ordini[P("YOR")] == [DPAdj.S, P("LON"), P("LON")], "A Yor S A Lon: %s" % str(v.ordini[P("YOR")]))
	v._consegna()
	await create_timer(0.3).timeout
	# 5. passaggio del dispositivo alla Francia
	_verifica(v.io == 2, "ora tocca alla Francia (io=%d)" % v.io)
	_verifica(v._popup != null, "compare l'avviso di passare il dispositivo")
	v._chiudi_popup()
	# 6. flotta verso la Spagna: due coste, si chiede quale
	v._su_tocco(P("MAO"), true)
	v._su_tocco(P("SPA"), false)
	_verifica(v._popup != null, "richiesta della costa di Spagna")
	v._ordina(P("MAO"), [DPAdj.M, P("SPA/SC"), 0])
	_verifica(v.ordini[P("MAO")] == [DPAdj.M, P("SPA/SC"), 0], "F Mao - Spa/sc")
	# 7. mossa semplice e sostegno a una mossa: A Bur - Mun, A Par resta
	v._su_tocco(P("BUR"), true)
	v._su_tocco(P("MUN"), false)
	_verifica(v.ordini[P("BUR")] == [DPAdj.M, P("MUN"), 0], "A Bur - Mun")
	v._consegna()
	# la risoluzione parte quando hanno consegnato tutte le persone
	var t := 0.0
	while ses.g.storia.is_empty() and t < 20.0:
		await process_frame
		t += 0.016
	_verifica(not ses.g.storia.is_empty(), "la fase si risolve dopo le due consegne")
	if not ses.g.storia.is_empty():
		var voce: Dictionary = ses.g.storia[0]
		_verifica(ses.g.st.up[P("BEL")] == 1, "l'armata inglese è sbarcata in Belgio")
		_verifica(ses.g.st.ul[P("SPA")] == P("SPA/SC"), "la flotta francese è sulla costa sud della Spagna")
		_verifica(voce["esiti"][P("BUR")] == DPGame.E_RESPINTA, "A Bur - Mun respinta (Monaco tiene)")
	print("INTERFACCIA OK" if errori == 0 else "INTERFACCIA: %d errori" % errori)
	quit(0 if errori == 0 else 1)

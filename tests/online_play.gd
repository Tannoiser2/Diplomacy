extends SceneTree
## Prova del gioco online: due istanze (chi crea la stanza guida l'Italia, l'amico la Francia, le altre
## cinque potenze sono IA di chi ospita) giocano sul finto Firebase (tests/firebase_mock.py) fino al 1904.
## DP_ROLE=host|guest, DP_CODEFILE=file per il codice della stanza.
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0

func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("DP_ROLE")
	var cf := OS.get_environment("DP_CODEFILE")
	var menu = main.current
	menu._apri("online")
	menu.on_name.text = "Stefano" if role == "host" else "Marco"
	if role == "host":
		menu.mio_posto = 4
		menu.aperti[2] = true
		menu.livello = 0
		await menu._online_create()
		var code: String = menu.lobby.get("code", "")
		print("DPTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._online_join()
	var ost := PackedFloat32Array([0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6])
	var scritto := false
	var risposto := {}
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 600000:
			print("DPTEST tempo scaduto")
			quit(2)
			return
		var v = main.current
		if v == null or not ("ses" in v) or v.ses == null:
			continue
		var ses: DPSession = v.ses
		var g: DPGame = ses.g
		v.config["auto"] = true
		var io: int = ses.posto
		if g.anno >= 1904:
			await _wait(1.0)
			print("DPTEST impronta %s | %d | %d | dispacci visti %d" % [str(JSON.stringify(g.st.to_dict()).hash()), g.storia.size(), ses.n, ses.corte.posta_di(io).size()])
			quit(0)
			return
		if not scritto and g.e_movimento():
			# un dispaccio a un'altra persona e una proposta a un'IA
			scritto = true
			ses.invia({"da": io, "a": 2 if io == 4 else 4, "tipo": "pace", "d": {}, "v": 1})
			ses.invia({"da": io, "a": 3, "tipo": "pace", "d": {}, "v": 2})
		for m in ses.corte.posta_di(io):
			if m["a"] == io and DPTesti.e_proposta(m["tipo"]) and m.get("esito", "") == "" and not risposto.has(m["id"]):
				risposto[m["id"]] = true
				ses.invia({"da": io, "a": m["da"], "tipo": "risposta", "d": {"si": true}, "rif": m["id"], "v": 0})
		if v.posso_ordinare():
			var val: Array = ses.corte.tat.valori(g.st, io, ost, g.fase == DPGame.AUTUNNO, g.anno)
			if g.e_movimento():
				v.ordini = ses.corte.tat.candidato(g.st, io, val, ost, 0.0)
			elif g.e_ritirata():
				v.rit_scelte = ses.corte.tat.ritirate(g, io, val)
			else:
				var a: Dictionary = ses.corte.tat.aggiustamenti(g, io, val, ost)
				v.costruzioni = {}
				v.scioglimenti = {}
				for c in a.get("c", []):
					v.costruzioni[DPMap.loc_prov[c[1]]] = c
				for u in a.get("s", []):
					v.scioglimenti[u] = true
			v._consegna()
			await _wait(0.2)

extends SceneTree
## Prova della partita «tabellone + telefoni» sul finto Firebase (tests/firebase_mock.py):
## DP_ROLE=tavolo crea la stanza senza giocare (mostra solo la mappa); DP_ROLE=telefono entra come farebbe
## chi inquadra il QR, sceglie la potenza DP_POSTO e gioca dalla vista per telefono fino al 1903.
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

func _fine(ses: DPSession, chi: String) -> void:
	await _wait(1.0)
	print("DPTEST impronta %s | %d | %s" % [str(JSON.stringify(ses.g.st.to_dict()).hash()), ses.g.storia.size(), chi])
	quit(0)

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("DP_ROLE")
	var cf := OS.get_environment("DP_CODEFILE")
	if role == "tavolo":
		var menu = main.current
		menu._apri("online")
		menu.on_name.text = "Tavolo"
		menu._scegli_posto(7)
		menu.aperti[2] = true
		menu.aperti[4] = true
		menu.livello = 0
		await menu._online_create()
		var code: String = menu.lobby.get("code", "")
		print("DPTEST stanza ", code, " posto ", menu.lobby.get("seat", "?"))
		var m := DPQr.matrice(main.indirizzo_stanza(code))
		print("DPTEST qr ", m.size())
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
		while true:
			await process_frame
			if Time.get_ticks_msec() - t0 > 500000:
				print("DPTEST tempo scaduto")
				quit(2)
				return
			var v = main.current
			if v == null or not ("ses" in v) or v.ses == null:
				continue
			v.config["auto"] = true
			if v.ses.g.anno >= 1903:
				print("DPTEST tavolo: io=%d locali=%s" % [v.io, str(v.ses.locali)])
				await _fine(v.ses, "tavolo")
				return
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		var voglio := int(OS.get_environment("DP_POSTO"))
		main.show_telefono(code)
		var v = main.current
		while not (v.passo == "entra" and v.nome_edit != null and is_instance_valid(v.nome_edit)):
			await _wait(0.2)
		v.nome_edit.text = "Tel%d" % voglio
		await v._prendi(voglio)
		print("DPTEST telefono: posto ", v.posto)
		var ost := PackedFloat32Array([0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6])
		var risposto := {}
		var scritto := false
		while true:
			await process_frame
			if Time.get_ticks_msec() - t0 > 500000:
				print("DPTEST tempo scaduto")
				quit(2)
				return
			if v.passo != "gioco":
				continue
			var ses: DPSession = v.ses
			var g: DPGame = ses.g
			var io: int = v.io
			if g.anno >= 1903:
				print("DPTEST telefono %d: dispacci visti %d" % [io, ses.corte.posta_di(io).size()])
				await _fine(ses, "telefono")
				return
			if not scritto and g.e_movimento():
				scritto = true
				v.con_chi = 3
				v.dispacci_ui.par = {"tipo": 1}
				v.dispacci_ui._finestra_componi()
				await _wait(0.2)
				v.dispacci_ui._spedisci({"da": io, "a": 3, "tipo": "pace", "d": {}, "v": 0})
			for m in ses.corte.posta_di(io):
				if m["a"] == io and DPTesti.e_proposta(m["tipo"]) and m.get("esito", "") == "" and not risposto.has(m["id"]):
					risposto[m["id"]] = true
					v.dispacci_ui.rispondi(m, true)
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

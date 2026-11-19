extends SceneTree
## Il «tabellone» per le prove (vedi tests/telefono_pagina.sh): crea sul finto Firebase una stanza senza
## giocare, aspetta DP_ATTESI telefoni, avvia la partita e la porta avanti fino al 1903 servendo i telefoni.
## Scrive il codice della stanza in DP_CODEFILE.

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
	var cf := OS.get_environment("DP_CODEFILE")
	if true:
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
			if Net._as_dict(room.get("seats", {})).size() >= (int(OS.get_environment("DP_ATTESI")) if OS.get_environment("DP_ATTESI") != "" else 2):
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

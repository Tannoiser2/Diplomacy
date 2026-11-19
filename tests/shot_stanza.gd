extends SceneTree
## Fotografie della stanza «tabellone + telefoni» (serve il finto Firebase e un display virtuale).
## DP_ROLE=tavolo|telefono, DP_CODEFILE, argomenti: <cartella> <larghezza> <altezza>

var out := "/tmp/shots_stanza"
var main

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run(int(args[1]), int(args[2]))

func _snap(nome: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, nome])
	print("foto ", nome)

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run(w: int, h: int) -> void:
	await _wait(0.4)
	root.size = Vector2i(w, h)
	DisplayServer.window_set_size(Vector2i(w, h))
	var cf := OS.get_environment("DP_CODEFILE")
	if OS.get_environment("DP_ROLE") == "tavolo":
		var menu = main.current
		menu._apri("online")
		menu.on_name.text = "Tavolo"
		menu._scegli_posto(7)
		for p in [1, 2, 4, 5]:
			menu.aperti[p] = true
		menu._apri("online")
		await _snap("s1_crea_stanza")
		await menu._online_create()
		var code: String = menu.lobby.get("code", "")
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 1:
				break
			await _wait(0.5)
		await _wait(2.0)
		await _snap("s2_stanza_con_qr")
		await menu._online_start()
		await _wait(2.5)
		await _snap("s3_tabellone")
		main.current._mostra_qr()
		await _wait(0.3)
		await _snap("s4_qr_in_partita")
		await _wait(6.0)
		quit(0)
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		main.show_telefono(code)
		var v = main.current
		while not (v.passo == "entra" and v.nome_edit != null and is_instance_valid(v.nome_edit)):
			await _wait(0.2)
		v.nome_edit.text = "Stefano"
		await _snap("t1_entra")
		await v._prendi(4)
		await _wait(2.0)
		await _snap("t2_attesa")
		while v.passo != "gioco":
			await _wait(0.3)
		await _wait(2.0)
		await _snap("t3_in_partita")
		quit(0)

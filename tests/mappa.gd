extends SceneTree
## Controlla le due carte (ridisegnata e tabellone originale): ogni pedina e ogni stella
## devono cadere dentro la loro provincia nella mappa dei tocchi.

func _init() -> void:
	var errori := 0
	for reale in [false, true]:
		DPMap.usa(reale)
		var img := Image.new()
		img.load("res://assets/mappa_reale/id.png" if reale else "res://assets/mappa/id.png")
		var k := float(img.get_width()) / DPMap.larghezza
		for l in DPMap.N_LOC:
			if not reale and l >= DPMap.N_PROV:
				continue   # sulla carta ridisegnata le flotte delle coste doppie stanno apposta sull'acqua
			var p: Vector2 = DPMap.pos_pedina[l] * k
			var id := int(round(img.get_pixel(int(p.x), int(p.y)).r * 255.0)) - 1
			if id != DPMap.loc_prov[l]:
				errori += 1
				print("pedina fuori posto: ", DPMap.sigla[l], " (", "tabellone" if reale else "ridisegnata", ") trovata in ", id)
		for c in DPMap.centri:
			var p: Vector2 = DPMap.pos_stella[c] * k
			var id := int(round(img.get_pixel(int(p.x), int(p.y)).r * 255.0)) - 1
			if id != c and not (reale and DPMap.sigla[c] == "CON"):   # la stella di Costantinopoli è stampata sullo stretto
				errori += 1
				print("stella fuori posto: ", DPMap.sigla[c], " (", "tabellone" if reale else "ridisegnata", ")")
	print("MAPPE OK" if errori == 0 else "ERRORI: %d" % errori)
	quit(0 if errori == 0 else 1)

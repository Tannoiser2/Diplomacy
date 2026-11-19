extends SceneTree
## Partite complete fra sole IA, con diplomazia: controlla che il gioco arrivi in fondo e mostra
## centri, patti e tradimenti. Uso: godot --headless --path . --script tests/sim.gd -- [partite] [livello] [dettagli]

func _init() -> void:
	DPMap.ensure()
	var args := OS.get_cmdline_user_args()
	var partite := int(args[0]) if args.size() > 0 else 1
	var liv := int(args[1]) if args.size() > 1 else 2
	var dettagli := args.size() > 2
	var vittorie := [0, 0, 0, 0, 0, 0, 0]
	var pareggi := 0
	var t0 := Time.get_ticks_msec()
	for n in partite:
		var g := DPGame.new()
		var c := DPCorte.new()
		c.crea(g, [false, false, false, false, false, false, false], liv, 1000 + n * 7)
		var max_ms := 0
		while not g.finita and g.anno <= 1930:
			var t1 := Time.get_ticks_msec()
			c.apri_fase()
			for p in 7:
				if g.deve_ordinare(p):
					g.imposta_ordini(p, c.ordini_ia(p))
			var inverno := g.fase == DPGame.INVERNO
			var voce := g.risolvi()
			c.dopo_risoluzione(voce)
			max_ms = maxi(max_ms, Time.get_ticks_msec() - t1)
			if dettagli and (g.fase == DPGame.PRIMAVERA or g.finita):
				print(g.anno - 1, " ", g.st.conta_centri())
			if g.fase == DPGame.PRIMAVERA and g.anno >= 1908 and not g.finita:
				c.proponi_pareggio(-1)
				c.voti.erase(-1)
				if c.esito_pareggio() == 1:
					g.pareggio()
		var tipi := {}
		for m in c.messaggi:
			var k: String = m["tipo"]
			if k == "nota":
				k = "nota:" + str(m["d"].get("k", ""))
			if k == "risposta":
				k = "risposta:" + ("si" if m["d"].get("si", false) else "no")
			tipi[k] = tipi.get(k, 0) + 1
		var pugnalate := 0
		var car := []
		for p in 7:
			car.append(c.dip[p].carattere)
			for r in c.dip[p].diario:
				if (r as String).contains("PUGNALO"):
					pugnalate += 1
					if dettagli:
						print("  ", DPMap.POTENZE_BREVI[p], " ", r)
		if g.vincitore >= 0:
			vittorie[g.vincitore] += 1
		else:
			pareggi += 1
		print("partita %d: fine %d, vincitore %s, centri %s, pugnalate %d, fase più lenta %d ms" % [n, g.anno,
			DPMap.POTENZE_BREVI[g.vincitore] if g.vincitore >= 0 else "pareggio " + str(g.pari), str(g.st.conta_centri()), pugnalate, max_ms])
		if dettagli:
			print("  caratteri ", car)
			print("  dispacci ", tipi)
			for p in 7:
				print("  ", DPMap.POTENZE_BREVI[p], ": ", c.dip[p].apertura)
	print("vittorie %s, pareggi %d, secondi %.1f" % [str(vittorie), pareggi, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()

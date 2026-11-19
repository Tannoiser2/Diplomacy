extends SceneTree
## Diagnostica: una partita fra IA con gli ordini anno per anno e i diari dei diplomatici.
## Uso: … --script tests/diag.gd -- seme ultimo_anno

func _init() -> void:
	DPMap.ensure()
	var args := OS.get_cmdline_user_args()
	var seme := int(args[0]) if args.size() > 0 else 1028
	var fino := int(args[1]) if args.size() > 1 else 1904
	var g := DPGame.new()
	var c := DPCorte.new()
	c.crea(g, [false, false, false, false, false, false, false], 2, seme)
	while not g.finita and g.anno <= fino:
		c.apri_fase()
		var n0 := c.messaggi.size()
		for p in 7:
			if g.deve_ordinare(p):
				g.imposta_ordini(p, c.ordini_ia(p))
		var voce := g.risolvi()
		c.dopo_risoluzione(voce)
		if voce.has("ordini"):
			var prima := DPState.from_dict(voce["prima"])
			print("== ", DPGame.NOMI_FASE[voce["fase"]], " ", voce["anno"])
			for p in 7:
				var righe := []
				for k in voce["ordini"]:
					if prima.up[k] == p:
						righe.append(DPGame.testo_ordine(prima, k, voce["ordini"][k]) + ("!" if voce["esiti"][k] != 0 else ""))
				var d: DPDiplomatico = c.dip[p]
				print("  %s [bers %s, all %s] %s" % [DPMap.SIGLE_POT[p], DPMap.SIGLE_POT[d.bersaglio] if d.bersaglio >= 0 else "-",
					DPMap.SIGLE_POT[d.alleato] if d.alleato >= 0 else "-", ", ".join(righe)])
		elif voce.has("costruite"):
			var s := []
			for x in voce["costruite"]:
				s.append("%s+%s %s" % [DPMap.SIGLE_POT[x[0]], "AF"[x[1]], DPMap.sigla[x[2]]])
			for x in voce["sciolte"]:
				s.append("%s-%s %s" % [DPMap.SIGLE_POT[x[0]], "AF"[x[1]], DPMap.sigla[x[2]]])
			print("== Inverno ", voce["anno"], " ", ", ".join(s), " centri ", g.st.conta_centri())
	for p in 7:
		var d: DPDiplomatico = c.dip[p]
		print(DPMap.POTENZE_BREVI[p], " (", d.carattere, ") rel ", d.rel, " patti ", d.patti.size())
		for r in d.diario.slice(0, 14):
			print("    ", r)
	quit()

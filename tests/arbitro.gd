extends SceneTree
## Prova dell'arbitro: confronta le risoluzioni con quelle del motore di riferimento
## (casi DATC e posizioni casuali in tests/casi_arbitro.json, generati da tools/genera_casi.py).
## Uso: godot --headless --path . --script tests/arbitro.gd [-- nome_del_caso]

func _init() -> void:
	DPMap.ensure()
	var casi: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/casi_arbitro.json"))
	var solo := ""
	for a in OS.get_cmdline_user_args():
		solo = a
	var adj := DPAdj.new()
	var errori := 0
	var fatti := 0
	for c in casi:
		if solo != "" and c["nome"] != solo:
			continue
		fatti += 1
		var st := DPState.new()
		for u in c["unita"]:
			st.metti(int(u[0]), int(u[1]), int(u[2]))
		adj.pulisci()
		adj.carica(c["ordini"])
		adj.risolvi(st)
		var r := adj.applica(st)
		var dopo := []
		var ns: DPState = r["stato"]
		for i in DPMap.N_PROV:
			if ns.up[i] >= 0:
				dopo.append([ns.up[i], ns.ut[i], ns.ul[i]])
		dopo.sort()
		var atteso := []
		for u in c["dopo"]:
			atteso.append([int(u[0]), int(u[1]), int(u[2])])
		atteso.sort()
		var rit := {}
		var quirk := false
		for x in r["ritirate"]:
			var o := Array(x["opzioni"])
			o.sort()
			# il motore di riferimento, se l'attaccante arriva per convoglio, elenca per errore anche
			# le province occupate: in quel caso si controlla solo che le nostre siano fra le sue
			if adj.via_mare[adj.sloggiata[x["prov"]]] == 1:
				quirk = true
			if not o.is_empty():
				rit[str(x["prov"])] = o
		var rit_att := {}
		for k in c["ritirate"]:
			var o := []
			for v in c["ritirate"][k]:
				o.append(int(v))
			o.sort()
			rit_att[k] = o
		if quirk:
			var ok := true
			for k in rit:
				for l in rit[k]:
					if not rit_att.has(k) or not (rit_att[k] as Array).has(l):
						ok = false
			if ok:
				rit = rit_att
		if dopo != atteso or rit != rit_att:
			errori += 1
			if errori <= 12 or solo != "":
				print("DIVERSO ", c["nome"])
				print("  unità  ", _u(c["unita"]))
				print("  ordini ", _o(c["ordini"]))
				print("  atteso ", _u(atteso), " rit ", _r(rit_att))
				print("  avuto  ", _u(dopo), " rit ", _r(rit))
	print("casi %d, diversi %d" % [fatti, errori])
	quit(1 if errori > 0 else 0)


func _u(a: Array) -> String:
	var s := []
	for u in a:
		s.append("%s%s %s" % [DPMap.SIGLE_POT[int(u[0])], "A" if int(u[1]) == 0 else "F", DPMap.sigla[int(u[2])]])
	return ", ".join(s)


func _o(d: Dictionary) -> String:
	var s := []
	for k in d:
		var o: Array = d[k]
		var t := int(o[0])
		var a := int(o[1])
		var n: String = DPMap.sigla[int(k)]
		match t:
			0: s.append(n + " H")
			1: s.append("%s-%s%s" % [n, DPMap.sigla[a] if a >= 0 and a < DPMap.N_LOC else "?", " VIA" if int(o[2]) == 1 else ""])
			2: s.append("%s S %s-%s" % [n, DPMap.sigla[a], DPMap.sigla[int(o[2])]])
			3: s.append("%s C %s-%s" % [n, DPMap.sigla[a], DPMap.sigla[int(o[2])]])
	return ", ".join(s)


func _r(d: Dictionary) -> String:
	var s := []
	for k in d:
		var o := []
		for l in d[k]:
			o.append(DPMap.sigla[int(l)])
		s.append("%s>[%s]" % [DPMap.sigla[int(k)], " ".join(o)])
	return ", ".join(s)

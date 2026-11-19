extends SceneTree
## Prova di salvataggio e ripresa: si giocano alcune fasi, si salva, si ricarica e si controlla che
## posizione, storico, patti e posta coincidano; poi la partita ricaricata prosegue senza errori.

func _init() -> void:
	DPMap.ensure()
	var ses := DPSession.new()
	ses.nuova({"posti": ["ia", "u", "ia", "ia", "u", "ia", "ia"], "nomi": ["", "Anna", "", "", "Stefano", "", ""],
		"livello": 1, "ultimo_anno": 0, "classiche": true, "seme": 77})
	_gioca(ses, 9)
	var testo := JSON.stringify(ses.stato())
	print("salvataggio: %d caratteri, %d dispacci" % [testo.length(), ses.corte.messaggi.size()])
	var ses2 := DPSession.new()
	ses2.da_stato(JSON.parse_string(testo))
	var ok := true
	if JSON.stringify(ses.g.to_dict()) != JSON.stringify(ses2.g.to_dict()):
		print("ERRORE: la partita ricaricata è diversa")
		ok = false
	for p in 7:
		var a: DPDiplomatico = ses.corte.dip[p]
		var b: DPDiplomatico = ses2.corte.dip[p]
		if (a == null) != (b == null):
			print("ERRORE: IA diverse al posto ", p)
			ok = false
		elif a != null:
			if a.patti.size() != b.patti.size() or a.bersaglio != b.bersaglio or a.carattere != b.carattere:
				print("ERRORE: diplomatico diverso al posto ", p)
				ok = false
			for q in 7:
				if absf(a.rel[q] - b.rel[q]) > 0.001 or absf(a.fid[q] - b.fid[q]) > 0.001:
					print("ERRORE: rapporti diversi ", p, " ", q)
					ok = false
	if ses2.corte.messaggi.size() == 0:
		print("ERRORE: posta persa")
		ok = false
	_gioca(ses2, 8)
	print("dopo la ripresa: %s, centri %s" % [ses2.g.nome_fase(), str(ses2.g.st.conta_centri())])
	print("SALVATAGGIO OK" if ok else "SALVATAGGIO FALLITO")
	ses.free()
	ses2.free()
	quit(0 if ok else 1)


func _gioca(ses: DPSession, fasi: int) -> void:
	var g := ses.g
	var ost := PackedFloat32Array([0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6])
	for k in fasi:
		if g.finita:
			return
		ses.corte.apri_fase()
		# le persone rispondono sì alle proposte e danno ordini di buon senso
		for p in 7:
			if ses.e_umano(p):
				for m in ses.corte.posta_di(p):
					if m["a"] == p and DPTesti.e_proposta(m["tipo"]) and m.get("esito", "") == "" and m["anno"] == g.anno and m["fase"] == g.fase:
						ses.corte.spedisci({"da": p, "a": m["da"], "tipo": "risposta", "d": {"si": true}, "rif": m["id"]})
		for p in 7:
			if not g.deve_ordinare(p):
				continue
			if ses.e_umano(p):
				var val := ses.corte.tat.valori(g.st, p, ost, g.fase == DPGame.AUTUNNO, g.anno)
				if g.e_movimento():
					g.imposta_ordini(p, ses.corte.tat.candidato(g.st, p, val, ost, 0.0))
				elif g.e_ritirata():
					g.imposta_ordini(p, ses.corte.tat.ritirate(g, p, val))
				else:
					g.imposta_ordini(p, ses.corte.tat.aggiustamenti(g, p, val, ost))
			else:
				g.imposta_ordini(p, ses.corte.ordini_ia(p))
		ses.corte.dopo_risoluzione(g.risolvi())

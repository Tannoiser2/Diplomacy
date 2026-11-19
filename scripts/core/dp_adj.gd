class_name DPAdj
extends RefCounted
## L'arbitro: risolve gli ordini di una fase di movimento secondo le regole di Diplomacy
## (algoritmo di Lucas Kruijswijk, «The Math of Adjudication», con la regola di Szykman per i
## paradossi dei convogli) e calcola le ritirate possibili.
##
## Gli ordini sono indicizzati per provincia dell'unità:
##   FERMA      ot = H
##   MUOVE      ot = M, oa = località di arrivo, ob = 1 se «via convoglio»
##   SOSTIENE   ot = S, oa = provincia dell'unità sostenuta, ob = provincia in cui la si sostiene
##              (uguale a oa per il sostegno a restare ferma)
##   CONVOGLIA  ot = C, oa = provincia dell'armata, ob = provincia di sbarco

const H := 0
const M := 1
const S := 2
const C := 3

var ot := PackedInt32Array()
var oa := PackedInt32Array()
var ob := PackedInt32Array()

# risultati
var esito := PackedByteArray()        # 1 = l'ordine riesce (per FERMA: 1)
var nullo := PackedByteArray()        # 1 = ordine impossibile o senza riscontro (vale come FERMA)
var sloggiata := PackedInt32Array()   # provincia dell'attaccante che scaccia l'unità, -1 se resta
var conteso := PackedByteArray()      # 1 = nella provincia c'è stato uno stallo (non ci si ritira)
var via_mare := PackedByteArray()     # 1 = la mossa è per convoglio
var senza_rotta := PackedByteArray()  # 1 = mossa per convoglio fallita perché il convoglio non c'è

var _st: DPState
var _md := PackedInt32Array()         # provincia di arrivo delle mosse
var _stato := PackedByteArray()       # 0 da risolvere, 1 ipotesi, 2 risolto
var _ris := PackedByteArray()
var _dip := PackedInt32Array()
var _primo_verso := PackedInt32Array()
var _succ_verso := PackedInt32Array()
var _primo_sup := PackedInt32Array()
var _succ_sup := PackedInt32Array()
var _coda := PackedInt32Array()
var _visto := PackedByteArray()
var _in_pila := PackedByteArray()
var _toccati := PackedInt32Array()


func _init() -> void:
	var n := DPMap.N_PROV
	for a in [ot, oa, ob, sloggiata, _md, _primo_verso, _succ_verso, _primo_sup, _succ_sup]:
		a.resize(n)
	for a in [esito, nullo, conteso, via_mare, senza_rotta, _stato, _ris, _visto, _in_pila]:
		a.resize(n)
	_coda.resize(n)
	pulisci()


## Tutti gli ordini tornano a FERMA.
func pulisci() -> void:
	ot.fill(H)
	oa.fill(-1)
	ob.fill(-1)


func ordina(prov: int, t: int, a := -1, b := -1) -> void:
	ot[prov] = t
	oa[prov] = a
	ob[prov] = b


## Carica gli ordini da un dizionario {provincia: [tipo, a, b]}.
func carica(ordini: Dictionary) -> void:
	for k in ordini:
		var o: Array = ordini[k]
		var p := int(k)
		ot[p] = int(o[0])
		oa[p] = int(o[1]) if o.size() > 1 else -1
		ob[p] = int(o[2]) if o.size() > 2 else -1


## Risolve la fase di movimento sulla posizione data (che non viene modificata).
func risolvi(st: DPState) -> void:
	_st = st
	var n := DPMap.N_PROV
	nullo.fill(0)
	via_mare.fill(0)
	senza_rotta.fill(0)
	_primo_verso.fill(-1)
	_primo_sup.fill(-1)
	_stato.fill(0)
	_ris.fill(0)
	_md.fill(-1)
	_dip.resize(0)
	_toccati.resize(0)
	_in_pila.fill(0)
	var up := st.up
	var ut := st.ut
	var ul := st.ul
	# 1. mosse
	for i in n:
		if up[i] < 0:
			ot[i] = H
			continue
		if ot[i] != M:
			continue
		var a := oa[i]
		if a < 0 or a >= DPMap.N_LOC:
			_annulla(i)
			continue
		var d := DPMap.loc_prov[a]
		if d == i:
			_annulla(i)
			continue
		if ut[i] == 0:
			oa[i] = d
			var terra_ok := (DPMap.adj_a[i] as PackedInt32Array).has(d)
			var mare_ok := DPMap.tipo[i] == DPMap.COSTA and DPMap.tipo[d] == DPMap.COSTA
			if not terra_ok and not mare_ok:
				_annulla(i)
				continue
			if not terra_ok:
				# senza una catena di flotte fra partenza e arrivo l'ordine è impossibile
				if not _catena_possibile(i, d):
					_annulla(i)
					continue
				via_mare[i] = 1
			elif mare_ok:
				# c'è anche la via di terra: si va per mare solo se l'ordine lo chiede («via convoglio»)
				# o se una flotta della stessa potenza fa parte di una rotta completa di convogli ordinati
				if ob[i] == 1:
					if not _catena_possibile(i, d):
						_annulla(i)
						continue
					if _rotta_ordinata(i, d, false):
						via_mare[i] = 1
				elif _rotta_ordinata(i, d, true):
					via_mare[i] = 1
			elif ob[i] == 1:
				_annulla(i)
				continue
			_md[i] = d
		else:
			if not (DPMap.adj_f[ul[i]] as PackedInt32Array).has(a):
				# costa non indicata o sbagliata: se l'approdo possibile è uno solo si usa quello
				var ap := DPMap.approdi(ul[i], d)
				if ap.size() == 1:
					oa[i] = ap[0]
				else:
					_annulla(i)
					continue
			_md[i] = d
	# 2. convogli
	for i in n:
		if up[i] < 0 or ot[i] != C:
			continue
		var a := oa[i]
		var b := ob[i]
		if ut[i] != 1 or DPMap.tipo[i] != DPMap.MARE or a < 0 or b < 0 or a >= n or b >= n \
				or up[a] < 0 or ut[a] != 0 or ot[a] != M or _md[a] != b or via_mare[a] == 0:
			_annulla(i)
	# 3. sostegni
	for i in n:
		if up[i] < 0 or ot[i] != S:
			continue
		var a := oa[i]
		var b := ob[i]
		if a < 0 or b < 0 or a >= n or b >= n or a == i or up[a] < 0 or not DPMap.tocca(ut[i], ul[i], b):
			_annulla(i)
			continue
		if a == b:
			if ot[a] == M:
				_annulla(i)
				continue
		else:
			if ot[a] != M or _md[a] != b:
				_annulla(i)
				continue
		_succ_sup[i] = _primo_sup[a]
		_primo_sup[a] = i
	for i in n:
		if up[i] >= 0 and ot[i] == M:
			var d := _md[i]
			_succ_verso[i] = _primo_verso[d]
			_primo_verso[d] = i
	# 4. risoluzione
	for i in n:
		if up[i] >= 0 and ot[i] != H:
			_risolvi(i)
	for i in n:
		esito[i] = 1
		if up[i] >= 0 and ot[i] != H:
			esito[i] = _ris[i]
			if ot[i] == M and via_mare[i] == 1 and not _rotta(i):
				senza_rotta[i] = 1
	# 5. unità scacciate e province contese
	sloggiata.fill(-1)
	conteso.fill(0)
	for d in n:
		var k := _primo_verso[d]
		var tentativi := 0
		var entrato := -1
		while k >= 0:
			if senza_rotta[k] == 0:
				tentativi += 1
			if esito[k] == 1:
				entrato = k
			k = _succ_verso[k]
		if entrato >= 0:
			if up[d] >= 0 and not (ot[d] == M and esito[d] == 1):
				sloggiata[d] = entrato
		elif tentativi >= 2:
			var resta := up[d] >= 0 and not (ot[d] == M and esito[d] == 1)
			if not resta:
				conteso[d] = 1


func _annulla(i: int) -> void:
	ot[i] = H
	nullo[i] = 1


## Le flotte con l'ordine di convogliare l'armata i verso d formano una rotta completa?
## Con serve_propria, inoltre, almeno una flotta della potenza dell'armata deve aver dato un ordine
## di convoglio sensato (cioè trovarsi su una catena possibile di flotte): è il segno che il convoglio
## è voluto; un'altra potenza non può «rapire» un'armata che ha anche la via di terra.
func _rotta_ordinata(i: int, d: int, serve_propria: bool) -> bool:
	var da_i := _raggiunte(i, i, d, true)
	var completa := false
	for f in da_i:
		if (DPMap.adj_fp[f] as PackedInt32Array).has(d):
			completa = true
	if not completa:
		return false
	if not serve_propria:
		return true
	var pi := _raggiunte(i, i, d, false)
	var pd := _raggiunte(d, i, d, false)
	for f in pi:
		if _st.up[f] == _st.up[i] and _convoglia(f, i, d) and pd.has(f):
			return true
	return false


## Le flotte in mare raggiungibili partendo dalla provincia p passando di flotta in flotta
## (solo quelle con l'ordine «convoglia i verso d» se ordinate è vero).
func _raggiunte(p: int, i: int, d: int, ordinate: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	_visto.fill(0)
	var testa := -1
	var f := p
	while true:
		for g in DPMap.adj_fp[f]:
			if _visto[g] == 0 and DPMap.tipo[g] == DPMap.MARE and _st.up[g] >= 0 and _st.ut[g] == 1 \
					and (not ordinate or _convoglia(g, i, d)):
				_visto[g] = 1
				out.append(g)
		testa += 1
		if testa >= out.size():
			break
		f = out[testa]
	return out


func _convoglia(f: int, i: int, d: int) -> bool:
	return ot[f] == C and oa[f] == i and ob[f] == d and _st.up[f] >= 0 and _st.ut[f] == 1 and DPMap.tipo[f] == DPMap.MARE


## Esiste una catena di flotte in mare (di chiunque) che collega la provincia i alla provincia d?
func _catena_possibile(i: int, d: int) -> bool:
	_visto.fill(0)
	var testa := 0
	var fine := 0
	for f in DPMap.adj_fp[i]:
		if DPMap.tipo[f] == DPMap.MARE and _st.up[f] >= 0 and _st.ut[f] == 1 and _visto[f] == 0:
			_visto[f] = 1
			_coda[fine] = f
			fine += 1
	while testa < fine:
		var f := _coda[testa]
		testa += 1
		var vicini: PackedInt32Array = DPMap.adj_fp[f]
		if vicini.has(d):
			return true
		for g in vicini:
			if DPMap.tipo[g] == DPMap.MARE and _st.up[g] >= 0 and _st.ut[g] == 1 and _visto[g] == 0:
				_visto[g] = 1
				_coda[fine] = g
				fine += 1
	return false


func _risolvi(nr: int) -> bool:
	if _stato[nr] == 2:
		return _ris[nr] == 1
	_toccati.append(nr)
	if _stato[nr] == 1:
		if not _dip.has(nr):
			_dip.append(nr)
		return _ris[nr] == 1
	var vecchi := _dip.size()
	var t0 := _toccati.size()
	_in_pila[nr] = 1
	_ris[nr] = 0
	_stato[nr] = 1
	var primo := _giudica(nr)
	if _dip.size() == vecchi:
		# non dipende da nessuna ipotesi: è definitivo
		_in_pila[nr] = 0
		if _stato[nr] != 2:
			_ris[nr] = 1 if primo else 0
			_stato[nr] = 2
		return _ris[nr] == 1
	var proprio := false
	var antenati := PackedInt32Array()
	for k in range(vecchi, _dip.size()):
		var x := _dip[k]
		if x == nr:
			proprio = true
		elif _in_pila[x] == 1 and not antenati.has(x):
			antenati.append(x)
	if not proprio:
		# dipende dall'ipotesi di un altro ordine in corso: risultato provvisorio
		_dip.append(nr)
		_ris[nr] = 1 if primo else 0
		_in_pila[nr] = 0
		return primo
	# dipende dalla propria ipotesi: si prova anche l'ipotesi opposta
	_azzera(vecchi)
	_ris[nr] = 1
	_stato[nr] = 1
	var secondo := _giudica(nr)
	for k in range(vecchi, _dip.size()):
		var x := _dip[k]
		if x != nr and _in_pila[x] == 1 and not antenati.has(x):
			antenati.append(x)
	_azzera(vecchi)
	if primo == secondo:
		_in_pila[nr] = 0
		_ris[nr] = 1 if primo else 0
		if antenati.is_empty():
			_stato[nr] = 2
		else:
			# vale solo finché valgono le ipotesi degli ordini più in alto
			_stato[nr] = 1
			for x in antenati:
				if not _dip.has(x):
					_dip.append(x)
			_dip.append(nr)
		return primo
	_regola_di_riserva(nr, t0, primo, secondo)
	_in_pila[nr] = 0
	if _stato[nr] != 2:
		_stato[nr] = 0
	return _risolvi(nr)


## Dimentica i risultati provvisori nati dalle ipotesi (gli ordini ancora in corso restano ipotesi).
func _azzera(vecchi: int) -> void:
	for k in range(vecchi, _dip.size()):
		var x := _dip[k]
		if _in_pila[x] == 0:
			_stato[x] = 0
	_dip.resize(vecchi)


## Situazioni senza soluzione unica: movimento circolare (tutte le mosse dell'anello riescono)
## oppure paradosso dei convogli (regola di Szykman: i convogli coinvolti non avvengono).
func _regola_di_riserva(nr: int, t0: int, primo: bool, secondo: bool) -> void:
	var fatto := false
	if ot[nr] == M and not primo and secondo:
		var anello := PackedInt32Array([nr])
		var x := _md[nr]
		while x != nr and anello.size() <= DPMap.N_PROV:
			if _st.up[x] < 0 or ot[x] != M:
				anello.resize(0)
				break
			anello.append(x)
			x = _md[x]
		if anello.size() >= 2 and x == nr:
			for k in anello:
				_ris[k] = 1
				_stato[k] = 2
			fatto = true
	if not fatto:
		if ot[nr] == C:
			_ris[nr] = 0
			_stato[nr] = 2
			fatto = true
		for k in range(t0, _toccati.size()):
			var x := _toccati[k]
			if ot[x] == C and _stato[x] != 2:
				_ris[x] = 0
				_stato[x] = 2
				fatto = true
	if not fatto:
		_ris[nr] = 0
		_stato[nr] = 2
	_toccati.resize(t0)


func _giudica(nr: int) -> bool:
	match ot[nr]:
		M:
			if via_mare[nr] == 1 and not _rotta(nr):
				return false
			var d := _md[nr]
			var att := _attacco(nr)
			if _testa_a_testa(nr):
				if att <= _difesa(d):
					return false
			elif att <= _tenuta(d):
				return false
			var k := _primo_verso[d]
			while k >= 0:
				if k != nr and att <= _impedimento(k):
					return false
				k = _succ_verso[k]
			return true
		S:
			return not _tagliato(nr)
		C:
			var k := _primo_verso[nr]
			while k >= 0:
				if _risolvi(k):
					return false
				k = _succ_verso[k]
			return true
	return true


func _testa_a_testa(nr: int) -> bool:
	var d := _md[nr]
	return _st.up[d] >= 0 and ot[d] == M and _md[d] == nr and via_mare[d] == 0 and via_mare[nr] == 0


## La mossa per convoglio ha una catena di flotte che la porta a destinazione?
func _rotta(nr: int) -> bool:
	var d := _md[nr]
	_visto.fill(0)
	var testa := 0
	var fine := 0
	for f in DPMap.adj_fp[nr]:
		if DPMap.tipo[f] == DPMap.MARE and _visto[f] == 0 and ot[f] == C and oa[f] == nr and ob[f] == d and _st.up[f] >= 0:
			_visto[f] = 1
			if _risolvi(f):
				_coda[fine] = f
				fine += 1
	while testa < fine:
		var f := _coda[testa]
		testa += 1
		var vicini: PackedInt32Array = DPMap.adj_fp[f]
		if vicini.has(d):
			return true
		for g in vicini:
			if DPMap.tipo[g] == DPMap.MARE and _visto[g] == 0 and ot[g] == C and oa[g] == nr and ob[g] == d and _st.up[g] >= 0:
				_visto[g] = 1
				if _risolvi(g):
					_coda[fine] = g
					fine += 1
	return false


func _sostegni(nr: int, escludi: int) -> int:
	var c := 0
	var s := _primo_sup[nr]
	var d := _md[nr] if ot[nr] == M else nr
	while s >= 0:
		if ob[s] == d and (escludi < 0 or _st.up[s] != escludi) and _risolvi(s):
			c += 1
		s = _succ_sup[s]
	return c


func _tenuta(d: int) -> int:
	if _st.up[d] < 0:
		return 0
	if ot[d] == M:
		return 0 if _risolvi(d) else 1
	return 1 + _sostegni(d, -1)


func _attacco(nr: int) -> int:
	if via_mare[nr] == 1 and not _rotta(nr):
		return 0
	var d := _md[nr]
	var contro := -1
	if _st.up[d] >= 0:
		var parte := ot[d] == M and not _testa_a_testa(nr) and _risolvi(d)
		if not parte:
			if _st.up[d] == _st.up[nr]:
				return 0
			contro = _st.up[d]
	return 1 + _sostegni(nr, contro)


func _difesa(nr: int) -> int:
	return 1 + _sostegni(nr, -1)


func _impedimento(nr: int) -> int:
	if via_mare[nr] == 1 and not _rotta(nr):
		return 0
	if _testa_a_testa(nr) and _risolvi(_md[nr]):
		return 0
	return 1 + _sostegni(nr, -1)


func _tagliato(s: int) -> bool:
	var bersaglio := ob[s]
	var k := _primo_verso[s]
	while k >= 0:
		if _st.up[k] != _st.up[s]:
			if via_mare[k] == 0 or _rotta(k):
				if k == bersaglio:
					if _risolvi(k):
						return true
				else:
					return true
		k = _succ_verso[k]
	return false


## La posizione dopo i movimenti (senza le unità scacciate) e l'elenco delle ritirate:
## [{prov, p, t, loc, opzioni}] dove opzioni sono le località in cui l'unità può ritirarsi.
func applica(st: DPState) -> Dictionary:
	var n := DPMap.N_PROV
	var nuovo := st.clone()
	for i in n:
		if st.up[i] >= 0 and (sloggiata[i] >= 0 or (ot[i] == M and esito[i] == 1)):
			nuovo.togli(i)
	for i in n:
		if st.up[i] >= 0 and ot[i] == M and esito[i] == 1:
			nuovo.metti(st.up[i], st.ut[i], oa[i])
	var rit := []
	for i in n:
		if sloggiata[i] < 0:
			continue
		var att := sloggiata[i]
		var opz := PackedInt32Array()
		for l in DPMap.destinazioni(st.ut[i], st.ul[i]):
			var q := DPMap.loc_prov[l]
			if nuovo.up[q] >= 0 or conteso[q] == 1:
				continue
			if q == att and via_mare[att] == 0:
				continue
			opz.append(l)
		rit.append({"prov": i, "p": st.up[i], "t": st.ut[i], "loc": st.ul[i], "opzioni": opz})
	return {"stato": nuovo, "ritirate": rit}


## Risolve le ritirate. scelte: {provincia: località, oppure -1 per sciogliere}. Due unità che si
## ritirano nella stessa provincia vengono sciolte entrambe. Restituisce {provincia: esito} con
## esito = località raggiunta oppure -1.
static func risolvi_ritirate(st: DPState, ritirate: Array, scelte: Dictionary) -> Dictionary:
	var arrivi := {}
	var out := {}
	for r in ritirate:
		var l := int(scelte.get(r["prov"], scelte.get(str(r["prov"]), -1)))
		if l >= 0 and not (r["opzioni"] as PackedInt32Array).has(l):
			l = -1
		out[r["prov"]] = l
		if l >= 0:
			var q := DPMap.loc_prov[l]
			arrivi[q] = arrivi.get(q, 0) + 1
	for r in ritirate:
		var l: int = out[r["prov"]]
		if l >= 0 and arrivi[DPMap.loc_prov[l]] > 1:
			out[r["prov"]] = -1
	for r in ritirate:
		var l: int = out[r["prov"]]
		if l >= 0:
			st.metti(r["p"], r["t"], l)
	return out

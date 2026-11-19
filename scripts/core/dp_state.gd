class_name DPState
extends RefCounted
## Una posizione sulla mappa: unità (indicizzate per provincia) e proprietari dei centri.

var up := PackedInt32Array()   # potenza dell'unità nella provincia, -1 se vuota
var ut := PackedInt32Array()   # tipo: 0 armata, 1 flotta
var ul := PackedInt32Array()   # località precisa (costa per le flotte)
var sc := PackedInt32Array()   # proprietario del centro, -1 neutrale o non centro


func _init() -> void:
	up.resize(DPMap.N_PROV)
	ut.resize(DPMap.N_PROV)
	ul.resize(DPMap.N_PROV)
	sc.resize(DPMap.N_PROV)
	up.fill(-1)
	ut.fill(0)
	ul.fill(-1)
	sc.fill(-1)


static func iniziale() -> DPState:
	DPMap.ensure()
	var s := DPState.new()
	for u in DPMap.iniziali:
		s.metti(u[0], u[1], u[2])
	for c in DPMap.centri:
		s.sc[c] = DPMap.casa_centro[c]
	return s


func clone() -> DPState:
	var s := DPState.new()
	s.up = up.duplicate()
	s.ut = ut.duplicate()
	s.ul = ul.duplicate()
	s.sc = sc.duplicate()
	return s


func metti(p: int, t: int, loc: int) -> void:
	var pr := DPMap.loc_prov[loc]
	up[pr] = p
	ut[pr] = t
	ul[pr] = loc


func togli(pr: int) -> void:
	up[pr] = -1
	ul[pr] = -1


func unita_di(p: int) -> PackedInt32Array:
	var o := PackedInt32Array()
	for i in DPMap.N_PROV:
		if up[i] == p:
			o.append(i)
	return o


func n_unita(p: int) -> int:
	var n := 0
	for i in DPMap.N_PROV:
		if up[i] == p:
			n += 1
	return n


func n_centri(p: int) -> int:
	var n := 0
	for c in DPMap.centri:
		if sc[c] == p:
			n += 1
	return n


func centri_di(p: int) -> PackedInt32Array:
	var o := PackedInt32Array()
	for c in DPMap.centri:
		if sc[c] == p:
			o.append(c)
	return o


func conta_centri() -> PackedInt32Array:
	var o := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	for c in DPMap.centri:
		if sc[c] >= 0:
			o[sc[c]] += 1
	return o


func conta_unita() -> PackedInt32Array:
	var o := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	for i in DPMap.N_PROV:
		if up[i] >= 0:
			o[up[i]] += 1
	return o


## I centri passano a chi li occupa (alla fine dell'autunno).
func aggiorna_centri() -> void:
	for c in DPMap.centri:
		if up[c] >= 0:
			sc[c] = up[c]


func to_dict() -> Dictionary:
	var u := []
	for i in DPMap.N_PROV:
		if up[i] >= 0:
			u.append([up[i], ut[i], ul[i]])
	return {"u": u, "sc": Array(sc)}


static func from_dict(d: Dictionary) -> DPState:
	DPMap.ensure()
	var s := DPState.new()
	for u in d.get("u", []):
		s.metti(int(u[0]), int(u[1]), int(u[2]))
	var a: Array = d.get("sc", [])
	for i in mini(a.size(), DPMap.N_PROV):
		s.sc[i] = int(a[i])
	return s

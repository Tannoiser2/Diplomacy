class_name DPMap
extends RefCounted
## La mappa standard di Diplomacy: 75 province (più le 6 coste distinte di Bulgaria, Spagna e
## San Pietroburgo), adiacenze per armate e flotte, centri di rifornimento e schieramento del 1901.
## I dati stanno in data/mappa.json (costruito da tools/costruisci_mappa.py).
##
## Una «località» (loc) è un numero: 0..74 sono le province (in ordine alfabetico di sigla),
## 75..80 le coste. Le armate stanno sempre su una provincia; le flotte, nelle tre province con
## due coste, stanno su una costa precisa.

const N_PROV := 75
const N_LOC := 81
const TERRA := 0   # provincia interna: solo armate
const COSTA := 1   # provincia costiera: armate e flotte
const MARE := 2    # solo flotte

const POTENZE := ["Austria-Ungheria", "Inghilterra", "Francia", "Germania", "Italia", "Russia", "Turchia"]
const POTENZE_BREVI := ["Austria", "Inghilterra", "Francia", "Germania", "Italia", "Russia", "Turchia"]
const AGGETTIVI := ["austriaco", "inglese", "francese", "tedesco", "italiano", "russo", "turco"]
const SIGLE_POT := ["A", "I", "F", "G", "It", "R", "T"]
const CAPI := ["l'Imperatore", "il Re d'Inghilterra", "il Presidente", "il Kaiser", "il Re d'Italia", "lo Zar", "il Sultano"]
const CAPITALI := ["Vienna", "Londra", "Parigi", "Berlino", "Roma", "San Pietroburgo", "Costantinopoli"]
## Colori delle potenze (pedine e tinta dei territori).
const COLORI := [Color("#b8322c"), Color("#2b4a9c"), Color("#4f9fd0"), Color("#4a4a4f"), Color("#3d8c40"), Color("#e9e4dc"), Color("#d8a520")]
const COLORI_TESTO := [Color("#ff8a80"), Color("#8fb0ff"), Color("#9fd6ff"), Color("#c9c9d2"), Color("#8fe090"), Color("#ffffff"), Color("#ffd75a")]

static var pronta := false
## false = la mappa ridisegnata in italiano, true = il tabellone originale steso sul rilievo.
## Cambia soltanto dove stanno le cose sulla carta (pedine, stelle, misure), non le regole.
static var reale := false
static var _posizioni := {}             # per genere di mappa: {larghezza, altezza, pedina, stella, etichetta}
const FILE_OPZIONI := "user://diplomacy_opzioni.cfg"
static var larghezza := 1835.0
static var altezza := 1360.0
static var sigla: Array = []            # per loc
static var nome: Array = []             # per provincia
static var tipo := PackedInt32Array()   # per provincia
static var loc_prov := PackedInt32Array()
static var costa_nome: Array = []       # per loc ("" oppure "NC"…)
static var coste_di: Array = []         # per provincia: elenco delle loc costa (vuoto se una sola costa)
static var adj_a: Array = []            # per provincia: province raggiungibili da un'armata
static var adj_f: Array = []            # per loc: loc raggiungibili da una flotta
static var adj_fp: Array = []           # per provincia: province raggiungibili da una flotta (qualsiasi costa)
static var adj_tutte: Array = []        # per provincia: tutte le province confinanti (armate o flotte)
static var centro := PackedByteArray()  # per provincia
static var centri := PackedInt32Array()
static var casa_centro := PackedInt32Array()  # potenza di casa del centro, -1
static var casa := PackedInt32Array()         # potenza di casa della provincia (anche senza centro), -1
static var case_di: Array = []          # per potenza: i centri di casa
static var pos_pedina: Array = []       # per loc: Vector2 sulla mappa
static var pos_stella: Array = []       # per provincia
static var pos_etichetta: Array = []
static var iniziali: Array = []         # [potenza, tipo, loc]
static var per_sigla := {}
static var dist_a: Array = []           # distanze fra province per un'armata (99 = irraggiungibile)
static var dist_f: Array = []           # distanze fra province per una flotta
static var dist_q: Array = []           # distanze «qualsiasi unità»


static func ensure() -> void:
	if pronta:
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mappa.json"))
	larghezza = float(d["larghezza"])
	altezza = float(d["altezza"])
	sigla.resize(N_LOC)
	nome.resize(N_PROV)
	tipo.resize(N_PROV)
	loc_prov.resize(N_LOC)
	costa_nome.resize(N_LOC)
	coste_di.resize(N_PROV)
	adj_a.resize(N_PROV)
	adj_f.resize(N_LOC)
	adj_fp.resize(N_PROV)
	adj_tutte.resize(N_PROV)
	centro.resize(N_PROV)
	casa_centro.resize(N_PROV)
	casa.resize(N_PROV)
	pos_pedina.resize(N_LOC)
	pos_stella.resize(N_PROV)
	pos_etichetta.resize(N_PROV)
	for p in 7:
		case_di.append(PackedInt32Array())
	var tipi := {"terra": TERRA, "costa": COSTA, "mare": MARE}
	for i in N_PROV:
		var pr: Dictionary = d["province"][i]
		sigla[i] = pr["sigla"]
		per_sigla[pr["sigla"]] = i
		nome[i] = pr["nome"]
		tipo[i] = tipi[pr["tipo"]]
		loc_prov[i] = i
		costa_nome[i] = ""
		coste_di[i] = PackedInt32Array()
		adj_a[i] = _ints(pr["adj_a"])
		adj_f[i] = _ints(pr["adj_f"])
		centro[i] = 1 if pr["centro"] else 0
		if pr["centro"]:
			centri.append(i)
		casa_centro[i] = int(pr["casa_centro"])
		casa[i] = int(pr["casa"])
		if casa_centro[i] >= 0:
			case_di[casa_centro[i]].append(i)
		pos_pedina[i] = Vector2(pr["pedina"][0], pr["pedina"][1])
		pos_stella[i] = Vector2(pr["stella"][0], pr["stella"][1]) if pr["stella"] != null else pos_pedina[i]
		pos_etichetta[i] = Vector2(pr["etichetta"][0], pr["etichetta"][1])
	for k: int in d["coste"].size():
		var c: Dictionary = d["coste"][k]
		var l: int = N_PROV + k
		sigla[l] = c["sigla"]
		per_sigla[c["sigla"]] = l
		loc_prov[l] = int(c["provincia"])
		costa_nome[l] = c["costa"]
		coste_di[loc_prov[l]].append(l)
		adj_f[l] = _ints(c["adj_f"])
		pos_pedina[l] = Vector2(c["pedina"][0], c["pedina"][1])
	for i in N_PROV:
		var s := {}
		for l in N_LOC:
			if loc_prov[l] == i:
				for t in adj_f[l]:
					s[loc_prov[t]] = true
		var a := PackedInt32Array()
		for k in s:
			a.append(k)
		a.sort()
		adj_fp[i] = a
		var tt := {}
		for k in a:
			tt[k] = true
		for k in adj_a[i]:
			tt[k] = true
		var b := PackedInt32Array()
		for k in tt:
			b.append(k)
		b.sort()
		adj_tutte[i] = b
	for u in d["iniziali"]:
		iniziali.append([int(u[0]), int(u[1]), int(u[2])])
	dist_a = _distanze(adj_a)
	dist_f = _distanze(adj_fp)
	dist_q = _distanze(adj_tutte)
	_posizioni[false] = {"larghezza": larghezza, "altezza": altezza, "pedina": pos_pedina.duplicate(),
		"stella": pos_stella.duplicate(), "etichetta": pos_etichetta.duplicate()}
	pronta = true


## Sceglie su quale carta si gioca: quella ridisegnata o il tabellone originale.
static func usa(r: bool) -> void:
	ensure()
	if not _posizioni.has(r):
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mappa_reale.json"))
		var pp := []
		for v in d["pedina"]:
			pp.append(Vector2(v[0], v[1]))
		var ss := []
		var ee := []
		for i in N_PROV:
			var v = d["stella"][i]
			ss.append(Vector2(v[0], v[1]) if v != null else pp[i])
			ee.append(Vector2(d["etichetta"][i][0], d["etichetta"][i][1]))
		_posizioni[r] = {"larghezza": float(d["larghezza"]), "altezza": float(d["altezza"]), "pedina": pp, "stella": ss, "etichetta": ee}
	var q: Dictionary = _posizioni[r]
	reale = r
	larghezza = q["larghezza"]
	altezza = q["altezza"]
	pos_pedina = q["pedina"]
	pos_stella = q["stella"]
	pos_etichetta = q["etichetta"]


## La carta preferita dal giocatore (ricordata sul suo dispositivo): di norma il tabellone originale.
static func preferenza() -> bool:
	var c := ConfigFile.new()
	if c.load(FILE_OPZIONI) != OK:
		return true
	return bool(c.get_value("mappa", "reale", true))


static func salva_preferenza(r: bool) -> void:
	var c := ConfigFile.new()
	c.load(FILE_OPZIONI)
	c.set_value("mappa", "reale", r)
	c.save(FILE_OPZIONI)


static func _ints(a: Array) -> PackedInt32Array:
	var o := PackedInt32Array()
	for v in a:
		o.append(int(v))
	return o


static func _distanze(adj: Array) -> Array:
	var out := []
	for s in N_PROV:
		var d := PackedInt32Array()
		d.resize(N_PROV)
		d.fill(99)
		d[s] = 0
		var coda := [s]
		var h := 0
		while h < coda.size():
			var x: int = coda[h]
			h += 1
			for y in adj[x]:
				if d[y] == 99:
					d[y] = d[x] + 1
					coda.append(y)
		out.append(d)
	return out


## Nome leggibile di una località: «Spagna (costa nord)».
static func nome_loc(l: int) -> String:
	var n: String = nome[loc_prov[l]]
	if costa_nome[l] != "":
		n += " (%s)" % nome_costa(costa_nome[l])
	return n


static func nome_costa(c: String) -> String:
	match c:
		"NC": return "costa nord"
		"SC": return "costa sud"
		"EC": return "costa est"
	return c


## Un'unità di tipo t (0 armata, 1 flotta) in loc può muovere in dest (loc)?
static func puo_muovere(t: int, da: int, a: int) -> bool:
	if t == 0:
		return a < N_PROV and da < N_PROV and (adj_a[da] as PackedInt32Array).has(a)
	return (adj_f[da] as PackedInt32Array).has(a)


## Un'unità di tipo t in loc può raggiungere (e quindi sostenere verso) la provincia p?
static func tocca(t: int, da: int, p: int) -> bool:
	if t == 0:
		return (adj_a[loc_prov[da]] as PackedInt32Array).has(p)
	for l in adj_f[da]:
		if loc_prov[l] == p:
			return true
	return false


## Le destinazioni possibili (loc) di un'unità.
static func destinazioni(t: int, da: int) -> PackedInt32Array:
	return adj_a[da] if t == 0 else adj_f[da]


## Località in cui una flotta proveniente da «da» arriva nella provincia p (una sola se la costa è obbligata).
static func approdi(da: int, p: int) -> PackedInt32Array:
	var o := PackedInt32Array()
	for l in adj_f[da]:
		if loc_prov[l] == p:
			o.append(l)
	return o

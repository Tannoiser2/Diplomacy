class_name DPQr
## Codice QR per invitare i telefoni nella stanza: versioni 1-5, correzione bassa (L), dati a byte.
## Basta per un indirizzo fino a 106 caratteri; un solo blocco di correzione, niente tabelle.

const DATI := [0, 19, 34, 55, 80, 108]      # parole di dati per versione (livello L)
const CORR := [0, 7, 10, 15, 20, 26]        # parole di correzione


## La matrice del codice: righe di byte (1 = scuro). Vuota se il testo è troppo lungo.
static func matrice(testo: String) -> Array:
	var bytes := testo.to_utf8_buffer()
	var v := 0
	for k in range(1, 6):
		if bytes.size() + 2 <= DATI[k]:
			v = k
			break
	if v == 0:
		return []
	# flusso di bit: modo byte, lunghezza, dati, terminatore, riempimento
	var bit := PackedByteArray()
	_metti(bit, 4, 4)
	_metti(bit, bytes.size(), 8)
	for b in bytes:
		_metti(bit, b, 8)
	var cap: int = DATI[v] * 8
	_metti(bit, 0, mini(4, cap - bit.size()))
	while bit.size() % 8 != 0:
		bit.append(0)
	var parole := PackedByteArray()
	for i in range(0, bit.size(), 8):
		var x := 0
		for j in 8:
			x = (x << 1) | bit[i + j]
		parole.append(x)
	var pad := 0xEC
	while parole.size() < DATI[v]:
		parole.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	parole.append_array(_reed_solomon(parole, CORR[v]))
	# moduli fissi
	var n := 17 + 4 * v
	var m := []
	var fisso := []
	for y in n:
		var r := PackedByteArray()
		r.resize(n)
		m.append(r)
		var f := PackedByteArray()
		f.resize(n)
		fisso.append(f)
	for i in n:
		_fissa(m, fisso, 6, i, i % 2 == 0)
		_fissa(m, fisso, i, 6, i % 2 == 0)
	for c in [[3, 3], [n - 4, 3], [3, n - 4]]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c[0] + dx
				var y: int = c[1] + dy
				if x >= 0 and x < n and y >= 0 and y < n:
					var d := maxi(absi(dx), absi(dy))
					_fissa(m, fisso, x, y, d != 2 and d != 4)
	if v >= 2:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				_fissa(m, fisso, n - 7 + dx, n - 7 + dy, maxi(absi(dx), absi(dy)) != 1)
	_formato(m, fisso, 0)       # riserva i posti delle informazioni di formato
	# dati a zig-zag dal basso a destra
	var i := 0
	var tot := parole.size() * 8
	var destra := n - 1
	while destra >= 1:
		if destra == 6:
			destra = 5
		for vert in n:
			for j in 2:
				var x := destra - j
				var su := ((destra + 1) & 2) == 0
				var y := n - 1 - vert if su else vert
				if fisso[y][x] == 0 and i < tot:
					m[y][x] = (parole[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		destra -= 2
	# la maschera migliore
	var meglio := -1
	var minimo := 1 << 30
	for k in 8:
		_maschera(m, fisso, k)
		_formato(m, fisso, k)
		var p := _penalita(m)
		if p < minimo:
			minimo = p
			meglio = k
		_maschera(m, fisso, k)
	_maschera(m, fisso, meglio)
	_formato(m, fisso, meglio)
	return m


## Il codice come immagine: scuro su chiaro, con il margine bianco che serve ai lettori.
static func texture(testo: String, punti := 8) -> ImageTexture:
	var m := matrice(testo)
	if m.is_empty():
		return null
	var n := m.size()
	var lato := (n + 8) * punti
	var img := Image.create(lato, lato, false, Image.FORMAT_RGB8)
	img.fill(Color("#f4ecd8"))
	var scuro := Color("#1c130c")
	for y in n:
		for x in n:
			if m[y][x] == 1:
				img.fill_rect(Rect2i((x + 4) * punti, (y + 4) * punti, punti, punti), scuro)
	return ImageTexture.create_from_image(img)


static func _metti(bit: PackedByteArray, valore: int, quanti: int) -> void:
	for i in range(quanti - 1, -1, -1):
		bit.append((valore >> i) & 1)


static func _fissa(m: Array, fisso: Array, x: int, y: int, scuro: bool) -> void:
	m[y][x] = 1 if scuro else 0
	fisso[y][x] = 1


static func _per(a: int, b: int) -> int:
	# prodotto nel campo di Galois a 256 elementi (polinomio 0x11D)
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((b >> i) & 1) * a
	return z & 0xFF


static func _reed_solomon(dati: PackedByteArray, grado: int) -> PackedByteArray:
	var div := PackedByteArray()
	div.resize(grado)
	div[grado - 1] = 1
	var radice := 1
	for i in grado:
		for j in grado:
			div[j] = _per(div[j], radice)
			if j + 1 < grado:
				div[j] ^= div[j + 1]
		radice = _per(radice, 2)
	var resto := PackedByteArray()
	resto.resize(grado)
	for b in dati:
		var f: int = b ^ resto[0]
		for j in grado - 1:
			resto[j] = resto[j + 1]
		resto[grado - 1] = 0
		for j in grado:
			resto[j] ^= _per(div[j], f)
	return resto


static func _formato(m: Array, fisso: Array, maschera: int) -> void:
	var dati := (1 << 3) | maschera            # livello L = 01
	var r := dati
	for i in 10:
		r = (r << 1) ^ ((r >> 9) * 0x537)
	var bits := ((dati << 10) | r) ^ 0x5412
	var n := m.size()
	for i in 6:
		_fissa(m, fisso, 8, i, (bits >> i) & 1 == 1)
	_fissa(m, fisso, 8, 7, (bits >> 6) & 1 == 1)
	_fissa(m, fisso, 8, 8, (bits >> 7) & 1 == 1)
	_fissa(m, fisso, 7, 8, (bits >> 8) & 1 == 1)
	for i in range(9, 15):
		_fissa(m, fisso, 14 - i, 8, (bits >> i) & 1 == 1)
	for i in 8:
		_fissa(m, fisso, n - 1 - i, 8, (bits >> i) & 1 == 1)
	for i in range(8, 15):
		_fissa(m, fisso, 8, n - 15 + i, (bits >> i) & 1 == 1)
	_fissa(m, fisso, 8, n - 8, true)


static func _maschera(m: Array, fisso: Array, k: int) -> void:
	var n := m.size()
	for y in n:
		for x in n:
			if fisso[y][x] == 1:
				continue
			var inv := false
			match k:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				m[y][x] ^= 1


static func _penalita(m: Array) -> int:
	var n := m.size()
	var p := 0
	var scuri := 0
	for y in n:
		var fila_r := 1
		var fila_c := 1
		for x in n:
			scuri += m[y][x]
			if x > 0:
				if m[y][x] == m[y][x - 1]:
					fila_r += 1
					if fila_r == 5:
						p += 3
					elif fila_r > 5:
						p += 1
				else:
					fila_r = 1
				if m[x][y] == m[x - 1][y]:
					fila_c += 1
					if fila_c == 5:
						p += 3
					elif fila_c > 5:
						p += 1
				else:
					fila_c = 1
			if x + 1 < n and y + 1 < n and m[y][x] == m[y][x + 1] and m[y][x] == m[y + 1][x] and m[y][x] == m[y + 1][x + 1]:
				p += 3
	p += 10 * (absi(scuri * 20 - n * n * 10) / (n * n))
	return p

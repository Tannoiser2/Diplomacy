class_name DPAperture
extends RefCounted
## Il libro delle aperture della primavera 1901.
## Ordini, nomi e frequenze d'uso vengono dalla «Library of Diplomacy Openings» della Diplomatic
## Pouch (diplom.org): per ogni potenza le aperture più giocate nelle partite catalogate.
## «contro» elenca le potenze che l'apertura minaccia: serve a sceglierla secondo gli accordi presi.
##
## Potenze: 0 Austria, 1 Inghilterra, 2 Francia, 3 Germania, 4 Italia, 5 Russia, 6 Turchia.

const LIBRO := [
	# AUSTRIA
	[
		{"nome": "Gambetto balcanico, variante di Budapest", "peso": 80, "contro": [], "o": "F TRI-ALB, A BUD-SER, A VIE-BUD"},
		{"nome": "Gambetto balcanico, variante di Trieste", "peso": 73, "contro": [], "o": "F TRI-ALB, A BUD-SER, A VIE-TRI"},
		{"nome": "Gambetto balcanico, variante di Galizia", "peso": 56, "contro": [5], "o": "F TRI-ALB, A BUD-SER, A VIE-GAL"},
		{"nome": "Gambetto balcanico, variante del Tirolo", "peso": 8, "contro": [4], "o": "F TRI-ALB, A BUD-SER, A VIE-TYR"},
		{"nome": "Riccio meridionale", "peso": 6, "contro": [4, 5], "o": "F TRI-VEN, A BUD-SER, A VIE-GAL"},
		{"nome": "Gambetto rumeno", "peso": 5, "contro": [5], "o": "F TRI-ALB, A BUD-RUM, A VIE-GAL"},
	],
	# INGHILTERRA
	[
		{"nome": "Apertura Churchill (del Nord, variante di Edimburgo)", "peso": 142, "contro": [], "o": "F EDI-NWG, F LON-NTH, A LVP-EDI"},
		{"nome": "Apertura del Nord, variante dello Yorkshire", "peso": 95, "contro": [], "o": "F EDI-NWG, F LON-NTH, A LVP-YOR"},
		{"nome": "Apertura del Sud, variante dello Yorkshire", "peso": 46, "contro": [2], "o": "F EDI-NTH, F LON-ENG, A LVP-YOR"},
		{"nome": "Apertura del Galles (del Sud)", "peso": 26, "contro": [2], "o": "F EDI-NTH, F LON-ENG, A LVP-WAL"},
	],
	# FRANCIA
	[
		{"nome": "Apertura Maginot", "peso": 52, "contro": [], "diffida": [3], "o": "F BRE-MAO, A MAR S A PAR-BUR, A PAR-BUR"},
		{"nome": "Apertura di Borgogna", "peso": 44, "contro": [], "o": "F BRE-MAO, A MAR-SPA, A PAR-BUR"},
		{"nome": "Apertura di Piccardia", "peso": 27, "contro": [], "o": "F BRE-MAO, A MAR-SPA, A PAR-PIC"},
		{"nome": "Attacco inglese", "peso": 8, "contro": [1], "o": "F BRE-ENG, A MAR-SPA, A PAR-PIC"},
		{"nome": "Apertura di Guascogna", "peso": 6, "contro": [], "o": "F BRE-MAO, A MAR-SPA, A PAR-GAS"},
		{"nome": "Sistema del Piemonte", "peso": 4, "contro": [4], "o": "F BRE-MAO, A MAR-PIE, A PAR-BUR"},
	],
	# GERMANIA
	[
		{"nome": "Blitzkrieg, variante olandese", "peso": 96, "contro": [], "o": "F KIE-HOL, A BER-KIE, A MUN-RUH"},
		{"nome": "Blitzkrieg, variante danese", "peso": 74, "contro": [], "o": "F KIE-DEN, A BER-KIE, A MUN-RUH"},
		{"nome": "Attacco in Borgogna, variante olandese", "peso": 29, "contro": [2], "o": "F KIE-HOL, A BER-KIE, A MUN-BUR"},
		{"nome": "Anschluss", "peso": 23, "contro": [], "o": "F KIE-DEN, A BER-KIE, A MUN H"},
		{"nome": "Attacco in Borgogna, variante danese", "peso": 19, "contro": [2], "o": "F KIE-DEN, A BER-KIE, A MUN-BUR"},
		{"nome": "Apertura Barbarossa", "peso": 5, "contro": [5], "o": "F KIE-DEN, A BER-PRU, A MUN-SIL"},
	],
	# ITALIA
	[
		{"nome": "Attacco al Tirolo", "peso": 41, "contro": [0], "o": "A ROM-VEN, F NAP-ION, A VEN-TYR"},
		{"nome": "Lepanto", "peso": 38, "contro": [6], "o": "A ROM-APU, F NAP-ION, A VEN H"},
		{"nome": "Lepanto con il Tirolo", "peso": 31, "contro": [6], "diffida": [0], "o": "A ROM-APU, F NAP-ION, A VEN-TYR"},
		{"nome": "Pollo alpino", "peso": 28, "contro": [2], "o": "A ROM-VEN, F NAP-ION, A VEN-PIE"},
		{"nome": "Lepanto occidentale", "peso": 15, "contro": [2], "o": "A ROM-TUS, F NAP-TYS, A VEN-PIE"},
		{"nome": "Lepanto a tradimento", "peso": 12, "contro": [0], "o": "A ROM-VEN, F NAP-ION, A VEN-TRI"},
	],
	# RUSSIA
	[
		{"nome": "Sistema ucraino (attacco austriaco)", "peso": 43, "contro": [0], "o": "A MOS-UKR, A WAR-GAL, F STP/SC-BOT, F SEV-RUM"},
		{"nome": "Sistema ucraino, difesa meridionale", "peso": 40, "contro": [0, 6], "o": "A MOS-UKR, A WAR-GAL, F STP/SC-BOT, F SEV-BLA"},
		{"nome": "Sistema settentrionale (il Calamaro)", "peso": 24, "contro": [6], "diffida": [1], "o": "A MOS-STP, A WAR-UKR, F STP/SC-BOT, F SEV-BLA"},
		{"nome": "Apertura settentrionale, variante ucraina", "peso": 17, "contro": [], "diffida": [1], "o": "A MOS-STP, A WAR-UKR, F STP/SC-BOT, F SEV-RUM"},
		{"nome": "Apertura rumena", "peso": 16, "contro": [], "o": "A MOS-SEV, A WAR-UKR, F STP/SC-BOT, F SEV-RUM"},
		{"nome": "Sistema meridionale (attacco turco)", "peso": 15, "contro": [6], "o": "A MOS-SEV, A WAR-UKR, F STP/SC-BOT, F SEV-BLA"},
		{"nome": "Sistema livone", "peso": 11, "contro": [], "diffida": [3], "o": "A MOS-LVN, A WAR-UKR, F STP/SC-BOT, F SEV-RUM"},
	],
	# TURCHIA
	[
		{"nome": "Attacco russo dal Mar Nero", "peso": 111, "contro": [5], "o": "A CON-BUL, F ANK-BLA, A SMY-CON"},
		{"nome": "Apertura del Bosforo, variante di Smirne", "peso": 71, "contro": [], "o": "A CON-BUL, F ANK-CON, A SMY H"},
		{"nome": "Rullo di Crimea", "peso": 54, "contro": [5], "o": "A CON-BUL, F ANK-BLA, A SMY-ARM"},
		{"nome": "Apertura del Bosforo", "peso": 39, "contro": [], "o": "A CON-BUL, F ANK-CON, A SMY-ANK"},
		{"nome": "Bosforo, variante d'Armenia", "peso": 10, "contro": [5], "o": "A CON-BUL, F ANK-CON, A SMY-ARM"},
	],
]


## Traduce «F TRI-ALB, A BUD-SER, A MAR S A PAR-BUR» in {provincia: [tipo, a, b]}.
static func ordini(testo: String) -> Dictionary:
	DPMap.ensure()
	var out := {}
	for pezzo in testo.split(","):
		var w := pezzo.strip_edges().split(" ")
		if w.size() < 2:
			continue
		if w.size() >= 3 and w[2] == "S":
			var m := w[4].split("-")
			var u: int = DPMap.loc_prov[DPMap.per_sigla[w[1]]]
			out[u] = [DPAdj.S, DPMap.loc_prov[DPMap.per_sigla[m[0]]], DPMap.loc_prov[DPMap.per_sigla[m[1]]]]
		elif w.size() >= 3 and w[2] == "H":
			out[DPMap.loc_prov[DPMap.per_sigla[w[1]]]] = [DPAdj.H, -1, -1]
		else:
			var m := w[1].split("-")
			out[DPMap.loc_prov[DPMap.per_sigla[m[0]]]] = [DPAdj.M, DPMap.per_sigla[m[1]], 0]
	return out


## Province in cui l'apertura fa entrare delle unità.
static func entra(ord: Dictionary) -> Array:
	var o := []
	for k in ord:
		if int(ord[k][0]) == DPAdj.M:
			o.append(DPMap.loc_prov[int(ord[k][1])])
	return o

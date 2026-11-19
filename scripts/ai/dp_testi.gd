class_name DPTesti
extends RefCounted
## I testi dei dispacci diplomatici: ogni messaggio ha un tipo e dei dati, e qui diventa una nota
## in italiano nello stile delle cancellerie del 1901.

const CANCELLERIE := ["la Ballhausplatz", "il Foreign Office", "il Quai d'Orsay", "la Wilhelmstrasse", "la Consulta", "il Ponte dei Cantori", "la Sublime Porta"]
const DA_CANC := ["dalla Ballhausplatz", "dal Foreign Office", "dal Quai d'Orsay", "dalla Wilhelmstrasse", "dalla Consulta", "dal Ponte dei Cantori", "dalla Sublime Porta"]
const CON_ARTICOLO := ["l'Austria", "l'Inghilterra", "la Francia", "la Germania", "l'Italia", "la Russia", "la Turchia"]
const DELLA := ["dell'Austria", "dell'Inghilterra", "della Francia", "della Germania", "dell'Italia", "della Russia", "della Turchia"]
const ALLA := ["all'Austria", "all'Inghilterra", "alla Francia", "alla Germania", "all'Italia", "alla Russia", "alla Turchia"]

const T := {
	"alleanza": [
		"Proponiamo un'intesa contro %s: unite, le nostre forze possono spartirsi i suoi centri. Attendiamo la vostra parola.",
		"Un'alleanza fra noi contro %s gioverebbe a entrambi. Siete dei nostri?",
		"Uniamo le armi contro %s, prima che diventi troppo forte per tutti e due.",
	],
	"pace": [
		"Proponiamo un patto di non aggressione: nessuna delle nostre unità muoverà contro l'altra parte.",
		"Non abbiamo motivo di combatterci. Vi offriamo pace alle nostre frontiere.",
		"Teniamo quieto il nostro confine comune: abbiamo entrambi nemici più urgenti.",
	],
	"dmz": [
		"Proponiamo di tenere sgombra la zona di %s: né voi né noi vi faremo entrare unità.",
		"Per la reciproca tranquillità, lasciamo vuota la zona di %s.",
	],
	"chiedi_sost": [
		"Vi chiediamo di sostenere con %s la nostra %s.",
		"Un vostro sostegno sarebbe decisivo: %s a sostegno della nostra %s.",
	],
	"offri_sost": [
		"Se ordinate %s, la nostra %s vi sosterrà.",
		"Vi offriamo il sostegno della nostra %s: ordinate %s e sarà fatta.",
	],
	"chiedi_mossa": [
		"Vi chiediamo di ordinare: %s.",
		"Ci gioverebbe molto questo vostro ordine: %s.",
	],
	"info": [
		"In confidenza: %s ci ha proposto di muovere contro di voi. Guardatevi le spalle.",
		"Sappiate che %s trama ai vostri danni. Ve lo diciamo da amici.",
	],
	"pareggio": [
		"La guerra è in stallo. Proponiamo di chiudere con un pareggio fra le potenze superstiti.",
	],
	"si": [
		"D'accordo. Avete la nostra parola.",
		"Accettiamo. Così sia.",
		"Intesa conclusa: contate su di noi.",
		"La proposta ci conviene. Accettata.",
	],
	"no": [
		"Ci spiace, non possiamo accettare.",
		"Non è il momento. Decliniamo.",
		"La proposta non ci conviene.",
		"Dobbiamo rifiutare: altri impegni ce lo impediscono.",
	],
	"tradimento": [
		"Avete tradito la parola data. Non lo dimenticheremo.",
		"Così ripagate la nostra fiducia? Ne risponderete.",
		"Il vostro voltafaccia è scritto nei nostri archivi. Ogni accordo fra noi è carta straccia.",
	],
	"promessa_mancata": [
		"Avevate promesso: %s. Non è avvenuto. Ne prendiamo nota.",
		"Dov'era il vostro ordine promesso (%s)? La nostra fiducia non è infinita.",
	],
	"spiegazione": [
		"La ragion di Stato non conosce amicizie. Non c'era altra via per vincere.",
		"Nulla di personale: i vostri centri erano troppo sguarniti per resistere alla tentazione.",
		"Ogni alleanza ha una fine. La nostra è finita oggi.",
	],
	"sospetto": [
		"Notiamo le vostre unità ammassate presso %s. Vogliate spiegarci le vostre intenzioni.",
		"Le vostre forze vicino a %s ci inquietano. Un alleato non avrebbe bisogno di tenerle lì.",
	],
	"grazie": [
		"Avete tenuto fede all'accordo. La nostra amicizia ne esce rafforzata.",
		"Parola mantenuta: è così che si costruisce un'alleanza.",
	],
	"coalizione": [
		"%s è a un passo dalla vittoria. Mettiamo da parte le nostre contese e fermiamola insieme.",
		"Se %s non viene fermata adesso, la partita è finita per tutti. Tregua fra noi e fronte comune.",
	],
	"saluto": [
		"I nostri omaggi. Confidiamo in rapporti cordiali fra i nostri governi.",
		"Un nuovo secolo comincia: che trovi i nostri due Paesi in amicizia.",
	],
	"aggressione": [
		"Prendiamo atto della vostra aggressione. Avrete la guerra che cercate.",
		"Le vostre unità hanno varcato il confine. Risponderemo con le armi.",
	],
	"tregua": [
		"Questa guerra ci dissangua entrambi a vantaggio di altri. Vi proponiamo di deporre le armi.",
	],
	"disdetta": [
		"Le circostanze sono cambiate: vi comunichiamo lealmente che il patto fra noi non è più in vigore.",
		"Disdiciamo oggi, alla luce del sole, gli accordi che ci legavano. Regolatevi di conseguenza.",
	],
	"denuncia": [
		"A tutte le potenze: %s ha violato i patti firmati con noi. Chi tratta con lei sappia quanto vale la sua parola.",
	],
	"libero": [
		"Abbiamo ricevuto la vostra nota. Preferiamo proposte precise: alleanze, patti, zone sgombre, sostegni.",
	],
}


## Prima lettera maiuscola (capitalize() di Godot abbasserebbe il resto).
static func maiuscola(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


static func unita(st: DPState, prov: int) -> String:
	if prov < 0 or prov >= DPMap.N_PROV or st.up[prov] < 0:
		return "unità"
	return "%s %s" % ["A" if st.ut[prov] == 0 else "F", DPMap.nome[prov]]


static func province(lista: Array) -> String:
	var n := []
	for p in lista:
		n.append(DPMap.nome[int(p)])
	if n.size() <= 1:
		return "" if n.is_empty() else n[0]
	return ", ".join(n.slice(0, n.size() - 1)) + " e " + n[-1]


## Il testo di un messaggio. v sceglie la variante.
static func componi(m: Dictionary, st: DPState) -> String:
	var tipo: String = m["tipo"]
	var d: Dictionary = m.get("d", {})
	var v: int = int(m.get("v", 0))
	match tipo:
		"alleanza":
			return _t("alleanza", v) % CON_ARTICOLO[int(d["contro"])]
		"pace":
			return _t("tregua" if d.get("tregua", false) else "pace", v)
		"dmz":
			return _t("dmz", v) % province(d["prov"])
		"chiedi_sost":
			return _t("chiedi_sost", v) % [unita(st, int(d["u"])), _mossa(st, int(d["a"]), int(d["b"]))]
		"offri_sost":
			var mossa := _mossa(st, int(d["a"]), int(d["b"]))
			if v % 2 == 0:
				return T["offri_sost"][0] % [mossa, unita(st, int(d["u"]))]
			return T["offri_sost"][1] % [unita(st, int(d["u"])), mossa]
		"chiedi_mossa":
			return _t("chiedi_mossa", v) % DPGame.testo_ordine(st, int(d["u"]), d["o"], true)
		"info":
			return _t("info", v) % CON_ARTICOLO[int(d["su"])]
		"pareggio":
			return _t("pareggio", v)
		"risposta":
			return _t("si" if d.get("si", false) else "no", v)
		"nota":
			var k: String = d.get("k", "saluto")
			var s := _t(k, v)
			if s.contains("%s"):
				s = s % str(d.get("x", ""))
			return s
		"libero":
			return str(d.get("testo", ""))
	return ""


static func _t(k: String, v: int) -> String:
	var a: Array = T[k]
	return a[absi(v) % a.size()]


static func _mossa(st: DPState, a: int, b: int) -> String:
	if a == b:
		return "%s che tiene la posizione" % unita(st, a)
	return "%s - %s" % [unita(st, a), DPMap.nome[b]]


## Titolo breve per l'elenco dei dispacci.
static func titolo(m: Dictionary) -> String:
	match m["tipo"]:
		"alleanza": return "Proposta di alleanza contro %s" % CON_ARTICOLO[int(m["d"]["contro"])]
		"pace": return "Proposta di tregua" if m["d"].get("tregua", false) else "Patto di non aggressione"
		"dmz": return "Zona sgombra"
		"chiedi_sost": return "Richiesta di sostegno"
		"offri_sost": return "Offerta di sostegno"
		"chiedi_mossa": return "Richiesta di un ordine"
		"info": return "Informazione riservata"
		"pareggio": return "Proposta di pareggio"
		"risposta": return "Accettato" if m["d"].get("si", false) else "Rifiutato"
		"nota": return "Nota diplomatica"
		"libero": return "Messaggio"
	return "Dispaccio"


## Il messaggio chiede una risposta sì/no?
static func e_proposta(tipo: String) -> bool:
	return tipo in ["alleanza", "pace", "dmz", "chiedi_sost", "offri_sost", "chiedi_mossa", "pareggio"]

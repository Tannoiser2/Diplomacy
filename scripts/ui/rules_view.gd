extends Control
## Regole e consigli: un compendio in italiano delle regole di Diplomacy, i comandi di questa
## versione, i consigli strategici dei giocatori da torneo e le aperture più note.

var chiudi := Callable()
var testo: RichTextLabel
var capitolo := 0
var bottoni: Array = []

const CAPITOLI := [
	["Lo scopo del gioco", """[b]Europa, primavera del 1901.[/b] Sette grandi potenze - Austria-Ungheria, Inghilterra, Francia, Germania, Italia, Russia e Turchia - si contendono il continente.

Sulla mappa ci sono [b]34 centri di rifornimento[/b] (i dischi colorati). Vince chi, alla fine di un autunno, ne controlla [b]18[/b]: la maggioranza assoluta.

Non ci sono dadi né carte: tutte le unità hanno la stessa forza. Si vince [b]convincendo gli altri[/b] ad aiutarvi (o a non ostacolarvi) e scegliendo il momento giusto per tradirli. Nulla di ciò che si promette durante le trattative è vincolante.

Se nessuno riesce a prevalere, le potenze superstiti possono accordarsi per un [b]pareggio[/b]."""],
	["La mappa e le unità", """La mappa è divisa in [b]province[/b] di tre tipi:
- [b]interne[/b]: ci stanno solo le armate;
- [b]costiere[/b]: ci stanno armate e flotte;
- [b]di mare[/b]: ci stanno solo le flotte.

In ogni provincia può stare [b]una sola unità[/b]. La Svizzera è impraticabile.

[b]Armata (A)[/b]: si muove fra province di terra confinanti.
[b]Flotta (F)[/b]: si muove fra mari e coste confinanti, seguendo la linea di costa (da Roma non può andare in Puglia: sono su mari diversi).

Tre province hanno [b]due coste separate[/b]: Spagna (nord e sud), Bulgaria (est e sud) e San Pietroburgo (nord e sud). Una flotta sta su una costa precisa e da lì raggiunge solo i mari di quel lato.

Kiel, Costantinopoli e la Danimarca hanno un canale: le flotte le attraversano da un mare all'altro (in due mosse).

Ogni potenza parte con tre centri di casa e tre unità; la Russia con quattro."""],
	["L'anno di gioco", """Ogni anno ha cinque fasi:

[b]1. Primavera[/b]: trattative, poi tutti scrivono in segreto un ordine per ogni unità. Gli ordini si rivelano e si risolvono tutti insieme.
[b]2. Ritirate di primavera[/b]: le unità scacciate si ritirano o si sciolgono.
[b]3. Autunno[/b]: come la primavera.
[b]4. Ritirate d'autunno.[/b]
[b]5. Inverno[/b]: si contano i centri. Un centro passa a chi lo [b]occupa alla fine dell'autunno[/b] e resta suo anche se poi se ne va, finché un altro non lo occupa a fine autunno. Chi ha più centri che unità [b]costruisce[/b]; chi ne ha meno [b]scioglie[/b].

Si costruisce solo nei propri [b]centri di casa[/b], se sono ancora propri e liberi. Chi li ha persi tutti continua a giocare ma non può costruire."""],
	["Gli ordini", """Ogni unità riceve uno di questi ordini (senza ordini resta ferma):

[b]Ferma[/b] - l'unità tiene la posizione.

[b]Muove[/b] (A Par - Bor) - l'unità va in una provincia confinante. Muovere in una provincia occupata è un attacco.

[b]Sostiene[/b] (A Mar S A Par - Bor) - l'unità resta dov'è e aggiunge la sua forza alla mossa (o alla difesa) di un'altra unità, anche di un'altra potenza. Si può sostenere solo verso una provincia in cui si potrebbe muovere. Il sostegno a restare fermi vale per chi tiene, sostiene o convoglia; non per chi muove.

[b]Convoglia[/b] (F Nth C A Lon - Bel) - una flotta in mare trasporta un'armata da una costa a un'altra. Più flotte in mari confinanti formano una catena. L'armata deve avere l'ordine di muovere verso quella destinazione."""],
	["Come si risolvono gli scontri", """[b]La forza[/b] di una mossa o di una difesa è 1 più il numero dei sostegni validi.

- Entra chi ha [b]più forza[/b] di ogni altro pretendente e di chi difende. A parità [b]nessuno si muove[/b] (stallo): chi era lì resta.
- Due unità non possono [b]scambiarsi di posto[/b] (salvo che una viaggi per convoglio). Tre o più unità possono invece ruotare in cerchio.
- Un'unità attaccata con più forza è [b]scacciata[/b]: dovrà ritirarsi.
- [b]Il sostegno si taglia[/b]: se chi sostiene viene attaccato da una provincia diversa da quella verso cui sta sostenendo, il suo sostegno non vale (anche se l'attacco fallisce). Se l'attacco viene proprio dalla provincia contro cui sostiene, il sostegno cade solo se l'unità è scacciata.
- Una potenza [b]non può scacciare le proprie unità[/b] né sostenere chi le scaccia.
- Un [b]convoglio[/b] fallisce se una delle flotte della catena è scacciata. Essere soltanto attaccata non basta.
- Un'unità scacciata non ha effetto sulla provincia da cui è partito l'attacco, ma può ancora fermare altri."""],
	["Ritirate e aggiustamenti", """Un'unità scacciata deve [b]ritirarsi[/b] in una provincia confinante libera. Non può andare:
- nella provincia da cui è venuto l'attaccante;
- in una provincia rimasta vuota per uno stallo in quel turno.

Se non ha vie d'uscita è distrutta. Se due unità si ritirano nella stessa provincia si sciolgono entrambe. Si può sempre scegliere di sciogliere l'unità (per ricostruirla altrove in inverno, se i centri bastano).

In [b]inverno[/b] le nuove unità nascono solo nei centri di casa liberi: armata o flotta a scelta (la flotta solo sulla costa; a San Pietroburgo si sceglie quale). Chi deve sciogliere e non dà ordini perde le unità più lontane da casa."""],
	["Comandi di questa versione", """[b]La mappa[/b]: trascinate con un dito (o con il mouse) per spostarla; pizzicate con due dita o usate la rotella per lo zoom; ruotate due dita (o trascinate con il tasto destro) per girare e inclinare la vista.
Dal Menu si sceglie la carta: il [b]tabellone originale[/b] del gioco steso sul rilievo, oppure la mappa [b]ridisegnata in italiano[/b].
[b]Telefoni[/b]: in «Gioca online con gli amici» scegliete «Nessuna: questo schermo fa da tabellone» e inquadrate il codice QR della stanza con il telefono. Sul telefono si tratta e si danno gli ordini in segreto, a testo; la mappa resta sullo schermo grande.

[b]Dare un ordine[/b]: toccate una vostra unità, poi la destinazione evidenziata in giallo. In azzurro le coste raggiungibili per convoglio. Con i pulsanti in basso scegliete Sostieni (toccate l'unità da sostenere, poi dove), Convoglia (l'armata, poi lo sbarco) o Ferma.

[b]Consegnare[/b]: gli ordini restano modificabili finché non premete «Consegna gli ordini». Sono segreti: nessuno li vede prima della risoluzione.

[b]Diplomazia[/b]: la scheda «Diplomazia» mostra il quadro dei rapporti con ogni potenza (accordi in vigore, posta da leggere); toccate una potenza, o la sua bandiera in alto, per aprire la corrispondenza. Potete proporre alleanze, patti di non aggressione, zone sgombre, chiedere o offrire sostegni. Le IA rispondono subito... ma, come voi, non sono obbligate a mantenere la parola.

[b]Storico[/b]: ogni fase risolta si può rivedere sulla mappa con ordini ed esiti.

[b]A fine partita[/b] si aprono gli archivi segreti: i diari delle IA e tutti i dispacci, con le promesse fatte in malafede."""],
	["La diplomazia", """Tutto è lecito a parole: promesse, minacce, mezze verità, menzogne. Contano solo gli ordini scritti.

Qualche principio dei giocatori da torneo:

- [b]Parlate con tutti[/b], fin dalla primavera del 1901. Chi tace viene attaccato.
- [b]Tenete almeno due amici[/b]: se uno vi tradisce, non restate soli.
- [b]La fiducia si costruisce con le piccole promesse mantenute[/b]: un sostegno dato quando serviva vale più di cento parole.
- [b]Non combattete su due fronti.[/b] Fate pace con un nemico prima di aprire una nuova guerra.
- [b]Aiutate il vostro alleato quel tanto che basta[/b]: un alleato che ha bisogno di voi non vi pugnala.
- [b]Guardate la mappa, non le parole[/b]: un'unità «amica» a ridosso dei vostri centri di casa è una minaccia, qualunque cosa vi sia stata detta.
- [b]Fermate chi sta per vincere[/b]: quando una potenza supera i 12-13 centri tutti gli altri devono fare fronte comune, anche fra nemici."""],
	["La pugnalata", """Tradire un alleato è il cuore del gioco, ma va fatto bene:

- [b]Mai per un centro solo.[/b] Una pugnalata deve fruttare almeno due centri, oppure azzoppare la vittima per sempre: altrimenti avete solo trasformato un alleato in un nemico.
- [b]Non a metà partita[/b], quando il nemico comune è ancora forte e l'alleato vi serve.
- [b]Il momento giusto[/b] è quando l'alleato è sbilanciato in avanti, con i centri di casa sguarniti, e voi non avete altri fronti aperti; o nella corsa finale ai 18 centri.
- [b]Continuate a scrivere[/b] alla vittima fino all'ultimo: chi smette di trattare si tradisce da solo.
- [b]Dopo[/b], spiegate le vostre ragioni: nella prossima partita potreste aver bisogno di lui.

E per non essere pugnalati: tenete qualche unità di guarnigione, non lasciate che l'alleato diventi molto più grande di voi, e fate in modo che gli serviate ancora."""],
	["Le linee di stallo", """Alcune posizioni non si possono sfondare, per quante unità abbia l'attaccante: sono le [b]linee di stallo[/b]. Quasi tutte passano dalla Svizzera e tagliano la mappa in due.

La più importante divide il Nord-Ovest dal Sud-Est, lungo San Pietroburgo - Germania - Alpi - Mediterraneo occidentale: chi sta per vincere deve [b]attraversarla prima che si chiuda[/b], chi difende deve [b]chiuderla in tempo[/b].

I punti chiave:
- il [b]Medio Atlantico[/b] e lo stretto fra Spagna e Nord Africa: la porta fra i due mari;
- [b]San Pietroburgo[/b], la porta del Nord;
- le province attorno alla [b]Svizzera[/b]: Borgogna, Monaco, Tirolo, Piemonte;
- le [b]flotte[/b]: fare e disfare una linea è quasi sempre questione di navi.

Se vedete una potenza avvicinarsi ai 18 centri, guardate quali di questi punti potete ancora tenere insieme agli altri."""],
	["Le potenze", """[b]Austria-Ungheria[/b] - Al centro, circondata. Deve trovare subito un amico fra Italia, Russia e Turchia, o non arriva al 1904. Chi sopravvive all'apertura diventa temibile.

[b]Inghilterra[/b] - Un'isola: difficile da invadere, lenta a espandersi. Vive di flotte e di convogli. Sceglie fra Francia e Germania, e tiene d'occhio la Russia in Scandinavia.

[b]Francia[/b] - Forte e ben protetta, con Spagna e Portogallo quasi garantiti. Il rischio è l'intesa fra Inghilterra e Germania.

[b]Germania[/b] - Tanti vicini e tanti centri neutrali a portata. Deve tenere tranquillo un fronte per volta.

[b]Italia[/b] - La più lenta a partire. Sceglie fra l'attacco all'Austria (rischioso) e il «Lepanto» contro la Turchia insieme all'Austria.

[b]Russia[/b] - Quattro unità e due fronti. Può dilagare o crollare in fretta: tutto dipende da chi si fa amico a sud.

[b]Turchia[/b] - Un angolo quasi inespugnabile. Cresce piano ma è durissima da eliminare. L'alleanza con la Russia (il «Juggernaut») spaventa tutti."""],
	["Le aperture", ""],
	["Riconoscimenti", """[b]Diplomacy[/b] è un gioco di Allan B. Calhamer (1959).

Questa è una versione digitale amatoriale, senza scopo di lucro, per giocare con gli amici.

- Geometria delle province: ricavata dalla mappa SVG del progetto jDip (Zach DelProposto, J. Fatula III), licenza GPL.
- Arbitro delle regole: scritto per questa versione sull'algoritmo di Lucas Kruijswijk e verificato con i casi DATC e con il motore libero «diplomacy» di Philip Paquette.
- Libro delle aperture: dalla «Library of Diplomacy Openings» della Diplomatic Pouch.
- Strategia delle IA: dagli articoli della Diplomatic Pouch, del Diplomacy Archive e di Diplomacy World, e dalle ricerche sui bot (DumbBot di David Norman, DipBlue, Cicero).
- Pedine classiche (cannone e corazzata) modellate per questa versione; carro e nave dal modulo di Tabletop Simulator.
- Caratteri: Old Standard TT, Pinyon Script, Special Elite (licenze libere)."""],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 28)
	add_child(m)
	var v := UI.vbox(12)
	m.add_child(v)
	var top := UI.hbox(16)
	v.add_child(top)
	top.add_child(UI.title("Regole e consigli", 64))
	top.add_child(UI.spacer(0, 0, true))
	top.add_child(UI.primary("Chiudi", func(): chiudi.call(), 200, 24))
	var hb := UI.hbox(16)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(hb)
	var elenco := UI.vbox(6)
	var sc := UI.scroll(elenco)
	sc.size_flags_horizontal = Control.SIZE_FILL
	sc.custom_minimum_size.x = 400
	hb.add_child(sc)
	for i in CAPITOLI.size():
		var b := UI.button(CAPITOLI[i][0], _apri.bind(i), 370, 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		elenco.add_child(b)
		bottoni.append(b)
	var foglio := UI.panel(UI.parch_style())
	foglio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(foglio)
	testo = RichTextLabel.new()
	testo.bbcode_enabled = true
	testo.custom_minimum_size.x = 600
	testo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	testo.add_theme_color_override("default_color", UI.INK)
	testo.add_theme_font_size_override("normal_font_size", 25)
	testo.add_theme_font_size_override("bold_font_size", 25)
	foglio.add_child(testo)
	_apri(0)


func _apri(i: int) -> void:
	capitolo = i
	for k in bottoni.size():
		(bottoni[k] as Button).add_theme_color_override("font_color", Color.WHITE if k == i else UI.OTTONE_L)
	var t: String = CAPITOLI[i][1]
	if CAPITOLI[i][0] == "Le aperture":
		t = _aperture()
	testo.text = "[font_size=34][b]%s[/b][/font_size]\n\n%s" % [CAPITOLI[i][0], t]
	testo.scroll_to_line(0)


## Il libro delle aperture usato dalle IA, in chiaro.
func _aperture() -> String:
	var s := "Le aperture della primavera 1901 più giocate, con il nome che hanno fra gli appassionati. Sono le stesse che usano le IA, scelte secondo gli accordi presi.\n"
	var st := DPState.iniziale()
	for p in 7:
		s += "\n[b]%s[/b]\n" % DPMap.POTENZE[p]
		for a in DPAperture.LIBRO[p]:
			var ord := DPAperture.ordini(a["o"])
			var righe := []
			for u in ord:
				righe.append(DPGame.testo_ordine(st, u, ord[u]))
			s += "- [b]%s[/b]: %s\n" % [a["nome"], ", ".join(righe)]
	return s

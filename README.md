# Diplomacy

Versione digitale di **Diplomacy** (Allan B. Calhamer, 1959): Europa, 1901, sette grandi potenze, nessun
dado. Si scrivono ordini segreti, si tratta con tutti e si tradisce al momento giusto; vince chi arriva
a 18 centri di rifornimento.

Si gioca qui: https://tannoiser2.github.io/Diplomacy/ (e dalla ludoteca: https://tannoiser2.github.io/).

Fatta con Godot 4.7 (renderer `gl_compatibility`, esportazione web), tutta in italiano.

## Che cosa c'è

- **Mappa 3D in rilievo**: la carta d'Europa rifatta da zero (pergamena, confini a inchiostro, monti che si
  alzano dalla carta, mari animati) su un tavolo di mogano. Si sposta, si ingrandisce e si ruota con mouse e
  rotella oppure con le dita su iPad (un dito trascina, due pizzicano e ruotano).
- **Pedine 3D**: cannone da campagna e corazzata modellati per questa versione, oppure il carro e la nave
  del modulo di Tabletop Simulator (si cambia dal Menu).
- **Arbitro completo**: movimenti, sostegni, sostegni tagliati, convogli e catene di convogli, movimenti
  circolari, paradossi dei convogli (regola di Szykman), ritirate, costruzioni e scioglimenti. Verificato con
  i casi DATC e con migliaia di posizioni casuali contro un motore di riferimento.
- **Dispacci diplomatici** come telegrammi: alleanze, patti di non aggressione, zone sgombre, richieste e
  offerte di sostegno, informazioni riservate (vere o false), proposte di pareggio.
- **IA da torneo** a tre livelli (Console, Ambasciatore, Gran Maestro): vedi sotto.
- **Da 1 a 7 persone**: da soli contro sei IA, in più sullo stesso dispositivo (ci si passa lo schermo per
  gli ordini segreti) oppure **online** con gli amici, con le IA nei posti liberi.
- **Salvataggi**: la partita si salva da sola sul dispositivo («Continua l'ultima partita») e, dal Menu, su
  Firebase con un codice di sei lettere per riprenderla altrove.
- **Storico** di ogni fase rivedibile sulla mappa, schermata finale con l'andamento dei centri e gli
  **archivi segreti**: i diari delle IA e tutti i dispacci, con le promesse fatte in malafede.
- **Regole e consigli** in italiano: regole, comandi, diplomazia, pugnalate, linee di stallo, aperture.

## Come ragionano le IA

Ogni potenza artificiale ha un **diplomatico** (`scripts/ai/dp_diplomatico.gd`) e usa un **motore tattico**
comune (`scripts/ai/dp_tattica.gd`).

- **Aperture** (`dp_aperture.gd`): il libro delle aperture della primavera 1901 con nomi e frequenze della
  «Library of Diplomacy Openings» della Diplomatic Pouch (Gambetto balcanico, Churchill, Maginot, Blitzkrieg,
  Lepanto, Sistema ucraino, Rullo di Crimea…), scelte secondo gli accordi presi prima di muovere.
- **Tattica**: valore delle province sul modello del DumbBot di David Norman (attacco, difesa, diffusione ai
  vicini), generazione di molti insiemi di ordini candidati (mosse, sostegni, convogli, difese) e scelta per
  *miglior risposta campionata*: ogni candidato è arbitrato contro campioni degli ordini probabili degli altri.
- **Strategia**: bersaglio e alleato scelti in base a vicinanza, rapporti di forza, chi è già sotto attacco,
  preferenze «naturali» di ogni potenza; mai due guerre insieme; fronte comune contro chi sta per vincere.
- **Trattative**: propongono alleanze, patti e zone sgombre, chiedono e offrono sostegni concreti, avvertono
  gli amici e seminano zizzania; rispondono alle proposte delle persone valutandole davvero.
- **Fiducia**: ogni promessa mantenuta o mancata aggiorna la fiducia; chi tradisce è «bruciato» per anni e
  viene denunciato alle altre potenze. Fidarsi ma verificare: un'unità amica a ridosso dei centri di casa
  insospettisce comunque.
- **Menzogne e pugnalate**: secondo il carattere (leale, opportunista, volpe, mastino, prudente,
  calcolatore) accettano patti in malafede, promettono sostegni che non daranno e pugnalano l'alleato
  quando il guadagno atteso supera una soglia: mai per un centro solo, non a metà partita, sì nella corsa
  finale ai 18 centri - come raccomandano gli articoli dei giocatori da torneo. E dopo, spiegano.

Fonti: Diplomatic Pouch (diplom.org), Diplomacy Archive, Diplomacy World; i lavori su DumbBot, DipBlue e
Cicero per l'impianto dei bot.

## Online

Il gioco online usa il progetto Firebase della ludoteca (radice `diplomacy/rooms`, salvataggi in
`diplomacy/partite`), con le strutture già previste dalla regola comune del database: non servono regole
nuove. Le IA girano sul dispositivo di chi crea la stanza. Ordini e dispacci viaggiano nel registro delle
mosse della stanza: l'interfaccia li mostra solo a chi spetta, ma non sono cifrati (va bene fra amici).

## Sviluppo

```
scripts/core   mappa, posizione, arbitro (dp_adj.gd), partita e fasi
scripts/ai     tattica, diplomatici, cancellerie (posta e coordinamento), testi dei dispacci, aperture
scripts/net    Firebase (net.gd) e sessione di gioco locale/online (session.gd)
scripts/ui     tema, menu, vista di gioco, mappa 3D, dispacci, fine partita, regole
tools          costruzione di mappa, modelli e grafica; casi di prova; controllo dei glifi
tests          prove automatiche
```

Prove (Godot 4.7 da riga di comando):

```
godot --headless --path . --script tests/arbitro.gd          # arbitro: casi DATC + posizioni casuali
godot --headless --path . --script tests/sim.gd -- 3 2       # tre partite complete fra IA Gran Maestro
godot --headless --path . --script tests/save_load.gd        # salvataggio e ripresa
python3 tests/firebase_mock.py 8765 & tests/online.sh        # partita online su un finto Firebase
xvfb-run godot --path . --script tests/shot.gd -- /tmp/foto  # fotografie di tutta l'interfaccia
python3 tools/controlla_glifi.py                             # ogni carattere dei testi esiste nei font
```

La mappa si rigenera con `python3 tools/costruisci_mappa.py` (serve `pip install diplomacy numpy scipy
pillow`), le pedine con `tools/costruisci_modelli.py`, bandiere e sfondi con `tools/costruisci_grafica.py`.

## Pubblicazione

Il workflow **Pubblica** (`.github/workflows/pages.yml`) costruisce la versione web e la mette su GitHub
Pages. Non parte a ogni modifica: si lancia a mano (Actions - Pubblica - Run workflow) oppure con un commit
che contiene `[pubblica]` nel messaggio. La cartella `ludoteca/` (scheda e copertina) fa comparire il gioco
nella ludoteca.

## Riconoscimenti e licenze

- Diplomacy è un gioco di Allan B. Calhamer; i diritti sul gioco e sul marchio sono dei rispettivi
  titolari. Questa è una versione amatoriale senza scopo di lucro, per giocare con gli amici.
- La geometria delle province (`data/mappa.json`, `assets/mappa/`) è ricavata dalla mappa SVG del progetto
  jDip di Zach DelProposto e J. Fatula III (licenza GPL) distribuita con il pacchetto Python `diplomacy` di
  Philip Paquette, usato anche come riferimento per le prove dell'arbitro (i casi DATC sono di Lucas
  Kruijswijk).
- Caratteri: Old Standard TT (Alexey Kryukov), Pinyon Script (Nicole Fally), licenza OFL; Special Elite
  (Astigmatic), licenza Apache 2.0.
- Carro e nave «del modulo» vengono dal modulo «Fixed Diplomacy» di Tabletop Simulator.

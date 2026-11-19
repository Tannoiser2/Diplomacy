# Il tabellone originale steso sul rilievo 3D

Questi script producono `data/mappa_reale.json` e `assets/mappa_reale/` a partire dalla scansione del
tabellone contenuta nel modulo di Tabletop Simulator (3768x2484) e dalla mappa ridisegnata del gioco.
Sono strumenti di lavoro: i percorsi in testa ai file vanno adattati alla propria macchina.

1. `tps.py` – porta la mappa delle province ridisegnata sul tabellone, usando come punti fermi le 34
   stelle dei centri (`stelle.json`, coordinate a metà risoluzione) e una prima stima quadratica (`C.npy`).
2. `flusso.py` – affina l'allineamento con un flusso ottico fra i confini noti e le linee stampate.
3. `seg4.py` – separa terra e mare sulla stampa, poi assegna ogni punto a una provincia agganciandosi
   alle linee stampate (`correzioni.json`: semi messi a mano sulle etichette).
4. `finale.py` – posizioni di pedine e coste, mappa dei tocchi (R provincia, G terra, B distanza dalla
   riva, A distanza dal confine) e quote del rilievo.

I confini interni dei paesi sono approssimati di qualche punto: per questo, sul tabellone originale,
tinte ed evidenziazioni sfumano verso i bordi della provincia. `tests/mappa.gd` controlla che ogni
pedina e ogni stella cadano nella provincia giusta.

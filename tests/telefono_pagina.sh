#!/bin/bash
# Prova «tabellone + pagina HTML per telefono»: finto Firebase, uno schermo che ospita senza giocare
# (Godot, senza finestra) e un telefono vero-simile (Chrome) che apre web/telefono e gioca l'Italia.
# Uso: tests/telefono_pagina.sh [percorso di godot] [cartella per le foto]
# Servono node con puppeteer-core e Chrome (NODE_PATH se puppeteer-core non è installato qui).
G=${1:-godot}
FOTO=${2:-/tmp/shots_pagina}
cd "$(dirname "$0")/.."
SITO=$(mktemp -d)
bash tools/prepara_telefono.sh "$SITO"
python3 tests/firebase_mock.py 8768 > /tmp/dp_mock4.log 2>&1 &
MOCK=$!
(cd "$SITO" && exec python3 -m http.server 8098 --bind 127.0.0.1 > /dev/null 2>&1) &
WEB=$!
sleep 1
export DP_DB_URL=http://127.0.0.1:8768/db DP_AUTH_URL=http://127.0.0.1:8768/signup DP_REFRESH_URL=http://127.0.0.1:8768/refresh
rm -f /tmp/dp_codice4.txt /tmp/dp_tav4.cfg
DP_ATTESI=1 DP_CODEFILE=/tmp/dp_codice4.txt DP_SESSION=/tmp/dp_tav4.cfg $G --headless --path . --script tests/tavolo.gd > /tmp/dp_tav4.log 2>&1 &
TAV=$!
node tests/web/telefono_pagina.js "http://127.0.0.1:8098/telefono/?rtdb=http://127.0.0.1:8768/db" /tmp/dp_codice4.txt "$FOTO"
ESITO=$?
sleep 3
kill $TAV $MOCK $WEB 2>/dev/null
grep -h "DPTEST" /tmp/dp_tav4.log | tail -3
grep -h -E "SCRIPT ERROR" -A3 /tmp/dp_tav4.log | head -12
rm -rf "$SITO"
exit $ESITO

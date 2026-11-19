#!/bin/bash
# Prova online: avvia il finto Firebase e due istanze del gioco (chi ospita e un amico).
# Uso: tests/online.sh [percorso di godot]
G=${1:-godot}
cd "$(dirname "$0")/.."
PORTA=8765
python3 tests/firebase_mock.py $PORTA > /tmp/dp_mock.log 2>&1 &
MOCK=$!
sleep 1
export DP_DB_URL=http://127.0.0.1:$PORTA/db DP_AUTH_URL=http://127.0.0.1:$PORTA/signup DP_REFRESH_URL=http://127.0.0.1:$PORTA/refresh
rm -f /tmp/dp_codice.txt /tmp/dp_host.cfg /tmp/dp_guest.cfg
DP_ROLE=host DP_CODEFILE=/tmp/dp_codice.txt DP_SESSION=/tmp/dp_host.cfg $G --headless --path . --script tests/online_play.gd > /tmp/dp_host.log 2>&1 &
H=$!
DP_ROLE=guest DP_CODEFILE=/tmp/dp_codice.txt DP_SESSION=/tmp/dp_guest.cfg $G --headless --path . --script tests/online_play.gd > /tmp/dp_guest.log 2>&1 &
O=$!
wait $H $O
kill $MOCK 2>/dev/null
A=$(grep "DPTEST impronta" /tmp/dp_host.log | cut -d'|' -f1,2)
B=$(grep "DPTEST impronta" /tmp/dp_guest.log | cut -d'|' -f1,2)
grep DPTEST /tmp/dp_host.log /tmp/dp_guest.log
if [ -n "$A" ] && [ "$A" == "$B" ]; then echo "ONLINE OK"; else echo "ONLINE FALLITO"; exit 1; fi

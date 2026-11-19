#!/bin/bash
# Prova «tabellone + telefoni»: il finto Firebase, uno schermo che ospita senza giocare e due telefoni.
# Uso: tests/telefono_online.sh [percorso di godot]
G=${1:-godot}
cd "$(dirname "$0")/.."
PORTA=8766
python3 tests/firebase_mock.py $PORTA > /tmp/dp_mock2.log 2>&1 &
MOCK=$!
sleep 1
export DP_DB_URL=http://127.0.0.1:$PORTA/db DP_AUTH_URL=http://127.0.0.1:$PORTA/signup DP_REFRESH_URL=http://127.0.0.1:$PORTA/refresh
rm -f /tmp/dp_codice2.txt /tmp/dp_tav.cfg /tmp/dp_tel2.cfg /tmp/dp_tel4.cfg
DP_ROLE=tavolo DP_CODEFILE=/tmp/dp_codice2.txt DP_SESSION=/tmp/dp_tav.cfg $G --headless --path . --script tests/telefono_online.gd > /tmp/dp_tav.log 2>&1 &
A=$!
DP_ROLE=telefono DP_POSTO=4 DP_CODEFILE=/tmp/dp_codice2.txt DP_SESSION=/tmp/dp_tel4.cfg $G --headless --path . --script tests/telefono_online.gd > /tmp/dp_tel4.log 2>&1 &
B=$!
DP_ROLE=telefono DP_POSTO=2 DP_CODEFILE=/tmp/dp_codice2.txt DP_SESSION=/tmp/dp_tel2.cfg $G --headless --path . --script tests/telefono_online.gd > /tmp/dp_tel2.log 2>&1 &
C=$!
wait $A $B $C
kill $MOCK 2>/dev/null
grep -h DPTEST /tmp/dp_tav.log /tmp/dp_tel4.log /tmp/dp_tel2.log | grep -v "tavolo: \(Prim\|Aut\|Inv\|Rit\)"
X=$(grep "DPTEST impronta" /tmp/dp_tav.log | cut -d'|' -f1,2)
Y=$(grep "DPTEST impronta" /tmp/dp_tel4.log | cut -d'|' -f1,2)
Z=$(grep "DPTEST impronta" /tmp/dp_tel2.log | cut -d'|' -f1,2)
if [ -n "$X" ] && [ "$X" == "$Y" ] && [ "$X" == "$Z" ]; then echo "TELEFONI ONLINE OK"; else echo "TELEFONI ONLINE FALLITO"; grep -h -E "SCRIPT ERROR|ERROR:" -A3 /tmp/dp_tav.log /tmp/dp_tel4.log /tmp/dp_tel2.log | head -30; exit 1; fi

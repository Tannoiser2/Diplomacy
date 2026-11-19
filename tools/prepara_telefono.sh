#!/bin/bash
# Mette accanto al gioco la pagina HTML per i telefoni (diplomazia e ordini, senza mappa):
# la pagina di web/telefono più caratteri, bandiere e pergamena presi dalle risorse del gioco.
# Uso: tools/prepara_telefono.sh <cartella del sito, es. build/web>
set -e
cd "$(dirname "$0")/.."
D="$1/telefono"
mkdir -p "$D/fonts"
cp web/telefono/index.html "$D/"
cp assets/fonts/*.ttf "$D/fonts/"
cp assets/bandiere/b?.png "$D/"
cp assets/misc/pergamena.jpg "$D/"
test -f "$D/index.html"

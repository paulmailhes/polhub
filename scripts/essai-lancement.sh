#!/bin/bash
# Vérifie, sans aucune autorisation (ni micro, ni navigateur), que l'application compilée :
#   1. se lance, fait tourner une sonde et sort avec le code 0 ;
#   2. sort avec le code 0 quand on lui demande de s'arrêter (SIGTERM) : l'agent de relance ne doit
#      relancer l'app qu'après un vrai plantage ;
#   3. écrit une ligne par lancement dans son journal.
# Efface les dossiers de traces qu'il a lui-même créés.
set -u

BIN="build/Polhub.app/Contents/MacOS/Polhub"
[ -x "$BIN" ] || { echo "Introuvable : $BIN (lancer « make app »)"; exit 1; }
ROOT="$HOME/Library/Application Support/Polhub/Mesures"
JOURNAL="$ROOT/lancements.jsonl"
export POLHUB_NO_ALERT=1
failures=0
mkdir -p "$ROOT"
marker="$(mktemp)"
before=$( [ -f "$JOURNAL" ] && wc -l < "$JOURNAL" || echo 0 )

"$BIN" --probe crash-writer --seconds 3 --quit >/dev/null 2>&1
code=$?
echo "1. sonde courte            : code $code (attendu 0)"
[ "$code" -eq 0 ] || failures=$((failures + 1))

"$BIN" --probe crash-writer --seconds 30 >/dev/null 2>&1 &
pid=$!
sleep 3
kill -TERM "$pid"
wait "$pid"
code=$?
echo "2. arrêt demandé (SIGTERM) : code $code (attendu 0)"
[ "$code" -eq 0 ] || failures=$((failures + 1))

after=$( [ -f "$JOURNAL" ] && wc -l < "$JOURNAL" || echo 0 )
added=$((after - before))
echo "3. journal des lancements  : $added ligne(s) ajoutée(s) (attendu 2)"
[ "$added" -eq 2 ] || failures=$((failures + 1))
tail -n 2 "$JOURNAL" 2>/dev/null | jq -c '{kind, origin: .data.origin, probe: .data.probe}'

find "$ROOT" -maxdepth 1 -type d -name '*-crash-writer' -newer "$marker" -exec rm -rf {} + 2>/dev/null
rm -f "$marker"

[ "$failures" -eq 0 ] && echo "Lancement vérifié." || { echo "$failures contrôle(s) en échec."; exit 1; }

#!/bin/bash
# Mesure ce que coûte un arrêt brutal pendant l'écriture des segments audio.
# Lance <n> fois l'écriture d'un son de synthèse, la tue par `kill -9` à un instant au hasard,
# puis fait relire les fichiers. Aucune autorisation n'est en jeu : pas de micro, pas de navigateur.
# Efface les dossiers de traces qu'il a lui-même créés.
set -u

N="${1:-50}"
BIN="build/Transcriptor.app/Contents/MacOS/Transcriptor"
[ -x "$BIN" ] || { echo "Introuvable : $BIN (lancer « make app »)"; exit 1; }

ROOT="$HOME/Library/Application Support/Transcriptor/Mesures"
losses=()

for i in $(seq 1 "$N"); do
    "$BIN" --probe crash-writer --seconds 30 --quit >/dev/null 2>&1 &
    pid=$!
    sleep "$(( (RANDOM % 9) + 2 )).$(( RANDOM % 10 ))"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null

    out="$("$BIN" --probe crash-writer --variant verify --quit 2>/dev/null)"
    loss="$(sed -n 's/.*perte_ms=\([0-9][0-9]*\).*/\1/p' <<<"$out")"
    dir="$(sed -n 's/.*dossier=\(.*\)$/\1/p' <<<"$out")"
    written="$(sed -n 's/.*ecrites=\([0-9][0-9]*\).*/\1/p' <<<"$out")"
    if [ -z "$loss" ] || [ "${written:-0}" -eq 0 ]; then
        echo "essai $i : sans mesure ($out)"
    else
        losses+=("$loss")
        [ -n "${VERBOSE:-}" ] && echo "essai $i : ${out% dossier=*}"
    fi
    # Ménage : le dossier de l'écriture tuée, et ceux des vérifications.
    case "$dir" in "$ROOT"/*-crash-writer) rm -rf "$dir" ;; esac
    find "$ROOT" -maxdepth 1 -type d -name '*-crash-writer' ! -exec test -d '{}/audio' ';' -exec rm -rf '{}' + 2>/dev/null
done

count="${#losses[@]}"
[ "$count" -gt 0 ] || { echo "Aucune mesure."; exit 1; }
sorted=($(printf '%s\n' "${losses[@]}" | sort -n))
echo "essais=$count pertes_ms: max=${sorted[$((count - 1))]} mediane=${sorted[$((count / 2))]} min=${sorted[0]}"

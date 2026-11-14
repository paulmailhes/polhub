#!/bin/zsh
# Polhub : la clé Google qui lui permet de lire tes agendas et d'y créer tes rendez-vous, une seule fois.
# Ouvre chaque page de la console Google au bon endroit, puis range tout seul le fichier téléchargé dans
# ~/Library/Application Support/Polhub/google-client.json (jamais affiché, jamais dans le dépôt).
# Le projet est publié « en production » : les connexions tiennent, sans rien refaire tous les 7 jours.

DEST="$HOME/Library/Application Support/Polhub/google-client.json"
etape() { print; print -P "%B── Étape $1/6 — $2%b"; }
attendre() { read "?   Entrée quand c'est fait… "; }

clear
print -P "%BPolhub — clé Google pour lire tes agendas%b"
print "Connecte-toi à la console Google avec ton compte perso. Chaque page s'ouvre toute seule."
print -P "%BÀ chaque étape, vérifie en haut de la page que le projet choisi est bien « Polhub ».%b"

if [[ -f "$DEST" ]]; then
  print; print "La clé est déjà en place. Rien à faire : dans Polhub, ouvre Calendrier › Ajouter un compte Google."
  read "?Entrée pour fermer… "; exit 0
fi

etape 1 "Créer le projet"
print "   Nom du projet : Polhub → Créer. Attends qu'il soit créé, puis choisis-le en haut de la page."
open "https://console.cloud.google.com/projectcreate"; attendre

etape 2 "Activer l'API Google Agenda"
print "   « Activer »."
open "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com"; attendre

etape 3 "L'écran de consentement"
print "   « Commencer » → nom de l'application : Polhub → ton e-mail → Audience : Externe → ton e-mail"
print "   → accepter le règlement → Créer."
open "https://console.cloud.google.com/auth/overview"; attendre

etape 4 "L'identité de l'application (Google l'exige pour publier)"
print "   Page d'accueil de l'application :       https://paulmailhes.github.io/polhub/"
print "   Règles de confidentialité :             https://paulmailhes.github.io/polhub/confidentialite.html"
print "   Conditions d'utilisation :              https://paulmailhes.github.io/polhub/conditions.html"
print "   Domaines autorisés → « Ajouter un domaine » : paulmailhes.github.io"
print "   → Enregistrer."
open "https://console.cloud.google.com/auth/branding"; attendre

etape 5 "Publier l'application (pour que les connexions tiennent)"
print "   « Publier l'application » → Confirmer. Le statut doit devenir « En production »."
print "   À la première connexion, Google dira « application non validée » (normal, sans validation),"
print "   et il suffira de cliquer « Paramètres avancés » puis « Accéder à Polhub »."
open "https://console.cloud.google.com/auth/audience"; attendre

etape 6 "Créer la clé"
print "   Type d'application : Application de bureau → nom : Polhub → Créer → « Télécharger le fichier JSON »."
debut=$(date +%s)
open "https://console.cloud.google.com/auth/clients/create"
print "   J'attends le fichier dans Téléchargements… (Ctrl+C pour arrêter)"
while true; do
  f=$(ls -t "$HOME/Downloads"/client_secret_*.json 2>/dev/null | head -1)
  if [[ -n "$f" ]] && (( $(stat -f %m "$f") >= debut )); then break; fi
  sleep 2
done
if ! /usr/bin/python3 -I -c 'import json,sys; c=json.load(open(sys.argv[1])); assert "installed" in c' "$f" 2>/dev/null; then
  print "   Ce fichier n'est pas une clé « Application de bureau ». Recommence l'étape 5 avec ce type."
  read "?Entrée pour fermer… "; exit 1
fi
mkdir -p "${DEST:h}"
mv "$f" "$DEST" && chmod 600 "$DEST"
print; print -P "%BC'est fait.%b La clé est rangée. Dans Polhub : Calendrier › Ajouter un compte Google."
read "?Entrée pour fermer… "

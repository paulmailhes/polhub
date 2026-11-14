#!/bin/zsh
# Polhub : la clé Google qui lui permet de lire tes agendas et d'y créer tes rendez-vous, une seule fois.
# Si la clé est déjà en place, il ne reste que les deux gestes qui ouvrent Gmail à Polhub (14/11).
# Ouvre chaque page de la console Google au bon endroit, puis range tout seul le fichier téléchargé dans
# ~/Library/Application Support/Polhub/google-client.json (jamais affiché, jamais dans le dépôt).
# Le projet est publié « en production » : les connexions tiennent, sans rien refaire tous les 7 jours.

DEST="$HOME/Library/Application Support/Polhub/google-client.json"
etape() { print; print -P "%B── Étape $1/8 — $2%b"; }
attendre() { read "?   Entrée quand c'est fait… "; }
# Les deux gestes qui ouvrent Gmail à Polhub : l'API, puis le champ d'application.
mails() {
  print; print -P "%B── Mails $1 — Activer l'API Gmail%b"
  print "   « Activer »."
  open "https://console.cloud.google.com/apis/library/gmail.googleapis.com"; attendre
  print; print -P "%B── Mails $2 — Le champ d'application des mails%b"
  print "   « Ajouter ou supprimer des champs d'application » → dans le filtre, tape gmail.modify"
  print "   → coche la ligne « .../auth/gmail.modify » → « Mettre à jour » → « Enregistrer »."
  open "https://console.cloud.google.com/auth/scopes"; attendre
}

clear
print -P "%BPolhub — clé Google pour lire tes agendas%b"
print "Connecte-toi à la console Google avec ton compte perso. Chaque page s'ouvre toute seule."
print -P "%BÀ chaque étape, vérifie en haut de la page que le projet choisi est bien « Polhub ».%b"

if [[ -f "$DEST" ]]; then
  print; print "La clé est déjà en place. Il reste deux gestes pour les mails."
  mails "1/2" "2/2"
  print; print -P "%BC'est fait.%b Dans Polhub : Réglages › Comptes Google › « Autoriser les mails », sur chaque compte."
  print "Sur l'avertissement de Google : « Paramètres avancés » → « Accéder à Polhub » → coche les mails et l'agenda."
  read "?Entrée pour fermer… "; exit 0
fi

etape 1 "Créer le projet"
print "   Nom du projet : Polhub → Créer. Attends qu'il soit créé, puis choisis-le en haut de la page."
open "https://console.cloud.google.com/projectcreate"; attendre

etape 2 "Activer l'API Google Agenda"
print "   « Activer »."
open "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com"; attendre

mails "(étape 3/8)" "(étape 4/8)"

etape 5 "L'écran de consentement"
print "   « Commencer » → nom de l'application : Polhub → ton e-mail → Audience : Externe → ton e-mail"
print "   → accepter le règlement → Créer."
open "https://console.cloud.google.com/auth/overview"; attendre

etape 6 "L'identité de l'application (Google l'exige pour publier)"
print "   Page d'accueil de l'application :       https://paulmailhes.github.io/polhub/"
print "   Règles de confidentialité :             https://paulmailhes.github.io/polhub/confidentialite.html"
print "   Conditions d'utilisation :              https://paulmailhes.github.io/polhub/conditions.html"
print "   Domaines autorisés → « Ajouter un domaine » : paulmailhes.github.io"
print "   → Enregistrer."
open "https://console.cloud.google.com/auth/branding"; attendre

etape 7 "Publier l'application (pour que les connexions tiennent)"
print "   « Publier l'application » → Confirmer. Le statut doit devenir « En production »."
print "   À la première connexion, Google dira « application non validée » (normal, sans validation),"
print "   et il suffira de cliquer « Paramètres avancés » puis « Accéder à Polhub »."
open "https://console.cloud.google.com/auth/audience"; attendre

etape 8 "Créer la clé"
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
  print "   Ce fichier n'est pas une clé « Application de bureau ». Recommence l'étape 8 avec ce type."
  read "?Entrée pour fermer… "; exit 1
fi
mkdir -p "${DEST:h}"
mv "$f" "$DEST" && chmod 600 "$DEST"
print; print -P "%BC'est fait.%b La clé est rangée. Dans Polhub : Réglages › Comptes Google › Ajouter un compte Google."
read "?Entrée pour fermer… "

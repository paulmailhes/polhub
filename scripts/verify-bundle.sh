#!/bin/bash
# Vérifie qu'une Polhub.app compilée porte les textes d'usage, l'identifiant, la signature et les
# droits attendus. Sans les textes d'usage, macOS enregistre du silence sans aucune erreur.
set -u

APP="${1:?usage: verify-bundle.sh <Polhub.app> [identifiant]}"
PLIST="$APP/Contents/Info.plist"
EXPECTED_ID="${2:-fr.paulmailhes.polhub}"
EXPECTED_AUTHORITY="Authority=Developer ID Application: Paul Mailhes (CQ43U6XX4Z)"
failures=0

check() { # check <label> <command...>
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "OK      $label"; else echo "ÉCHEC   $label"; failures=$((failures + 1)); fi
}

plist_value() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }
not_empty()   { [ -n "$(plist_value "$1")" ]; }
equals()      { [ "$(plist_value "$1")" = "$2" ]; }

check "Info.plist présent"                test -f "$PLIST"
check "NSMicrophoneUsageDescription"      not_empty NSMicrophoneUsageDescription
check "NSAudioCaptureUsageDescription"    not_empty NSAudioCaptureUsageDescription
check "NSAppleEventsUsageDescription"     not_empty NSAppleEventsUsageDescription
check "CFBundleIdentifier = $EXPECTED_ID" equals CFBundleIdentifier "$EXPECTED_ID"
check "LSUIElement = true"                equals LSUIElement true

AGENT="$APP/Contents/Library/LaunchAgents/fr.paulmailhes.polhub.relance.plist"
agent_value() { plutil -extract "$1" raw -o - "$AGENT" 2>/dev/null; }
agent_equals() { [ "$(agent_value "$1")" = "$2" ]; }

# Seule la version de production porte l'agent de relance.
if [ "$EXPECTED_ID" = "fr.paulmailhes.polhub" ]; then
    check "agent de relance présent"          test -f "$AGENT"
    check "agent : Label"                     agent_equals Label fr.paulmailhes.polhub.relance
    check "agent : BundleProgram"             agent_equals BundleProgram Contents/MacOS/Polhub
    check "agent : KeepAlive sur échec"       agent_equals KeepAlive.SuccessfulExit false
else
    check "pas d'agent de relance"            test ! -e "$AGENT"
    check "PolhubFlavor = dev"                   equals PolhubFlavor dev
fi

check "signature valide (codesign --verify)" codesign --verify --deep --strict "$APP"

details="$(codesign -dv --verbose=4 "$APP" 2>&1)"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
has() { grep -qF -- "$2" <<<"$1"; }
# The app never loads a model: WhisperKit and Silero live only in polhub-calcul.
not_linked_whisperkit() { ! strings "$APP/Contents/MacOS/$(defaults read "$PLIST" CFBundleExecutable)" | grep -q "WhisperKitConfig"; }

check "signée Developer ID (CQ43U6XX4Z)"  has "$details" "$EXPECTED_AUTHORITY"
check "Hardened Runtime"                  has "$details" "(runtime)"
check "droit audio-input"                 has "$entitlements" "com.apple.security.device.audio-input"
check "droit apple-events"                has "$entitlements" "com.apple.security.automation.apple-events"

# Étape 2 : le calcul et la ligne de commande, signés comme l'app.
HELPERS="$APP/Contents/Helpers"
for tool in polhub-calcul polhub; do
    tool_details=$(codesign -dv --verbose=4 "$HELPERS/$tool" 2>&1 || true)
    check "$tool présent"                 test -x "$HELPERS/$tool"
    check "$tool signé par CQ43U6XX4Z"    has "$tool_details" "TeamIdentifier=CQ43U6XX4Z"
    check "$tool en Hardened Runtime"     has "$tool_details" "(runtime)"
done
check "polhub --help répond"        "$HELPERS/polhub" --help
check "aucun modèle d'IA lié à l'app"     not_linked_whisperkit

echo
codesign -d -r- "$APP" 2>&1 | grep -E "^designated" || echo "designated => (illisible)"

if [ "$failures" -gt 0 ]; then
    echo "$failures contrôle(s) en échec."
    exit 1
fi
echo "Tous les contrôles passent."

#!/bin/bash
# Vérifie qu'une hub.app compilée porte les textes d'usage, l'identifiant, la signature et les
# droits attendus. Sans les textes d'usage, macOS enregistre du silence sans aucune erreur.
set -u

APP="${1:?usage: verify-bundle.sh <hub.app> [identifiant]}"
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
    check "agent : BundleProgram"             agent_equals BundleProgram Contents/MacOS/hub
    check "agent : KeepAlive sur échec"       agent_equals KeepAlive.SuccessfulExit false
else
    check "pas d'agent de relance"            test ! -e "$AGENT"
    check "HubFlavor = dev"                      equals HubFlavor dev
fi

check "signature valide (codesign --verify)" codesign --verify --deep --strict "$APP"

details="$(codesign -dv --verbose=4 "$APP" 2>&1)"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
has() { grep -qF -- "$2" <<<"$1"; }
# The app never loads a model: WhisperKit and Silero live only in hub-calcul.
not_linked_whisperkit() { ! strings "$APP/Contents/MacOS/$(defaults read "$PLIST" CFBundleExecutable)" | grep -q "WhisperKitConfig"; }

check "signée Developer ID (CQ43U6XX4Z)"  has "$details" "$EXPECTED_AUTHORITY"
check "Hardened Runtime"                  has "$details" "(runtime)"
check "droit audio-input"                 has "$entitlements" "com.apple.security.device.audio-input"
check "droit apple-events"                has "$entitlements" "com.apple.security.automation.apple-events"
# Notarisation : Apple refuse une signature sans horodatage sécurisé ou avec le droit de débogage.
lacks() { ! grep -qF -- "$2" <<<"$1"; }
# Perl, a hardened program, loads a library only by its full path.
media_state() { /usr/bin/perl -e 'use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0]) or exit 2; my $s = DynaLoader::dl_find_symbol($l, "hub_media_state") or exit 3; DynaLoader::dl_install_xsub("main::o", $s); main::o();' "$(cd "$HELPERS" && pwd)/hub-media.dylib" | grep -qE '^[01] [0-9]+$'; }
check "horodatage sécurisé"               has "$details" "Timestamp="
check "pas de droit get-task-allow"       lacks "$entitlements" "get-task-allow"

# Étape 2 : le calcul et la ligne de commande, signés comme l'app.
HELPERS="$APP/Contents/Helpers"
for tool in hub-calcul hub-dictee hub; do
    tool_details=$(codesign -dv --verbose=4 "$HELPERS/$tool" 2>&1 || true)
    check "$tool présent"                 test -x "$HELPERS/$tool"
    check "$tool signé par CQ43U6XX4Z"    has "$tool_details" "TeamIdentifier=CQ43U6XX4Z"
    check "$tool en Hardened Runtime"     has "$tool_details" "(runtime)"
    check "$tool horodaté"                has "$tool_details" "Timestamp="
    check "$tool sans get-task-allow"     lacks "$(codesign -d --entitlements - --xml "$HELPERS/$tool" 2>/dev/null)" "get-task-allow"
done
# The Dictée's helper listens to the microphone itself (20/11).
check "hub-dictee : droit audio-input"   has "$(codesign -d --entitlements - --xml "$HELPERS/hub-dictee" 2>/dev/null)" "com.apple.security.device.audio-input"
# The Dictée's bridge to « what is playing » (20/11): signed like the app, loaded by /usr/bin/perl.
media_details=$(codesign -dv --verbose=4 "$HELPERS/hub-media.dylib" 2>&1 || true)
check "hub-media.dylib présent"           test -f "$HELPERS/hub-media.dylib"
check "hub-media.dylib signé par CQ43U6XX4Z" has "$media_details" "TeamIdentifier=CQ43U6XX4Z"
check "hub-media.dylib horodaté"          has "$media_details" "Timestamp="
check "hub-media.dylib répond par Perl"   media_state
check "hub --help répond"           "$HELPERS/hub" --help
check "aucun modèle d'IA lié à l'app"     not_linked_whisperkit

echo
codesign -d -r- "$APP" 2>&1 | grep -E "^designated" || echo "designated => (illisible)"

if [ "$failures" -gt 0 ]; then
    echo "$failures contrôle(s) en échec."
    exit 1
fi
echo "Tous les contrôles passent."

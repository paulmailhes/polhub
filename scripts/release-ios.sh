#!/bin/bash
# Publie une version de Polhub pour iPhone sur TestFlight. Usage : scripts/release-ios.sh 1.0.0
#   1. tests du paquet Link ; 2. archive signée (identifiant fr.paulmailhes.polhub.ios) ;
#   3. envoi à App Store Connect, d'où TestFlight la donne à l'iPhone de Paul.
# Réglages locaux (jamais publiés) : prive/appstore.env définit APPSTORE_KEY_ID, APPSTORE_ISSUER_ID et APPSTORE_KEY_PATH,
# la clé d'API d'App Store Connect (un fichier .p8, jamais affiché ni versionné). Le numéro de build est l'heure de
# l'envoi : TestFlight en veut un nouveau à chaque fois.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, par exemple 1.0.0}"
cd "$ROOT"
fail() { echo "$*" >&2; echo "Rien n'est envoyé." >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version attendue sous la forme 1.0.0, pas « $VERSION »."
[ -f prive/appstore.env ] || fail "prive/appstore.env manque : la clé d'API d'App Store Connect."
. prive/appstore.env
: "${APPSTORE_KEY_ID:?APPSTORE_KEY_ID manque dans prive/appstore.env}"
: "${APPSTORE_ISSUER_ID:?APPSTORE_ISSUER_ID manque dans prive/appstore.env}"
: "${APPSTORE_KEY_PATH:?APPSTORE_KEY_PATH manque dans prive/appstore.env}"
[ -f "$APPSTORE_KEY_PATH" ] || fail "La clé $APPSTORE_KEY_PATH n'existe pas."
[ -z "$(git status --porcelain)" ] || fail "Des changements ne sont pas commités."

AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$APPSTORE_KEY_PATH" -authenticationKeyID "$APPSTORE_KEY_ID"
      -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID")
BUILD="$(date +%Y%m%d%H%M)"
OUT="$ROOT/build/ios"
rm -rf "$OUT" && mkdir -p "$OUT" dist

echo "1/3 Tests"
swift test --package-path Packages/Link >dist/tests-ios.log 2>&1 || { tail -30 dist/tests-ios.log >&2; fail "Des tests échouent (dist/tests-ios.log)."; }

echo "2/3 Archive $VERSION ($BUILD)"
xcodegen generate --quiet
xcodebuild -project Polhub.xcodeproj -scheme PolhubPhone -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Polhub.xcarchive" -derivedDataPath build/DerivedData-ios-release "${AUTH[@]}" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive >"$OUT/archive.log" 2>&1 \
  || { grep -E 'error:' "$OUT/archive.log" | head -20 >&2; fail "L'archive a échoué ($OUT/archive.log)."; }

echo "3/3 Envoi à App Store Connect"
cat >"$OUT/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>CQ43U6XX4Z</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
# La signature de distribution et l'envoi passent par le compte Apple ouvert dans Xcode : la clé d'API (App Manager) n'a
# pas le droit de signer « dans le nuage » (mesuré le 20/11 : « Cloud signing permission error »).
xcodebuild -exportArchive -archivePath "$OUT/Polhub.xcarchive" -exportOptionsPlist "$OUT/export.plist" -exportPath "$OUT/export" \
  -allowProvisioningUpdates >"$OUT/export.log" 2>&1 || { grep -E 'error:' "$OUT/export.log" | head -20 >&2; fail "L'envoi a échoué ($OUT/export.log)."; }
node scripts/testflight.mjs groupe || echo "Le groupe TestFlight n'a pas pu être préparé : la version est envoyée quand même." >&2
echo "Envoyée : Polhub iPhone $VERSION ($BUILD). TestFlight la donne à l'iPhone une fois traitée par Apple (quelques minutes)."

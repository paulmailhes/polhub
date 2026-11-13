#!/bin/bash
# Publie une version de Transcriptor sur GitHub. Usage : scripts/release.sh 0.3.1 (ou make release VERSION=0.3.1)
#   1. tests ; 2. VERSION ; 3. app signée et vérifiée ; 4. notarisation par Apple si possible ;
#   5. dist/Transcriptor.zip ; 6. étiquette vX.Y.Z et version GitHub, avec la section de CHANGELOG.md.
# Les Transcriptor installés la trouvent dans l'heure et s'installent seuls, jamais pendant une réunion :
# ils n'acceptent qu'une app signée par l'équipe de l'auteur (Packages/MeetingsMac/Sources/Updates/Verifier.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, par exemple 0.3.1}"
REPO="paulmailhes/transcriptor"
PROFILE="${TRANSCRIPTOR_NOTARY_PROFILE:-vigie-notarisation}"
APP="$ROOT/build/Transcriptor.app"
cd "$ROOT"

fail() { echo "$*" >&2; echo "Rien n'est publié." >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version attendue sous la forme 0.3.1, pas « $VERSION »."
[ "$(git branch --show-current)" = "main" ] || fail "Publier depuis la branche main."
[ -z "$(git status --porcelain)" ] || fail "Des changements ne sont pas commités."
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "L'étiquette v$VERSION existe déjà."
NOTES="$(awk -v v="## $VERSION" 'index($0, v) == 1 { on = 1; next } on && /^## / { exit } on' CHANGELOG.md)"
[ -n "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ] || fail "CHANGELOG.md n'a pas de section « ## $VERSION »."

echo "1/6 Tests"
make check >/dev/null 2>&1 || fail "Des tests échouent."

echo "2/6 Version $VERSION"
if [ "$(cat VERSION)" != "$VERSION" ]; then
  echo "$VERSION" > VERSION
  git add VERSION
  git commit -q -m "Version $VERSION"
fi

echo "3/6 App signée"
make app VERSION="$VERSION" >/dev/null
scripts/verify-bundle.sh "$APP" >/dev/null || fail "L'app ne passe pas ses contrôles (scripts/verify-bundle.sh)."
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT" = "$VERSION" ] || fail "L'app construite porte la version $BUILT, pas $VERSION."
codesign -dv --verbose=2 "$APP" 2>&1 | grep -qx "TeamIdentifier=CQ43U6XX4Z" || fail "L'app n'est pas signée par l'équipe CQ43U6XX4Z."

echo "4/6 Notarisation"
mkdir -p dist
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  ditto -c -k --keepParent "$APP" dist/notarisation.zip
  if xcrun notarytool submit dist/notarisation.zip --keychain-profile "$PROFILE" --wait --timeout 15m | tee /dev/stderr | grep -q "status: Accepted"; then
    xcrun stapler staple "$APP" >/dev/null && echo "    app notarisée et agrafée"
  else
    fail "Apple a refusé la notarisation : xcrun notarytool log <id> --keychain-profile $PROFILE"
  fi
  rm -f dist/notarisation.zip
else
  echo "    ! Apple refuse le profil « $PROFILE » (accord à accepter sur developer.apple.com ?) : app signée, non notarisée."
  echo "      Les Transcriptor installés l'acceptent : ils vérifient eux-mêmes la signature."
fi

echo "5/6 Archive"
rm -f dist/Transcriptor.zip
ditto -c -k --keepParent "$APP" dist/Transcriptor.zip

echo "6/6 Publication"
git tag -a "v$VERSION" -m "Transcriptor $VERSION"
git push -q origin main "v$VERSION"
printf '%s\n' "$NOTES" > dist/notes.md
gh release create "v$VERSION" dist/Transcriptor.zip --repo "$REPO" --title "Transcriptor $VERSION" --notes-file dist/notes.md >/dev/null
echo "Publié : https://github.com/$REPO/releases/tag/v$VERSION ($(du -h dist/Transcriptor.zip | cut -f1))"

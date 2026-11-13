#!/bin/bash
# Publie une version de Polhub sur GitHub. Usage : scripts/release.sh 0.3.1 (ou make release VERSION=0.3.1)
#   1. tests ; 2. VERSION ; 3. app signée et vérifiée ; 4. notarisation par Apple ; 5. dist/Polhub.zip ;
#   6. version GitHub créée en brouillon, puis publiée en dernier (l'étiquette vX.Y.Z naît à ce moment).
# Les Polhub installés la trouvent dans l'heure et s'installent seuls, jamais pendant une réunion : ils
# n'acceptent qu'une app signée par l'équipe de l'auteur (Packages/MeetingsMac/Sources/Updates/Verifier.swift).
# Réglages locaux (jamais publiés) : prive/release.env peut définir POLHUB_NOTARY_PROFILE, le profil créé par
# `xcrun notarytool store-credentials`. POLHUB_ALLOW_UNNOTARIZED=1 : publier sans notarisation (déconseillé).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, par exemple 0.3.1}"
REPO="paulmailhes/polhub"
APP="$ROOT/build/Polhub.app"
cd "$ROOT"
[ -f prive/release.env ] && . prive/release.env
PROFILE="${POLHUB_NOTARY_PROFILE:-polhub-notarisation}"

fail() { echo "$*" >&2; echo "Rien n'est publié." >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version attendue sous la forme 0.3.1, pas « $VERSION »."
[ "$(git branch --show-current)" = "main" ] || fail "Publier depuis la branche main."
[ -z "$(git status --porcelain)" ] || fail "Des changements ne sont pas commités."
if [ "$(gh release view "v$VERSION" --repo "$REPO" --json isDraft -q .isDraft 2>/dev/null || true)" = "false" ]; then
  fail "La version v$VERSION est déjà publiée."
fi
NOTES="$(awk -v v="## $VERSION" 'index($0, v) == 1 { on = 1; next } on && /^## / { exit } on' CHANGELOG.md)"
[ -n "$(printf '%s' "$NOTES" | tr -d '[:space:]')" ] || fail "CHANGELOG.md n'a pas de section « ## $VERSION »."

echo "1/6 Tests"
mkdir -p dist
make check >dist/tests.log 2>&1 || { tail -30 dist/tests.log >&2; fail "Des tests échouent (dist/tests.log)."; }

echo "2/6 Version $VERSION"
if [ "$(cat VERSION)" != "$VERSION" ]; then
  echo "$VERSION" > VERSION
  git add VERSION
  git commit -q -m "Version $VERSION"
fi

echo "3/6 App signée"
make app VERSION="$VERSION" >dist/build.log 2>&1 || { tail -30 dist/build.log >&2; fail "La construction a échoué."; }
scripts/verify-bundle.sh "$APP" >/dev/null || fail "L'app ne passe pas ses contrôles (scripts/verify-bundle.sh)."
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUILT" = "$VERSION" ] || fail "L'app construite porte la version $BUILT, pas $VERSION."
codesign --verify --deep --strict -R="$(sed -n 's/.*designated => //p' <(codesign -d -r- "$APP" 2>&1))" "$APP" >/dev/null 2>&1 \
  || fail "La signature de l'app ne tient pas."
# Captured first: with pipefail, `grep -q` closing the pipe early would fail the line.
SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
[[ $'\n'"$SIGNATURE"$'\n' == *$'\n'"TeamIdentifier=CQ43U6XX4Z"$'\n'* ]] || fail "L'app n'est pas signée par l'équipe CQ43U6XX4Z."

echo "4/6 Notarisation"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  ditto -c -k --keepParent "$APP" dist/notarisation.zip
  RESULT="$(xcrun notarytool submit dist/notarisation.zip --keychain-profile "$PROFILE" --wait --timeout 15m 2>&1 || true)"
  rm -f dist/notarisation.zip
  printf '%s\n' "$RESULT" | tail -3
  [[ "$RESULT" == *"status: Accepted"* ]] || fail "Apple a refusé la notarisation (xcrun notarytool log <id> --keychain-profile $PROFILE)."
  xcrun stapler staple "$APP" >/dev/null || fail "L'agrafage du ticket de notarisation a échoué."
elif [ -n "${POLHUB_ALLOW_UNNOTARIZED:-}" ]; then
  echo "    ! profil « $PROFILE » refusé par Apple : app signée mais non notarisée (POLHUB_ALLOW_UNNOTARIZED)."
else
  fail "Apple refuse le profil de notarisation « $PROFILE » (accord à accepter sur developer.apple.com, ou prive/release.env)."
fi

echo "5/6 Archive"
rm -f dist/Polhub.zip
ditto -c -k --keepParent "$APP" dist/Polhub.zip
printf '%s\n' "$NOTES" > dist/notes.md

echo "6/6 Publication"
git push -q origin main
TARGET="$(git rev-parse HEAD)"
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  # A draft left by an interrupted run: its archive and notes are replaced.
  gh release upload "v$VERSION" dist/Polhub.zip --repo "$REPO" --clobber >/dev/null
  gh release edit "v$VERSION" --repo "$REPO" --notes-file dist/notes.md --target "$TARGET" >/dev/null
else
  gh release create "v$VERSION" dist/Polhub.zip --repo "$REPO" --draft --target "$TARGET" \
    --title "Polhub $VERSION" --notes-file dist/notes.md >/dev/null
fi
gh release edit "v$VERSION" --repo "$REPO" --draft=false >/dev/null
git fetch -q --tags origin
echo "Publié : https://github.com/$REPO/releases/tag/v$VERSION ($(du -h dist/Polhub.zip | cut -f1))"

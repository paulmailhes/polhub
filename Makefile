APP      := build/Polhub.app
PRODUCT  := build/DerivedData/Build/Products/Release/Polhub.app
INSTALL  := /Applications/Polhub.app
AGENT    := fr.paulmailhes.polhub.relance
DB       := $(HOME)/Library/Application Support/Polhub/Polhub.sqlite
VERSION  := $(shell cat VERSION)

.PHONY: check gen app app-dev verify install stop release

# Tests des deux paquets, sans micro ni navigateur.
check:
	swift test --package-path Packages/Kernel
	swift test --package-path Packages/MeetingsMac

# Le projet Xcode est généré, jamais versionné.
gen:
	xcodegen generate --quiet

app: gen
	xcodebuild -project Polhub.xcodeproj -scheme Polhub -configuration Release \
		-derivedDataPath build/DerivedData -quiet MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(VERSION) build
	rm -rf $(APP)
	ditto $(PRODUCT) $(APP)

# La version de développement : identifiant .dev, données à part, détection coupée. Jamais installée.
app-dev: gen
	xcodebuild -project Polhub.xcodeproj -scheme PolhubDev -configuration Release \
		-derivedDataPath build/DerivedData -quiet MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(VERSION) build
	rm -rf "build/Polhub Dev.app"
	ditto "build/DerivedData/Build/Products/Release/Polhub Dev.app" "build/Polhub Dev.app"
	scripts/verify-bundle.sh "build/Polhub Dev.app" fr.paulmailhes.polhub.dev

verify:
	scripts/verify-bundle.sh $(APP)

# Change l'état du Mac : seulement avec l'accord de Paul (CONFIRM=oui).
install:
	@test "$(CONFIRM)" = "oui" || { echo "Refusé : relancer avec CONFIRM=oui, après accord de Paul."; exit 1; }
	@n=$$(sqlite3 "$(DB)" "SELECT count(*) FROM meeting WHERE status IN ('pending','recording','presumedEnded') AND deletedAt IS NULL" 2>/dev/null || echo 0); \
		test "$$n" = "0" || { echo "Refusé : une réunion s'enregistre ($$n). Attendre sa fin."; exit 1; }
	@! pgrep -x Polhub >/dev/null || { echo "Refusé : Polhub tourne. Le quitter d'abord (make stop)."; exit 1; }
	rm -rf $(INSTALL)
	ditto $(APP) $(INSTALL)
	@echo "Installé : $(INSTALL)"
	@# The relaunch agent stays loaded (make stop quits cleanly, launchd does not restart it): it starts the new version.
	@if launchctl print gui/$$(id -u)/$(AGENT) >/dev/null 2>&1; then \
		launchctl kickstart gui/$$(id -u)/$(AGENT) && echo "Relancée par l'agent de relance."; \
	else \
		echo "Agent de relance absent : ouvrir Polhub, puis cocher la relance dans le Diagnostic."; \
	fi

# Quitte l'app, sauf si une réunion s'enregistre.
stop:
	@n=$$(sqlite3 "$(DB)" "SELECT count(*) FROM meeting WHERE status IN ('pending','recording','presumedEnded') AND deletedAt IS NULL" 2>/dev/null || echo 0); \
		test "$$n" = "0" || { echo "Refusé : une réunion s'enregistre ($$n)."; exit 1; }
	-pkill -x Polhub
	@sleep 1

# Publie une version sur GitHub (tests, app signée, archive, notes de CHANGELOG.md) : make release VERSION=0.3.1
release:
	scripts/release.sh $(VERSION)

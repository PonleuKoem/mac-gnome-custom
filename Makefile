# mac-gnome-custom — common tasks. `make help` lists them.
APP_DIR   := app
KIT_DIR   := packages/shellkit
SWIFT_DIR := $(KIT_DIR)/macos
DEBUG_APP := $(APP_DIR)/build/macos/Build/Products/Debug/mac-gnome-custom.app
RELEASE_APP := $(APP_DIR)/build/macos/Build/Products/Release/mac-gnome-custom.app
INSTALL_DIR := /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Signing identity for `make install`. A real identity (your Apple Development
# certificate, found automatically) keeps macOS privacy permissions — e.g.
# Accessibility and Screen Recording for window previews — across reinstalls;
# an ad-hoc signature ("-") looks like a new app to macOS on every build.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}')

.PHONY: help gen analyze test test-swift test-dart goldens build release run install uninstall restore wallpapers icon clean

help:
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

gen: ## Regenerate the Pigeon bridge (Dart + Swift) from pigeons/messages.dart
	cd $(KIT_DIR) && dart run pigeon --input pigeons/messages.dart

analyze: ## Static analysis (Dart)
	cd $(APP_DIR) && flutter analyze

test: test-swift test-dart ## All unit tests

test-swift: ## Swift core tests (no Flutter needed)
	cd $(SWIFT_DIR) && swift test

test-dart: ## Dart tests incl. golden images
	cd $(APP_DIR) && flutter test

goldens: ## Re-render golden images after an intentional UI change
	cd $(APP_DIR) && flutter test --update-goldens test/golden_test.dart

build: ## Debug build of the app
	cd $(APP_DIR) && flutter build macos --debug

release: ## Release build (sign/notarize separately, see README)
	cd $(APP_DIR) && flutter build macos --release

run: build ## Build and launch the shell (first run opens onboarding; nothing changes until you press Start)
	open $(DEBUG_APP)

install: release ## Release build → /Applications (quits a running copy first; quitting restores the Dock)
	-osascript -e 'tell application id "dev.ponleu.macGnomeCustom" to quit' 2>/dev/null
	@for i in $$(seq 1 20); do pgrep -f 'mac-gnome-custom.app/Contents/MacOS' >/dev/null || break; sleep 0.5; done
	rm -rf $(INSTALL_DIR)/mac-gnome-custom.app
	ditto $(RELEASE_APP) $(INSTALL_DIR)/mac-gnome-custom.app
	@if [ -n "$(SIGN_ID)" ] && [ "$(SIGN_ID)" != "-" ]; then \
	  echo "Signing with $(SIGN_ID) (macOS may ask to use the key: choose Always Allow)"; \
	  perl -e 'alarm 120; exec @ARGV' codesign --force --deep --sign "$(SIGN_ID)" \
	    --entitlements $(APP_DIR)/macos/Runner/Release.entitlements $(INSTALL_DIR)/mac-gnome-custom.app \
	  || { echo "Signing failed; using an ad-hoc signature (permissions reset on each install)"; \
	       codesign --force --deep --sign - --entitlements $(APP_DIR)/macos/Runner/Release.entitlements $(INSTALL_DIR)/mac-gnome-custom.app; }; \
	fi
	$(LSREGISTER) -f $(INSTALL_DIR)/mac-gnome-custom.app
	@echo "Installed. Open it from Launchpad/Spotlight, or: open $(INSTALL_DIR)/mac-gnome-custom.app"

uninstall: ## Quit and remove the installed app (settings in ~/Library/Application Support/MacGnomeCustom are kept)
	-osascript -e 'tell application id "dev.ponleu.macGnomeCustom" to quit' 2>/dev/null
	@for i in $$(seq 1 20); do pgrep -f 'mac-gnome-custom.app/Contents/MacOS' >/dev/null || break; sleep 0.5; done
	-$(LSREGISTER) -u $(INSTALL_DIR)/mac-gnome-custom.app
	rm -rf $(INSTALL_DIR)/mac-gnome-custom.app

restore: ## Emergency: put macOS back to the first-run snapshot
	@test -x $(DEBUG_APP)/Contents/MacOS/mac-gnome-custom && $(DEBUG_APP)/Contents/MacOS/mac-gnome-custom --restore \
	  || $(RELEASE_APP)/Contents/MacOS/mac-gnome-custom --restore

wallpapers: ## Regenerate the built-in presets' wallpapers (slow: pure Python)
	python3 tools/gen_wallpapers.py
	python3 tools/gen_wallpaper_overprint.py

icon: ## Regenerate the app icon
	swift tools/gen_icon.swift

clean:
	cd $(APP_DIR) && flutter clean
	rm -rf $(SWIFT_DIR)/.build

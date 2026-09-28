.PHONY: setup gen build test test-packages test-app test-ui lint format format-check strings ci archive ipa testflight clean

PACKAGES := HabitCore HabitStore HabitUI
XCODEBUILD := set -o pipefail && xcodebuild -project SpacedHabits.xcodeproj -scheme SpacedHabits
# Hard cap: no single test may run longer than TEST_TIME_LIMIT seconds (xcodebuild rounds up to whole minutes).
TEST_TIME_LIMIT := 60
XCTEST := $(XCODEBUILD) -destination "$$(Scripts/simulator-destination.sh)" test \
	-test-timeouts-enabled YES -default-test-execution-time-allowance $(TEST_TIME_LIMIT) \
	-maximum-test-execution-time-allowance $(TEST_TIME_LIMIT)

setup:        ## install pinned tools
	brew bundle
	pre-commit install

gen:          ## regenerate SpacedHabits.xcodeproj from project.yml + refresh buildServer.json for SourceKit-LSP
	xcodegen generate
	xcode-build-server config -project SpacedHabits.xcodeproj -scheme SpacedHabits

build: gen
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build | xcbeautify

test: test-packages test-app

test-packages: ## package tests via SwiftPM (fast); each package's whole run gets TEST_TIME_LIMIT, builds excluded
	@for pkg in $(PACKAGES); do \
		echo "==> swift test $$pkg"; \
		xcrun swift build --build-tests --package-path Packages/$$pkg || exit 1; \
		Scripts/time-limit.sh $(TEST_TIME_LIMIT) xcrun swift test --skip-build --package-path Packages/$$pkg || exit 1; \
	done

test-app: gen  ## app unit tests via xcodebuild on an iOS simulator
	$(XCTEST) -skip-testing:SpacedHabitsUITests | xcbeautify

test-ui: gen   ## XCUITest smoke flows (~60 s); run by `make ci`, not `make test`
	$(XCTEST) -only-testing:SpacedHabitsUITests | xcbeautify

lint:
	swiftlint lint --strict

format:
	swiftformat .

format-check:
	swiftformat --lint .

strings: gen  ## fill every Localizable.xcstrings (en base) with the strings the sources use
	xcodebuild -exportLocalizations -project SpacedHabits.xcodeproj -localizationPath "$$(mktemp -d)" -exportLanguage en | tail -1

ci: gen format-check lint test test-ui

# Release (§13 M11). Bump CURRENT_PROJECT_VERSION in project.yml before each upload: App Store Connect
# refuses a build number it has seen. The export runs with /usr/bin first on PATH: Xcode's IPA step calls
# `rsync`, and Homebrew's rsync 3.x fails there ("Copy failed").
ARCHIVE := build/SpacedHabits.xcarchive
EXPORT := PATH=/usr/bin:$$PATH xcodebuild -exportArchive -archivePath $(ARCHIVE) -allowProvisioningUpdates

archive: gen  ## Release archive for devices, in build/
	$(XCODEBUILD) -configuration Release -destination 'generic/platform=iOS' -archivePath $(ARCHIVE) \
		-allowProvisioningUpdates archive | xcbeautify

ipa: archive  ## App Store-signed IPA in build/export, without uploading
	rm -rf build/export
	$(EXPORT) -exportPath build/export -exportOptionsPlist Scripts/ExportOptions.plist

testflight: archive  ## upload the archive to App Store Connect (TestFlight)
	plutil -replace destination -string upload -o build/ExportOptions-upload.plist Scripts/ExportOptions.plist
	$(EXPORT) -exportPath build/upload -exportOptionsPlist build/ExportOptions-upload.plist

clean:        ## remove every build artifact, including Xcode's DerivedData for this project
	rm -rf SpacedHabits.xcodeproj buildServer.json DerivedData .build Packages/*/.build build \
		$(HOME)/Library/Developer/Xcode/DerivedData/SpacedHabits-*

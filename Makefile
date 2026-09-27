.PHONY: setup gen build test test-packages test-app test-ui lint format format-check strings ci clean

PACKAGES := HabitCore HabitStore HabitUI
XCODEBUILD := set -o pipefail && xcodebuild -project SpacedHabits.xcodeproj -scheme SpacedHabits
XCTEST := $(XCODEBUILD) -destination "$$(Scripts/simulator-destination.sh)" test

setup:        ## install pinned tools
	brew bundle
	pre-commit install

gen:          ## regenerate SpacedHabits.xcodeproj from project.yml + refresh buildServer.json for SourceKit-LSP
	xcodegen generate
	xcode-build-server config -project SpacedHabits.xcodeproj -scheme SpacedHabits

build: gen
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build | xcbeautify

test: test-packages test-app

test-packages: ## package tests via SwiftPM (fast)
	@for pkg in $(PACKAGES); do \
		echo "==> swift test $$pkg"; \
		xcrun swift test --package-path Packages/$$pkg || exit 1; \
	done

test-app: gen  ## app unit tests via xcodebuild on an iOS simulator
	$(XCTEST) -skip-testing:SpacedHabitsUITests | xcbeautify

test-ui: gen   ## XCUITest smoke flows (~35 s); run by `make ci`, not `make test`
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

clean:
	rm -rf SpacedHabits.xcodeproj buildServer.json DerivedData .build Packages/*/.build

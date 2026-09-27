.PHONY: setup gen build test test-packages test-app lint format format-check ci clean

PACKAGES := HabitCore HabitStore HabitUI
XCODEBUILD := set -o pipefail && xcodebuild -project SpacedHabits.xcodeproj -scheme SpacedHabits

setup:        ## install pinned tools
	brew bundle
	pre-commit install

gen:          ## regenerate SpacedHabits.xcodeproj from project.yml
	xcodegen generate

build: gen
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' build | xcbeautify

test: test-packages test-app

test-packages: ## package tests via SwiftPM (fast)
	@for pkg in $(PACKAGES); do \
		echo "==> swift test $$pkg"; \
		xcrun swift test --package-path Packages/$$pkg || exit 1; \
	done

test-app: gen  ## app tests via xcodebuild on an iOS simulator
	$(XCODEBUILD) -destination "$$(Scripts/simulator-destination.sh)" test | xcbeautify

lint:
	swiftlint lint --strict

format:
	swiftformat .

format-check:
	swiftformat --lint .

ci: gen format-check lint test

clean:
	rm -rf SpacedHabits.xcodeproj DerivedData .build Packages/*/.build

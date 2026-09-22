# Last edited: 2026-09-22 12:27 PT
# Developer commands for TickTick. Run scripts/setup.sh once before the first `make`.

PROJECT := TickTick.xcodeproj
SCHEME := TickTick
DERIVED := build
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -allowProvisioningUpdates
RELEASE_APP := $(DERIVED)/Build/Products/Release/TickTick.app

.PHONY: gen build test lint format install

# Regenerate the project so files added under TickTick/ or TickTickTests/ are picked up.
gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -configuration Debug build

test: gen
	$(XCODEBUILD) -configuration Debug test -destination 'platform=macOS'

lint:
	swiftlint lint --strict
	swiftformat --lint .

format:
	swiftformat .

install: gen
	$(XCODEBUILD) -configuration Release build
	pkill -x TickTick || true
	ditto $(RELEASE_APP) /Applications/TickTick.app
	open /Applications/TickTick.app

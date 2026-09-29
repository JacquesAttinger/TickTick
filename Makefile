# Last edited: 2026-09-29 19:05 CDT
# Developer commands for TickTick. Run scripts/setup.sh once before the first `make`.

PROJECT := TickTick.xcodeproj
SCHEME := TickTick
DERIVED := build
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -allowProvisioningUpdates
RELEASE_APP := $(DERIVED)/Build/Products/Release/TickTick.app

# xcodebuild and SwiftLint need Xcode, not the Command Line Tools.
# When xcode-select points at the Command Line Tools, use /Applications/Xcode.app for these commands.
ifeq ($(findstring .app,$(shell xcode-select -p)),)
ifneq ($(wildcard /Applications/Xcode.app),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

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
	while pgrep -x TickTick >/dev/null; do sleep 0.2; done
	rm -rf /Applications/TickTick.app
	ditto $(RELEASE_APP) /Applications/TickTick.app
	open /Applications/TickTick.app

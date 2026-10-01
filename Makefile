# KinBeacon developer entry points. `make help` lists targets.
SHELL := /bin/bash
PROJECT := KinBeacon.xcodeproj
SCHEME := KinBeacon
# The connected iPhone by default (override: make test DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro').
DEVICE_ID ?= $(shell xcrun xctrace list devices 2>/dev/null | grep -v Simulator | grep -E '\([0-9]+\.[0-9.]+\) \(' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]+)\)$$/\1/')
DESTINATION ?= id=$(DEVICE_ID)
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null || echo cat)
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath DerivedData -allowProvisioningUpdates

.PHONY: help bootstrap project open build run test test-unit test-ui perf screenshots appstore-screenshots archive export bump lint format icon clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install tooling (XcodeGen, SwiftLint, SwiftFormat, xcbeautify)
	brew install xcodegen swiftlint swiftformat xcbeautify

project: ## Generate KinBeacon.xcodeproj from project.yml
	xcodegen generate

open: project ## Generate and open in Xcode
	open $(PROJECT)

build: project ## Debug build for the destination (default: connected iPhone)
	set -o pipefail; $(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' build | $(XCBEAUTIFY)

run: build ## Build, install and launch on the connected iPhone (demo, parent role)
	xcrun devicectl device install app --device $(DEVICE_ID) DerivedData/Build/Products/Debug-iphoneos/KinBeacon.app
	xcrun devicectl device process launch --terminate-existing --device $(DEVICE_ID) com.lynkto.kinbeacon -- -KinRole parent

test-unit: project ## 113 swift-testing tests, hosted so they run on a real iPhone
	set -o pipefail; $(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' test -only-testing:KinKitTests | $(XCBEAUTIFY)

test-ui: project ## Critical-path XCUITests (parent, child, onboarding) + screenshot walk-through
	set -o pipefail; $(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' test -only-testing:KinBeaconUITests -skip-testing:KinBeaconUITests/LaunchPerformanceTests | $(XCBEAUTIFY)

test: test-unit test-ui ## All functional tests

perf: project ## Cold-launch time (Release, XCTApplicationLaunchMetric, 5 iterations) on the device
	set -o pipefail; $(XCODEBUILD) -scheme KinBeaconPerf -destination '$(DESTINATION)' test | grep -E "measured|Test Case"

screenshots: project ## Regenerate docs/screenshots from the UI walk-through
	rm -rf build/shots.xcresult build/shots
	$(XCODEBUILD) -scheme $(SCHEME) -destination '$(DESTINATION)' -resultBundlePath build/shots.xcresult test -only-testing:KinBeaconUITests/ScreenshotTests
	xcrun xcresulttool export attachments --path build/shots.xcresult --output-path build/shots
	python3 scripts/export_screenshots.py build/shots docs/screenshots

appstore-screenshots: project ## 6.9" App Store screenshots from the iPhone 17 Pro Max simulator → docs/appstore/screenshots
	rm -rf build/appstore.xcresult build/appstore
	$(XCODEBUILD) -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -resultBundlePath build/appstore.xcresult \
		test -only-testing:KinBeaconUITests/ScreenshotTests
	xcrun xcresulttool export attachments --path build/appstore.xcresult --output-path build/appstore
	python3 scripts/export_screenshots.py build/appstore docs/appstore/screenshots

bump: ## Increment CURRENT_PROJECT_VERSION in project.yml (build number for TestFlight)
	python3 -c "import re;p='project.yml';s=open(p).read();n=int(re.search(r'CURRENT_PROJECT_VERSION: \"(\d+)\"',s).group(1))+1;open(p,'w').write(re.sub(r'CURRENT_PROJECT_VERSION: \"\d+\"',f'CURRENT_PROJECT_VERSION: \"{n}\"',s));print('build',n)"
	xcodegen generate

archive: project ## Release archive (needs the Family Controls *Distribution* entitlement approved by Apple)
	$(XCODEBUILD) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS' -archivePath build/KinBeacon.xcarchive archive

export: archive ## Export an App Store .ipa → build/export (upload with Xcode Organizer or Transporter)
	xcodebuild -exportArchive -archivePath build/KinBeacon.xcarchive -exportPath build/export \
		-exportOptionsPlist Config/ExportOptions-AppStore.plist -allowProvisioningUpdates

lint: ## SwiftLint (strict) + SwiftFormat (check only)
	swiftlint lint --strict
	swiftformat --lint .

format: ## Auto-format sources
	swiftformat .
	swiftlint lint --fix

icon: ## Regenerate the App Store icon
	python3 scripts/make_app_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

clean: ## Remove build products
	rm -rf DerivedData build

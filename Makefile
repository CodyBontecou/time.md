# time.md Build Commands
# Usage: make <target>

.PHONY: help build-mac clean release-mac sign-update appcast-template bump-build lint format check version stats open logs-mac

# Default target
help:
	@echo "time.md Build Commands"
	@echo ""
	@echo "Development:"
	@echo "  make build-mac     Build macOS app"
	@echo "  make clean         Clean build artifacts"
	@echo ""
	@echo "Release (Sparkle / GitHub Releases):"
	@echo "  make release-mac   Build, notarize, and ZIP for Sparkle release"
	@echo "  make sign-update   Sign release ZIP for Sparkle auto-updates"
	@echo "  make appcast-template  Show appcast.xml entry template"
	@echo "  make bump-build    Increment build number"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint          Check code style (SwiftLint)"
	@echo "  make format        Format code (SwiftFormat)"
	@echo "  make check         Run lint + build (CI check)"
	@echo ""
	@echo "Utilities:"
	@echo "  make open          Open Xcode project"
	@echo "  make version       Show current version"
	@echo "  make stats         Show project statistics"

# Build targets
build-mac:
	xcodebuild -scheme time.md \
		-destination 'platform=macOS' \
		build

# CI check (lint + build)
check: lint build-mac
	@echo "All checks passed!"

# Clean build artifacts
clean:
	rm -rf build/
	rm -rf ~/Library/Developer/Xcode/DerivedData/time.md-*
	@echo "Build artifacts cleaned"

# Code quality
lint:
	@echo "Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml 2>/dev/null || swiftlint lint; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

format:
	@echo "Running SwiftFormat..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat . --config .swiftformat 2>/dev/null || swiftformat .; \
	else \
		echo "SwiftFormat not installed. Install with: brew install swiftformat"; \
	fi

# Versioning helpers
version:
	@echo "Current version info:"
	@grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" time.md.xcodeproj/project.pbxproj | head -4

bump-build:
	@echo "Incrementing build number..."
	@xcrun agvtool next-version -all
	@echo "Build number incremented"

# Development helpers
open:
	open time.md.xcodeproj

logs-mac:
	@echo "Streaming macOS logs (Ctrl+C to stop)..."
	log stream --predicate 'subsystem BEGINSWITH "com.codybontecou.time.md"' --info

# Project statistics
stats:
	@echo "=== time.md Project Statistics ==="
	@echo ""
	@echo "Swift files:"
	@find . -name "*.swift" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./node_modules/*" | wc -l | tr -d ' '
	@echo ""
	@echo "Lines of code:"
	@find . -name "*.swift" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./node_modules/*" -exec cat {} \; | wc -l | tr -d ' '
	@echo ""
	@echo "Test files:"
	@find time.mdTests -name "*.swift" 2>/dev/null | wc -l | tr -d ' '
	@echo ""
	@echo "Documentation files:"
	@find . -name "*.md" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.pi/*" -maxdepth 3 | wc -l | tr -d ' '

# ============================================================================
# SPARKLE AUTO-UPDATES
# ============================================================================

VERSION := $(shell grep -m1 'MARKETING_VERSION' time.md.xcodeproj/project.pbxproj | sed 's/.*= //' | tr -d ';' | tr -d ' ')
DEVELOPER_ID := "Developer ID Application: Cody Russell Bontecou (67KC823C9A)"
TEAM_ID := 67KC823C9A
BUNDLE_ID := com.bontecou.time.md
SPARKLE_BIN := $(shell find ~/Library/Developer/Xcode/DerivedData/time.md-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
BUILD_NUMBER := $(shell grep -m1 'CURRENT_PROJECT_VERSION' time.md.xcodeproj/project.pbxproj | sed 's/.*= //' | tr -d ';' | tr -d ' ')

# Sign a release ZIP for Sparkle updates
sign-update:
	@if [ -z "$(SPARKLE_BIN)" ]; then \
		echo "Error: Sparkle tools not found. Run 'make build-mac' first to fetch packages."; \
		exit 1; \
	fi
	@if [ ! -f "time.md-v$(VERSION)-macOS.zip" ]; then \
		echo "Error: time.md-v$(VERSION)-macOS.zip not found."; \
		echo "Run 'make release-mac' first to create the release ZIP."; \
		exit 1; \
	fi
	@echo "=== Signing time.md-v$(VERSION)-macOS.zip for Sparkle ==="
	@echo ""
	@$(SPARKLE_BIN)/sign_update time.md-v$(VERSION)-macOS.zip
	@echo ""
	@echo "Copy the edSignature above into appcast.xml"

# Build, notarize, and prepare for Sparkle release
release-mac:
	@echo "=== Building time.md v$(VERSION) (build $(BUILD_NUMBER)) for Release ==="
	@echo ""
	@# Clean previous builds
	rm -rf build/release time.md-v$(VERSION)-macOS time.md-v$(VERSION)-macOS.zip
	mkdir -p build/release
	@# Build release archive
	@echo "► Building release archive..."
	xcodebuild -scheme time.md \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath build/release/time.md.xcarchive \
		archive
	@# Export the app
	@echo "► Exporting app..."
	xcodebuild -exportArchive -allowProvisioningUpdates \
		-archivePath build/release/time.md.xcarchive \
		-exportPath build/release \
		-exportOptionsPlist ExportOptions-macOS.plist
	@# Notarize the app
	@echo "► Notarizing app (this may take a few minutes)..."
	ditto -c -k --keepParent build/release/time.md.app build/release/time.md-notarize.zip
	xcrun notarytool submit build/release/time.md-notarize.zip \
		--keychain-profile "notarytool-profile" \
		--wait
	@# Staple the app
	@echo "► Stapling notarization ticket..."
	xcrun stapler staple build/release/time.md.app
	@# Create release ZIP (app only, for Sparkle)
	@echo "► Creating release ZIP..."
	mkdir -p time.md-v$(VERSION)-macOS
	cp -R build/release/time.md.app time.md-v$(VERSION)-macOS/
	ditto -c -k --keepParent time.md-v$(VERSION)-macOS time.md-v$(VERSION)-macOS.zip
	@echo ""
	@echo "=== Release Build Complete ==="
	@echo "ZIP: time.md-v$(VERSION)-macOS.zip"
	@echo "Size: $$(du -h time.md-v$(VERSION)-macOS.zip | cut -f1)"
	@echo "Bytes: $$(stat -f%z time.md-v$(VERSION)-macOS.zip)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'make sign-update' to get the Sparkle signature"
	@echo "  2. Update appcast.xml with the signature and file size"
	@echo "  3. Create a GitHub release and upload the ZIP"
	@echo "  4. Push appcast.xml to main branch"

# Show appcast.xml template for new release
appcast-template:
	@echo ""
	@echo "Add this to appcast.xml (after <channel>, before existing <item>s):"
	@echo ""
	@echo "        <item>"
	@echo "            <title>Version $(VERSION)</title>"
	@echo "            <pubDate>$$(date -R)</pubDate>"
	@echo "            <sparkle:version>$(BUILD_NUMBER)</sparkle:version>"
	@echo "            <sparkle:shortVersionString>$(VERSION)</sparkle:shortVersionString>"
	@echo "            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
	@echo "            <description>"
	@echo "                <![CDATA["
	@echo "                    <h2>What's New in $(VERSION)</h2>"
	@echo "                    <ul>"
	@echo "                        <li>YOUR CHANGES HERE</li>"
	@echo "                    </ul>"
	@echo "                ]]>"
	@echo "            </description>"
	@echo "            <enclosure"
	@echo "                url=\"https://github.com/codybontecou/time.md/releases/download/v$(VERSION)/time.md-v$(VERSION)-macOS.zip\""
	@echo "                length=\"$$(stat -f%z time.md-v$(VERSION)-macOS.zip 2>/dev/null || echo 'FILE_SIZE_BYTES')\""
	@echo "                type=\"application/octet-stream\""
	@echo "                sparkle:edSignature=\"YOUR_SIGNATURE_HERE\""
	@echo "            />"
	@echo "        </item>"
	@echo ""

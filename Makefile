# Timeprint Build Commands
# Usage: make <target>

.PHONY: help build-mac build-ios test archive upload clean

# Default target
help:
	@echo "Timeprint Build Commands"
	@echo ""
	@echo "Development:"
	@echo "  make build-mac     Build macOS app"
	@echo "  make build-ios     Build iOS app (simulator)"
	@echo "  make build-all     Build both macOS and iOS"
	@echo "  make test          Run unit tests"
	@echo "  make clean         Clean build artifacts"
	@echo ""
	@echo "Release:"
	@echo "  make archive       Archive iOS app for App Store"
	@echo "  make upload        Archive and upload to App Store Connect"
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
	xcodebuild -scheme Timeprint \
		-destination 'platform=macOS' \
		build

build-ios:
	xcodebuild -scheme TimeprintIOS \
		-destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
		build

build-ios-device:
	xcodebuild -scheme TimeprintIOS \
		-destination 'generic/platform=iOS' \
		build

build-all: build-mac build-ios
	@echo "All builds succeeded!"

# CI check (lint + build)
check: lint build-all
	@echo "All checks passed!"

# Test target
test:
	xcodebuild -scheme TimeprintIOS \
		-destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
		test

# Archive for App Store
ARCHIVE_PATH = build/TimeprintIOS.xcarchive
EXPORT_PATH = build/export

archive:
	@echo "Archiving TimeprintIOS..."
	xcodebuild -scheme TimeprintIOS \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		archive
	@echo "Archive created at $(ARCHIVE_PATH)"

# Export and upload to App Store Connect
upload: archive
	@echo "Exporting for App Store Connect..."
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_PATH) \
		-exportOptionsPlist ExportOptions.plist
	@echo "Upload complete! Check App Store Connect for the build."

# Clean build artifacts
clean:
	rm -rf build/
	rm -rf ~/Library/Developer/Xcode/DerivedData/Timeprint-*
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
	@grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" Timeprint.xcodeproj/project.pbxproj | head -4

bump-build:
	@echo "Incrementing build number..."
	@xcrun agvtool next-version -all
	@echo "Build number incremented"

# Development helpers
open:
	open Timeprint.xcodeproj

simulator:
	open -a Simulator

logs-ios:
	@echo "Streaming iOS logs (Ctrl+C to stop)..."
	log stream --predicate 'subsystem BEGINSWITH "com.codybontecou.Timeprint"' --info

logs-mac:
	@echo "Streaming macOS logs (Ctrl+C to stop)..."
	log stream --predicate 'subsystem BEGINSWITH "com.codybontecou.Timeprint"' --info

# Project statistics
stats:
	@echo "=== Timeprint Project Statistics ==="
	@echo ""
	@echo "Swift files:"
	@find . -name "*.swift" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./node_modules/*" | wc -l | tr -d ' '
	@echo ""
	@echo "Lines of code:"
	@find . -name "*.swift" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./node_modules/*" -exec cat {} \; | wc -l | tr -d ' '
	@echo ""
	@echo "Test files:"
	@find TimeprintTests -name "*.swift" 2>/dev/null | wc -l | tr -d ' '
	@echo ""
	@echo "Documentation files:"
	@find . -name "*.md" -not -path "./.build/*" -not -path "./DerivedData/*" -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.pi/*" -maxdepth 3 | wc -l | tr -d ' '

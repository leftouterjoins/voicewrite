.PHONY: build release app run debug clean install uninstall notarize notarize-status notarize-log

APP_NAME := VoiceWrite
BUILD_DIR := .build
APP_BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications
# Development signing (for local testing)
DEV_IDENTITY := Apple Development: support@pineridgeranch.net (Z42AQ7N7KX)
# Distribution signing (for release)
DIST_IDENTITY := Developer ID Application: Pineridge Ranch Technologies LLC (4GB7LATCNU)
CODESIGN_IDENTITY := $(DIST_IDENTITY)
ENTITLEMENTS := VoiceWrite/VoiceWrite.entitlements
TEAM_ID := 4GB7LATCNU

# Debug build
build:
	swift build
	@echo "Debug build complete"

# Release build
release:
	swift build -c release
	@echo "Release build complete"

# Create app bundle (release)
app: release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp VoiceWrite/Info.plist $(APP_BUNDLE)/Contents/
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Copy SwiftPM resource bundles
	@cp -r $(BUILD_DIR)/arm64-apple-macosx/release/*.bundle $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@codesign --force --deep --sign "$(CODESIGN_IDENTITY)" --options runtime --entitlements "$(ENTITLEMENTS)" $(APP_BUNDLE)
	@echo "Created and signed $(APP_BUNDLE)"

# Create distribution zip and notarize
notarize: app
	@rm -f $(APP_NAME)-*.zip
	@zip -r $(APP_NAME)-1.0.0.zip $(APP_BUNDLE)
	@echo "Submitting for notarization..."
	@xcrun notarytool submit $(APP_NAME)-1.0.0.zip --keychain-profile "notarytool" --wait
	@echo "Stapling notarization ticket..."
	@xcrun stapler staple $(APP_BUNDLE)
	@rm -f $(APP_NAME)-1.0.0.zip
	@zip -r $(APP_NAME)-1.0.0.zip $(APP_BUNDLE)
	@echo "Notarized $(APP_NAME)-1.0.0.zip ready for distribution"

# Check notarization status
notarize-status:
	@xcrun notarytool history --keychain-profile "notarytool"

# Get notarization log (usage: make notarize-log ID=<submission-id>)
notarize-log:
	@xcrun notarytool log $(ID) --keychain-profile "notarytool"

# Run the app
run: app
	open $(APP_BUNDLE)

# Run with console output (for debugging)
debug: app
	lldb $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) -o run

# Install to /Applications
install: app
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -r $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(APP_BUNDLE)"

# Uninstall from /Applications
uninstall:
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Removed $(INSTALL_DIR)/$(APP_BUNDLE)"

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

# Show help
help:
	@echo "VoiceWrite Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build     - Debug build"
	@echo "  release   - Release build"
	@echo "  app              - Create signed VoiceWrite.app bundle"
	@echo "  notarize         - Submit for notarization and wait"
	@echo "  notarize-status  - Check notarization history"
	@echo "  notarize-log     - Get log (make notarize-log ID=xxx)"
	@echo "  run              - Build and run the app"
	@echo "  debug            - Run with lldb for debugging"
	@echo "  install          - Install to /Applications"
	@echo "  uninstall        - Remove from /Applications"
	@echo "  clean            - Clean build artifacts"
	@echo "  help             - Show this help"
	@echo ""
	@echo "Note: Uses macOS SpeechAnalyzer API (requires macOS 26+)"

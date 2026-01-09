.PHONY: build release app run debug clean install uninstall notarize notarize-status notarize-log generate-keys sign-update inputmethod install-inputmethod uninstall-inputmethod

APP_NAME := VoiceWrite
BUILD_DIR := .build
APP_BUNDLE := $(APP_NAME).app
IM_BUNDLE := VoiceWriteInputMethod.app
IM_INSTALL_DIR := $(HOME)/Library/Input\ Methods
INSTALL_DIR := /Applications
VERSION := 2.0.0
# Development signing (for local testing)
DEV_IDENTITY := Apple Development: support@pineridgeranch.net (Z42AQ7N7KX)
# Distribution signing (for release)
DIST_IDENTITY := Developer ID Application: Pineridge Ranch Technologies LLC (4GB7LATCNU)
CODESIGN_IDENTITY := $(DIST_IDENTITY)
ENTITLEMENTS := VoiceWrite/VoiceWrite.entitlements
TEAM_ID := 4GB7LATCNU
# Sparkle framework path (after swift build resolves it)
SPARKLE_XCFRAMEWORK := $(BUILD_DIR)/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework

# Debug build
build:
	swift build
	@echo "Debug build complete"

# Release build
release:
	@# Ensure dependencies are resolved
	swift package resolve
	@# Patch KeyboardShortcuts to use resourceURL for bundle lookup (works with macOS app bundles)
	@sed -i '' 's|NSLocalizedString(self, bundle: .module, comment: self)|NSLocalizedString(self, bundle: Bundle.main.resourceURL.flatMap { $$0.appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle") }.flatMap { Bundle(url: $$0) } ?? .module, comment: self)|g' \
		.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift 2>/dev/null || true
	swift build -c release
	@echo "Release build complete"

# Create app bundle (release)
app: release inputmethod
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	@cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@# Add rpath so the binary can find Sparkle.framework in Frameworks/
	@install_name_tool -add_rpath @executable_path/../Frameworks $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp VoiceWrite/Info.plist $(APP_BUNDLE)/Contents/
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Copy SwiftPM resource bundles to Contents/Resources/ (patched accessor looks here)
	@cp -r $(BUILD_DIR)/arm64-apple-macosx/release/*.bundle $(APP_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Copy app icon to Resources
	@cp VoiceWrite/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@# Embed Input Method in Resources (auto-installed to ~/Library/Input Methods on launch)
	@cp -R $(IM_BUNDLE) $(APP_BUNDLE)/Contents/Resources/
	@# Copy Sparkle framework to Frameworks/
	@cp -R $(SPARKLE_XCFRAMEWORK) $(APP_BUNDLE)/Contents/Frameworks/
	@# Sign Sparkle components (order matters - XPC services first, never use --deep)
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime --preserve-metadata=entitlements \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime \
		"$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"
	@# Sign resource bundles (KeyboardShortcuts)
	@for bundle in $(APP_BUNDLE)/Contents/Resources/*.bundle; do \
		codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime "$$bundle" 2>/dev/null || true; \
	done
	@# Sign embedded Input Method
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime \
		"$(APP_BUNDLE)/Contents/Resources/$(IM_BUNDLE)"
	@# Sign main app last
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime --entitlements "$(ENTITLEMENTS)" $(APP_BUNDLE)
	@echo "Created and signed $(APP_BUNDLE)"

# Create distribution zip and notarize
notarize: app
	@rm -f $(APP_NAME)-*.zip
	@# Use ditto (not zip) to preserve symlinks and metadata - required for notarization
	@ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-notarize.zip
	@echo "Submitting for notarization..."
	@xcrun notarytool submit $(APP_NAME)-notarize.zip --keychain-profile "notarytool" --wait
	@echo "Stapling notarization ticket..."
	@xcrun stapler staple $(APP_BUNDLE)
	@rm -f $(APP_NAME)-notarize.zip
	@# Create final distribution archive
	@ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-$(VERSION).zip
	@echo "Notarized $(APP_NAME)-$(VERSION).zip ready for distribution"

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
	rm -rf $(IM_BUNDLE)

# Build Input Method bundle
inputmethod:
	swift build -c release --product VoiceWriteInputMethod
	@rm -rf $(IM_BUNDLE)
	@mkdir -p $(IM_BUNDLE)/Contents/MacOS
	@mkdir -p $(IM_BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/release/VoiceWriteInputMethod $(IM_BUNDLE)/Contents/MacOS/
	@cp VoiceWriteInputMethod/Info.plist $(IM_BUNDLE)/Contents/
	@echo "APPL????" > $(IM_BUNDLE)/Contents/PkgInfo
	@# Copy app icon
	@cp VoiceWrite/AppIcon.icns $(IM_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Copy menu bar icon
	@cp VoiceWriteInputMethod/Resources/MenuIcon.tiff $(IM_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Copy localized strings
	@cp -R InputMethodResources/en.lproj $(IM_BUNDLE)/Contents/Resources/ 2>/dev/null || true
	@# Sign the input method
	@codesign -f -s "$(CODESIGN_IDENTITY)" -o runtime $(IM_BUNDLE)
	@echo "Created and signed $(IM_BUNDLE)"

# Install Input Method to user Library (no admin required)
install-inputmethod: inputmethod
	@mkdir -p "$(IM_INSTALL_DIR)"
	@rm -rf "$(IM_INSTALL_DIR)/$(IM_BUNDLE)"
	@cp -r $(IM_BUNDLE) "$(IM_INSTALL_DIR)/"
	@echo "Installed to $(IM_INSTALL_DIR)/$(IM_BUNDLE)"
	@echo "Add 'VoiceWrite' in System Settings > Keyboard > Input Sources"

# Uninstall Input Method
uninstall-inputmethod:
	@rm -rf "$(IM_INSTALL_DIR)/$(IM_BUNDLE)"
	@echo "Removed. You may need to log out and back in."

# Generate Sparkle EdDSA keys (one-time setup)
generate-keys:
	@echo "Generating Sparkle EdDSA keypair..."
	@$(BUILD_DIR)/artifacts/sparkle/Sparkle/bin/generate_keys
	@echo ""
	@echo "IMPORTANT: Copy the public key above to Info.plist (SUPublicEDKey)"
	@echo "The private key is stored in your Keychain - BACK IT UP!"

# Sign an update archive for Sparkle (usage: make sign-update FILE=VoiceWrite-1.2.0.zip)
sign-update:
	@$(BUILD_DIR)/artifacts/sparkle/Sparkle/bin/sign_update $(FILE)

# Show help
help:
	@echo "VoiceWrite Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build               - Debug build"
	@echo "  release             - Release build"
	@echo "  app                 - Create signed VoiceWrite.app bundle"
	@echo "  notarize            - Submit for notarization and wait"
	@echo "  notarize-status     - Check notarization history"
	@echo "  notarize-log        - Get log (make notarize-log ID=xxx)"
	@echo "  run                 - Build and run the app"
	@echo "  debug               - Run with lldb for debugging"
	@echo "  install             - Install to /Applications"
	@echo "  uninstall           - Remove from /Applications"
	@echo "  clean               - Clean build artifacts"
	@echo "  generate-keys       - Generate Sparkle EdDSA keypair (one-time)"
	@echo "  sign-update         - Sign update archive (FILE=xxx.zip)"
	@echo "  inputmethod         - Build Input Method bundle"
	@echo "  install-inputmethod - Install Input Method (requires admin)"
	@echo "  uninstall-inputmethod - Remove Input Method"
	@echo "  help                - Show this help"
	@echo ""
	@echo "Note: Uses macOS SpeechAnalyzer API (requires macOS 26+)"

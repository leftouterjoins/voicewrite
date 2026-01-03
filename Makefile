.PHONY: build release app run debug clean install uninstall

APP_NAME := VoiceWrite
BUILD_DIR := .build
APP_BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications
CODESIGN_IDENTITY := Apple Development: support@pineridgeranch.net (Z42AQ7N7KX)

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
	@codesign --force --deep --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)
	@echo "Created and signed $(APP_BUNDLE)"

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
	@echo "  app       - Create signed VoiceWrite.app bundle"
	@echo "  run       - Build and run the app"
	@echo "  debug     - Run with lldb for debugging"
	@echo "  install   - Install to /Applications"
	@echo "  uninstall - Remove from /Applications"
	@echo "  clean     - Clean build artifacts"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Note: Uses macOS SpeechAnalyzer API (requires macOS 26+)"

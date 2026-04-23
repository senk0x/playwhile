# Builds the Swift executable and wraps it into a macOS .app bundle.
# An .app bundle is required so Info.plist (and its LSUIElement=1 key)
# takes effect — which is what makes the app a background/accessory
# utility with no Dock icon.

APP_NAME    := PlayWhile
CONFIG      ?= release
BUILD_DIR   := .build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
BIN_SRC     := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
PLIST_SRC   := Resources/Info.plist

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_SRC)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp "$(PLIST_SRC)" "$(APP_BUNDLE)/Contents/Info.plist"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@echo "Built $(APP_BUNDLE)"

run: bundle
	open "$(APP_BUNDLE)"

clean:
	rm -rf "$(BUILD_DIR)"
